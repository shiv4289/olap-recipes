### Queries
Source1: https://www.e6data.com/blog/iceberg-metadata-evolution-after-compaction

The NYC Yellow Taxi trip data for January and February 2022. You do not need to download the dataset, as it has already been baked into the container stored as parquet files.

Note: This requires a bit more memory so it is advised to increase your colima memory limits.

Fire up spark sql

```shell
docker exec -it spark-iceberg spark-sql
```

Create temporary views for the Parquet files so that we can use them later to insert the iceberg table:

```sql
-- For January data
CREATE OR REPLACE TEMPORARY VIEW parquet_temp_view
USING parquet
OPTIONS (
path '/home/iceberg/data/yellow_tripdata_2022-01.parquet'
);

-- For February data
CREATE OR REPLACE TEMPORARY VIEW parquet_temp_view2
USING parquet
OPTIONS (
path '/home/iceberg/data/yellow_tripdata_2022-02.parquet'
);
```

Creating the Partitioned Table

```sql
CREATE TABLE demo.nyc.taxis_partitioned (
                                            VendorID BIGINT,
                                            tpep_pickup_datetime TIMESTAMP,
                                            tpep_dropoff_datetime TIMESTAMP,
                                            passenger_count DOUBLE,
                                            trip_distance DOUBLE,
                                            RatecodeID DOUBLE,
                                            store_and_fwd_flag STRING,
                                            PULocationID BIGINT,
                                            DOLocationID BIGINT,
                                            payment_type BIGINT,
                                            fare_amount DOUBLE,
                                            extra DOUBLE,
                                            mta_tax DOUBLE,
                                            tip_amount DOUBLE,
                                            tolls_amount DOUBLE,
                                            improvement_surcharge DOUBLE,
                                            total_amount DOUBLE,
                                            congestion_surcharge DOUBLE,
                                            airport_fee DOUBLE
)
    USING ICEBERG
PARTITIONED BY (
    payment_type
);
```

### Adding Data to the Partitioned Table

First INSERT operation: Creating an initial snapshot
```sql
INSERT INTO demo.nyc.taxis_partitioned SELECT * FROM parquet_temp_view;
```

Second INSERT operation:

```sql
INSERT INTO demo.nyc.taxis_partitioned SELECT * FROM parquet_temp_view2;
```
 
### Querying from clickhouse

Exec into the clickhouse container.

```shell
docker exec -it clickhouse clickhouse-client
```

Query the demo.nyc.taxis_partitioned table from clickhouse using icebergs3 functions.

Count of all rows from iceberg tables
```sql
SELECT count(*) FROM icebergS3('http://minio:9000/lakehouse/nyc/taxis_partitioned','admin','password');
```

Top 3 rows from iceberg tables
```sql
SELECT * FROM icebergS3('http://minio:9000/lakehouse/nyc/taxis_partitioned','admin','password') LIMIT 3;
```