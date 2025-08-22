#!/bin/bash
echo "🧹 Stopping and cleaning up containers, and local folders..."
docker-compose down -v
docker rm $(docker ps -a -q)
rm -rf ./lakehouse ./minio ./clickhouse_data ./olake-data ./lakehouse
echo "✅ Cleanup complete!"