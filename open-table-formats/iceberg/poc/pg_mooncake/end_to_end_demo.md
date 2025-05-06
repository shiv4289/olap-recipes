### Queries
Source: https://www.e6data.com/blog/iceberg-metadata-evolution-after-compaction

Note: This requires a bit more memory so it is advised to increase your colima/docker desktop memory limits.
```shell
colima start --cpu 6 --memory 12
```

### Docker Setup

```mermaid
graph TD
    subgraph Storage
        MINIO["MinIO<br/>(S3-compatible Storage)"]
        MC["mc<br/>(MinIO CLI)"]
    end

    subgraph Catalog
        REST["Iceberg REST Catalog<br/>(Port: 8181)"]
    end

    subgraph Compute
        SPARK["Spark-Iceberg<br/>(Ports: 8888, 8080, etc.)"]
        CLICKHOUSE["ClickHouse<br/>(Parquet I/O via S3)"]
        PG_MOONCAKE["pg_mooncake<br/>(Ports: 5432)"]
    end

    MC --> MINIO
    REST --> MINIO
    SPARK --> MINIO
    SPARK --> REST
    CLICKHOUSE --> MINIO
    CLICKHOUSE --> REST
    PG_MOONCAKE --> MINIO
```

#### Setup
Note: You can view the s3 directories and folders using minio ui
```shell
http://localhost:9001/login
username: admin
password: passwrod
```
All the commands from here on should be run from within the directory. If you are in a different directory, cd into the directory **end to end**.

```shell
# Run only if not the end to end directory
cd end to end
```

Once in the directory, grant executable permissions to setup.sh and teardown.sh

```shell
chmod +x ./setup.sh ./teardown.sh
```

### Setup Script Summary (`setup.sh`)

This script automates the setup of a local lakehouse environment with Spark, Iceberg, MinIO, ClickHouse, and a REST catalog.

**Key actions:**

- Creates required directories (`lakehouse`, `minio/data`, `notebooks`, etc.)
- Downloads NYC Taxi dataset (`trips_0`, `trips_1`, `trips_2`) and extracts it into ClickHouse's import directory
- Downloads necessary JARs for Spark to connect with S3 (Hadoop AWS and AWS SDK)
- Starts all services using Docker Compose
- Initializes the ClickHouse table and loads the dataset using `init-clickhouse.sh`

### ClickHouse Initialization Script Summary (`init-clickhouse.sh`)

This script is executed inside the ClickHouse container to:

- Wait for the ClickHouse server to be ready
- Create a `trips` table (NYC Taxi schema) with geolocation, fare, and trip info
- Import all `.tsv` dataset files from `/var/lib/clickhouse/data_import` into the `trips` table

The table uses the `MergeTree` engine with `pickup_datetime` and `dropoff_datetime` as the primary key.

### Teardown Script Summary (`teardown.sh`)

Use this script to clean up the entire lakehouse environment:

- Stops and removes all Docker containers and volumes
- Deletes local project directories:
  - `lakehouse/` (Iceberg data)
  - `minio/` (object store data)
  - `clickhouse/` (database files and import data)

## Flow 1: Moving Data from Clickhouse to Iceberg Tables

### Step 1: Data from clickhouse tables into S3 as a parquet file

Fire up clickhouse client

```shell
docker exec -it clickhouse clickhouse-client
```
The pre created **trips** table is within default database. We will write this table as a parquet file into s3 bucket.

```sql
INSERT INTO FUNCTION s3(
  'http://minio:9000/lakehouse/clickhouse_generated/trips.parquet',
  'admin', 'password',
  'Parquet'
)
SELECT * FROM trips;
```

This parquet file can be then queried using clickhouse itself.

Count of rows from parquet file
```sql
SELECT count(*) FROM s3('http://minio:9000/lakehouse/clickhouse_generated/trips.parquet','admin','password');
```
It should match the count of rows in trips table
```sql
SELECT count(*) from trips;
```

### Step 2: Creating iceberg table using this parquet file
Fire up spark sql: For some reason spark sql does not inherit the configurations passed 
as the env variables in docker compose file. Hence we are configuring the same here.

```shell
docker exec -it spark-iceberg spark-sql \
  --conf spark.driver.extraClassPath="/opt/spark-extra-jars/*" \
  --conf spark.executor.extraClassPath="/opt/spark-extra-jars/*" \
  --conf spark.hadoop.fs.s3a.access.key=admin \
  --conf spark.hadoop.fs.s3a.secret.key=password \
  --conf spark.hadoop.fs.s3a.endpoint=http://minio:9000 \
  --conf spark.hadoop.fs.s3a.path.style.access=true
```
Create table
```sql
CREATE TABLE demo.iceberg.trips (
                                       trip_id             INT,
                                       pickup_datetime     TIMESTAMP,
                                       dropoff_datetime    TIMESTAMP,
                                       pickup_longitude    DOUBLE,
                                       pickup_latitude     DOUBLE,
                                       dropoff_longitude   DOUBLE,
                                       dropoff_latitude    DOUBLE,
                                       passenger_count     INT,
                                       trip_distance       FLOAT,
                                       fare_amount         FLOAT,
                                       extra               FLOAT,
                                       tip_amount          FLOAT,
                                       tolls_amount        FLOAT,
                                       total_amount        FLOAT,
                                       payment_type        STRING,
                                       pickup_ntaname      STRING,
                                       dropoff_ntaname     STRING
) USING ICEBERG
PARTITIONED BY (
    payment_type
);
```

