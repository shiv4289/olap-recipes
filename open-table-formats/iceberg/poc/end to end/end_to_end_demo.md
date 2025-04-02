### Queries
Source: https://www.e6data.com/blog/iceberg-metadata-evolution-after-compaction

Note: This requires a bit more memory so it is advised to increase your colima/docker desktop memory limits.
```shell
colima start --cpu 4 --memory 8
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
    end

    MC --> MINIO
    REST --> MINIO
    SPARK --> MINIO
    SPARK --> REST
    CLICKHOUSE --> MINIO
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

```mermaid
flowchart TD
    A[ClickHouse<br/>Preloaded trips table]
    B[ClickHouse S3 Function<br/>Writes Parquet to MinIO]
    C[MinIO<br/>clickhouse_generated/trips.parquet]
    D[Spark SQL<br/>Shell with manual config]
    E[Create Iceberg Table<br/>demo.iceberg.trips]
    F[Insert Parquet<br/>into Iceberg table]
    G[MinIO<br/>iceberg/trips]
    H[ClickHouse<br/>Query with icebergS3]

    A --> B
    B --> C
    C --> D
    D --> E
    E --> F
    F --> G
    G --> H
```

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

### Step 3: Querying iceberg tables from clickhouse

Fire up clickhouse client

```shell
docker exec -it clickhouse clickhouse-client
```

Query this new table count
```sql
SELECT count(*) FROM icebergS3('http://minio:9000/lakehouse/iceberg/trips','admin','password');
```
It should match the count of rows in trips table
```sql
SELECT count(*) from trips;
```

## Flow 2: Compaction of Iceberg Tables

```mermaid
flowchart TD
    A[Existing Iceberg Table<br/>demo.iceberg.trips]
    B[Insert 10 New Rows<br/>Using Spark SQL]
    C[Run Compaction<br/>Using System Procedure]
    D[New Compacted<br/>Parquet File]
    E[MinIO<br/>iceberg/trips]

    A --> B
    B --> C
    C --> D
    D --> E
```

### Step 1: Create Table and Insert Data

Fire up spark sql with the necessary configurations:

```shell
docker exec -it spark-iceberg spark-sql \
  --conf spark.driver.extraClassPath="/opt/spark-extra-jars/*" \
  --conf spark.executor.extraClassPath="/opt/spark-extra-jars/*" \
  --conf spark.hadoop.fs.s3a.access.key=admin \
  --conf spark.hadoop.fs.s3a.secret.key=password \
  --conf spark.hadoop.fs.s3a.endpoint=http://minio:9000 \
  --conf spark.hadoop.fs.s3a.path.style.access=true
```

First, create a new unpartitioned table for demonstrating compaction:

```sql
CREATE TABLE demo.iceberg.trips_compact (
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
) USING ICEBERG;  -- No partitioning for clearer compaction demo
```

First, load the data from the parquet file (same as Flow 1):
```sql
INSERT INTO demo.iceberg.trips_compact
SELECT * FROM parquet.`s3a://lakehouse/clickhouse_generated/trips.parquet`;
```

Let's check the files created from the parquet data load:
```sql
SELECT file_path, file_format, record_count, file_size_in_bytes 
FROM demo.iceberg.trips_compact.files;
```
```
s3://lakehouse/iceberg/trips_compact/data/00000-2-2400d604-87ce-4088-9fb2-28365d5b99cc-0-00001.parquet  PARQUET 1048576 26048635
s3://lakehouse/iceberg/trips_compact/data/00001-3-2400d604-87ce-4088-9fb2-28365d5b99cc-0-00001.parquet  PARQUET 1048576 25732220
s3://lakehouse/iceberg/trips_compact/data/00002-4-2400d604-87ce-4088-9fb2-28365d5b99cc-0-00001.parquet  PARQUET 903165  22401900
Time taken: 0.6 seconds, Fetched 3 row(s)
```

Then, insert additional rows one by one to create multiple small files for compaction:
```sql
-- Insert rows one by one to create multiple small files
INSERT INTO demo.iceberg.trips_compact VALUES
(1, TIMESTAMP '2023-06-01 08:15:00', TIMESTAMP '2023-06-01 08:30:00', -73.9857, 40.7484, -73.9819, 40.7433, 1, 2.1, 10.5, 0.5, 2.0, 0.0, 13.0, '1', 'Midtown', 'Chelsea');

INSERT INTO demo.iceberg.trips_compact VALUES
(2, TIMESTAMP '2023-06-01 09:10:00', TIMESTAMP '2023-06-01 09:25:00', -73.9822, 40.7527, -73.9711, 40.7612, 2, 3.4, 14.0, 1.0, 1.5, 0.0, 16.5, '1', 'Times Square', 'Upper East Side');

INSERT INTO demo.iceberg.trips_compact VALUES
(3, TIMESTAMP '2023-06-01 10:45:00', TIMESTAMP '2023-06-01 11:10:00', -73.9948, 40.7505, -74.0059, 40.7453, 1, 1.8, 8.0, 0.5, 1.0, 0.0, 9.5, '1', 'Penn Station', 'Meatpacking');

