#!/bin/bash
set -e

# Dataset folder inside the container
DATA_IMPORT_DIR="/var/lib/clickhouse/data_import"

echo "⏳ Waiting for ClickHouse to start..."
until clickhouse-client --host=localhost --query "SELECT 1" &>/dev/null; do
    echo "Waiting for ClickHouse..."
    sleep 2
done

echo "📌 Creating ClickHouse table..."
clickhouse-client --host=localhost --query "
CREATE TABLE IF NOT EXISTS trips (
    trip_id             UInt32,
    pickup_datetime     DateTime,
    dropoff_datetime    DateTime,
    pickup_longitude    Nullable(Float64),
    pickup_latitude     Nullable(Float64),
    dropoff_longitude   Nullable(Float64),
    dropoff_latitude    Nullable(Float64),
    passenger_count     UInt8,
    trip_distance       Float32,
    fare_amount         Float32,
    extra               Float32,
    tip_amount          Float32,
    tolls_amount        Float32,
    total_amount        Float32,
    payment_type        Enum('CSH' = 1, 'CRE' = 2, 'NOC' = 3, 'DIS' = 4, 'UNK' = 5),
    pickup_ntaname      LowCardinality(String),
    dropoff_ntaname     LowCardinality(String)
)
ENGINE = MergeTree
PRIMARY KEY (pickup_datetime, dropoff_datetime);
"

echo "📥 Importing dataset into ClickHouse..."
for FILE in "$DATA_IMPORT_DIR"/*.tsv; do
    echo "Loading $FILE..."
    clickhouse-client --host=localhost --query "
        INSERT INTO trips FORMAT TabSeparatedWithNames" < "$FILE"
done

echo "✅ ClickHouse setup complete!"