Insert into this iceberg table using parquet file ingested before
```sql
INSERT INTO demo.iceberg.trips
SELECT * FROM parquet.`s3a://lakehouse/clickhouse_generated/trips.parquet`;
```
You can query the count of rows using this spark sql query:
```sql
SELECT COUNT(*) FROM demo.iceberg.trips;
```

## Flow 2: Querying iceberg tables using pg_mooncake

You can Query this iceberg table using pg_mooncake

Fire up pgmooncake client

```shell
docker exec -it pgmooncake psql -U admin
```

Enable wide display
```sql
\x
```

Enable pg_mooncake extension

```sql
CREATE EXTENSION IF NOT EXISTS pg_mooncake;
```

Create a secret so that pg_mooncake can access the s3 buckets.

```sql
SELECT mooncake.create_secret(
  'minio-secret',
  'S3',
  'admin',   -- AWS_ACCESS_KEY_ID
  'password', -- AWS_SECRET_ACCESS_KEY
  '{
    "ENDPOINT": "minio:9000",
    "REGION": "us-east-1",
    "USE_SSL":"false"
  }'
);
```

Verify that secret exists

```sql
select * from mooncake.secrets;
```

You can read parquet files that we wrote eariler: 

```sql
SELECT count(*) FROM mooncake.read_parquet('s3://lakehouse/clickhouse_generated/trips.parquet') AS t(
  trip_id             INTEGER,
  pickup_datetime     TIMESTAMP,
  dropoff_datetime    TIMESTAMP,
  pickup_longitude    DOUBLE PRECISION,
  pickup_latitude     DOUBLE PRECISION,
  dropoff_longitude   DOUBLE PRECISION,
  dropoff_latitude    DOUBLE PRECISION,
  passenger_count     SMALLINT,
  trip_distance       REAL,
  fare_amount         REAL,
  extra               REAL,
  tip_amount          REAL,
  tolls_amount        REAL,
  total_amount        REAL,
  payment_type        TEXT,
  pickup_ntaname      TEXT,
  dropoff_ntaname     TEXT
);
```

```sql
SELECT * FROM mooncake.read_parquet('s3://lakehouse/clickhouse_generated/trips.parquet') AS t(
  trip_id             INTEGER,
  pickup_datetime     TIMESTAMP,
  dropoff_datetime    TIMESTAMP,
  pickup_longitude    DOUBLE PRECISION,
  pickup_latitude     DOUBLE PRECISION,
  dropoff_longitude   DOUBLE PRECISION,
  dropoff_latitude    DOUBLE PRECISION,
  passenger_count     SMALLINT,
  trip_distance       REAL,
  fare_amount         REAL,
  extra               REAL,
  tip_amount          REAL,
  tolls_amount        REAL,
  total_amount        REAL,
  payment_type        TEXT,
  pickup_ntaname      TEXT,
  dropoff_ntaname     TEXT
) where trip_id=1200853689;
```

### Scanning iceberg tables: 

pg_mooncake internally uses duckdb's iceberg functions. Since duckdb iceberg is not integrated with rest catalog yet, 
you will need to provide the exact metadata path to read the iceberg table files.

```sql
SELECT count(*) FROM mooncake.iceberg_scan('s3://lakehouse/iceberg/trips/metadata/<metadata-file-name>') AS t(
  trip_id             INTEGER,
  pickup_datetime     TIMESTAMP,
  dropoff_datetime    TIMESTAMP,
  pickup_longitude    DOUBLE PRECISION,
  pickup_latitude     DOUBLE PRECISION,
  dropoff_longitude   DOUBLE PRECISION,
  dropoff_latitude    DOUBLE PRECISION,
  passenger_count     SMALLINT,
  trip_distance       REAL,
  fare_amount         REAL,
  extra               REAL,
  tip_amount          REAL,
  tolls_amount        REAL,
  total_amount        REAL,
  payment_type        TEXT,
  pickup_ntaname      TEXT,
  dropoff_ntaname     TEXT
);
```

You can inspect the iceberg metadata using:
```sql
SELECT *
FROM mooncake.iceberg_metadata('s3://lakehouse/iceberg/trips/metadata/<metadata-file-path>');
```

You can inspect the iceberg snapshots details using: 
```sql
SELECT *
FROM mooncake.iceberg_snapshots('s3://lakehouse/iceberg/trips/metadata/<metadata-file-path>');
```

