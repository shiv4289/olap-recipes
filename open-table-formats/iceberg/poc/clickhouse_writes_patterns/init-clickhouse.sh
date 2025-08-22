#!/bin/bash
set -e

echo "⏳ Waiting for ClickHouse to start..."
until ./clickhouse_data/clickhouse client --query "SELECT 1" &>/dev/null; do
    echo "Waiting for ClickHouse..."
    sleep 2
done

cp ./dataset/weather.csv ./clickhouse_data/user_files

echo "📌 Creating ClickHouse table for weather data"
./clickhouse_data/clickhouse client --query "
DROP TABLE IF EXISTS weather"

echo "📌 Creating ClickHouse table for weather data"
./clickhouse_data/clickhouse client --query "
CREATE TABLE IF NOT EXISTS weather
(
    id UInt64 DEFAULT cityHash64(station_code, date_full),
    precipitation    Float32,
    date_full        String,
    date_month       Int32,
    date_week_of     Int32,
    date_year        Int32,
    station_city     String,
    station_code     String,
    station_location String,
    station_state    String,
    temperature_avg  Float32,
    temperature_max  Float32,
    temperature_min  Float32,
    wind_direction   Int32,
    wind_speed       Float32
)
ENGINE = MergeTree
PRIMARY KEY (id);
"

echo "📥 Importing dataset into ClickHouse..."
echo "Loading weather.csv..."
echo 'init-clickhouse-tasks: Loading weather data into ClickHouse (fast)...'
./clickhouse_data/clickhouse client --query "
INSERT INTO weather (
    precipitation,
    date_full,
    date_month,
    date_week_of,
    date_year,
    station_city,
    station_code,
    station_location,
    station_state,
    temperature_avg,
    temperature_max,
    temperature_min,
    wind_direction,
    wind_speed
)
SELECT
    CAST(src.\`Data.Precipitation\`               AS Float32) AS precipitation,
    src.\`Date.Full\`                                        AS date_full,
    CAST(src.\`Date.Month\`                      AS Int32)   AS date_month,
    CAST(src.\`Date.Week of\`                    AS Int32)   AS date_week_of,
    CAST(src.\`Date.Year\`                       AS Int32)   AS date_year,
    src.\`Station.City\`                                     AS station_city,
    src.\`Station.Code\`                                     AS station_code,
    src.\`Station.Location\`                                 AS station_location,
    src.\`Station.State\`                                    AS station_state,
    CAST(src.\`Data.Temperature.Avg Temp\`      AS Float32)  AS temperature_avg,
    CAST(src.\`Data.Temperature.Max Temp\`      AS Float32)  AS temperature_max,
    CAST(src.\`Data.Temperature.Min Temp\`      AS Float32)  AS temperature_min,
    CAST(src.\`Data.Wind.Direction\`            AS Int32)    AS wind_direction,
    CAST(src.\`Data.Wind.Speed\`                AS Float32)  AS wind_speed
FROM file('weather.csv', 'CSVWithNames') AS src"

echo "✅ ClickHouse setup complete!"