-- Insert remaining rows in one batch
INSERT INTO demo.iceberg.trips_compact VALUES
(4, TIMESTAMP '2023-06-01 12:00:00', TIMESTAMP '2023-06-01 12:25:00', -73.9681, 40.7853, -73.9581, 40.8001, 3, 4.2, 18.0, 1.5, 2.5, 0.0, 22.0, '1', 'Upper East Side', 'Harlem'),
(5, TIMESTAMP '2023-06-01 13:30:00', TIMESTAMP '2023-06-01 13:50:00', -73.9772, 40.7520, -73.9690, 40.7601, 2, 2.0, 9.0, 0.5, 1.2, 0.0, 10.7, '1', 'Midtown East', 'Turtle Bay'),
(6, TIMESTAMP '2023-06-01 14:15:00', TIMESTAMP '2023-06-01 14:40:00', -73.9915, 40.7301, -73.9854, 40.7441, 1, 2.9, 11.0, 0.5, 2.0, 0.0, 13.5, '1', 'East Village', 'Gramercy'),
(7, TIMESTAMP '2023-06-01 15:45:00', TIMESTAMP '2023-06-01 16:05:00', -73.9849, 40.7392, -73.9811, 40.7503, 1, 1.5, 7.0, 0.5, 1.0, 0.0, 8.5, '1', 'Flatiron', 'Kips Bay'),
(8, TIMESTAMP '2023-06-01 17:10:00', TIMESTAMP '2023-06-01 17:35:00', -73.9715, 40.7643, -73.9650, 40.7751, 2, 3.2, 13.0, 1.0, 2.2, 0.0, 16.2, '1', 'Lincoln Square', 'Central Park'),
(9, TIMESTAMP '2023-06-01 18:50:00', TIMESTAMP '2023-06-01 19:15:00', -73.9610, 40.7777, -73.9511, 40.7888, 1, 2.5, 10.0, 0.5, 1.3, 0.0, 11.8, '1', 'Upper West Side', 'Harlem'),
(10, TIMESTAMP '2023-06-01 20:30:00', TIMESTAMP '2023-06-01 20:50:00', -73.9810, 40.7333, -73.9777, 40.7433, 2, 2.1, 9.5, 0.5, 1.8, 0.0, 11.8, '1', 'Greenwich Village', 'Chelsea');
```

Let's check how our files look after adding the small files:
```sql
SELECT file_path, file_format, record_count, file_size_in_bytes 
FROM demo.iceberg.trips_compact.files;
```
```
s3://lakehouse/iceberg/trips_compact/data/00000-10-aeb8f09e-a643-4667-97a2-82efe915e556-0-00001.parquet PARQUET 1       4644
s3://lakehouse/iceberg/trips_compact/data/00001-11-aeb8f09e-a643-4667-97a2-82efe915e556-0-00001.parquet PARQUET 2       4819
s3://lakehouse/iceberg/trips_compact/data/00002-12-aeb8f09e-a643-4667-97a2-82efe915e556-0-00001.parquet PARQUET 2       4780
s3://lakehouse/iceberg/trips_compact/data/00003-13-aeb8f09e-a643-4667-97a2-82efe915e556-0-00001.parquet PARQUET 2       4865
s3://lakehouse/iceberg/trips_compact/data/00000-9-3522df96-46e2-498e-ab6e-642ef9634d24-0-00001.parquet  PARQUET 1       4657
s3://lakehouse/iceberg/trips_compact/data/00000-8-9b9418da-612f-4b53-900f-e4ee72845bd2-0-00001.parquet  PARQUET 1       4687
s3://lakehouse/iceberg/trips_compact/data/00000-7-f637cd78-6c3b-4e15-863a-ede647df5589-0-00001.parquet  PARQUET 1       4594
s3://lakehouse/iceberg/trips_compact/data/00000-2-2400d604-87ce-4088-9fb2-28365d5b99cc-0-00001.parquet  PARQUET 1048576 26048635
s3://lakehouse/iceberg/trips_compact/data/00001-3-2400d604-87ce-4088-9fb2-28365d5b99cc-0-00001.parquet  PARQUET 1048576 25732220
s3://lakehouse/iceberg/trips_compact/data/00002-4-2400d604-87ce-4088-9fb2-28365d5b99cc-0-00001.parquet  PARQUET 903165  22401900
Time taken: 0.287 seconds, Fetched 10 row(s)
```

As we can see, we now have:
- 3 large files (>22MB each) from the initial parquet data load
- 7 small files (~4KB each) from our individual inserts
This mix of large and small files makes it a perfect scenario for demonstrating compaction.

### Step 2: Run Compaction

Now execute the compaction procedure to optimize the data files:

```sql
CALL demo.system.rewrite_data_files('demo.iceberg.trips_compact');
```
```
10      1       74215801        0
Time taken: 10.104 seconds, Fetched 1 row(s)
```

Let's check the files after compaction:
```sql
SELECT file_path, file_format, record_count, file_size_in_bytes 
FROM demo.iceberg.trips_compact.files;
```
```
s3://lakehouse/iceberg/trips_compact/data/00000-16-a40066d8-eb14-4c59-b43c-573ad2928822-0-00001.parquet PARQUET 3000327 74002472
Time taken: 0.195 seconds, Fetched 1 row(s)
```

As we can see, after compaction:
1. All 10 files (3 large + 7 small) have been combined into a single file
2. The new file contains all records (3,000,327) and is about 74MB in size
3. The older files will not be physically deleted from storage - only their linking will be removed from the latest manifest files, ensuring that time travel queries and rollback operations remain possible.

### Step 3: Query the Compacted Table from ClickHouse

Fire up clickhouse client:

```shell
docker exec -it clickhouse clickhouse-client
```

Verify the data is still accessible and the count matches:

```sql
SELECT count(*) FROM icebergS3('http://minio:9000/lakehouse/iceberg/trips_compact','admin','password');
```

The count should show all 10 rows we added, now stored in fewer, more optimally sized files.