#!/bin/bash

set -e  # Exit on error

echo "Creating required directories..."
mkdir -p ./minio/data
mkdir -p ./clickhouse_data

echo "Setting full access permissions..."
sudo chmod -R 777 ./clickhouse_data
sudo chmod -R 777 ./minio/data

echo "Starting Docker Compose..."
docker-compose up -d

echo "Starting clickhouse"
cp ./clickhouse_binary/clickhouse  ./clickhouse_data
chmod +x ./clickhouse_data/clickhouse
cd ./clickhouse_data
./clickhouse server