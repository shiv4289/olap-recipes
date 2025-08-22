#!/bin/bash

set -e  # Exit on error

echo "Creating required directories..."
mkdir -p ./minio/data
mkdir -p ./clickhouse_data
mkdir -p ./olake-data
mkdir -p ./lakehouse

echo "Setting full access permissions..."
sudo chmod -R 777 ./clickhouse_data
sudo chmod -R 777 ./minio/data
sudo chmod -R 777 ./olake-data


echo "Downloading Extra jars for iceberg"
mkdir -p jars
# Hadoop AWS JAR
if [ ! -f jars/hadoop-aws-3.3.1.jar ]; then
  echo "Downloading hadoop-aws-3.3.1.jar..."
  curl -o jars/hadoop-aws-3.3.1.jar https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.1/hadoop-aws-3.3.1.jar
else
  echo "hadoop-aws-3.3.6.jar already exists. Skipping download."
fi

# AWS Java SDK Bundle JAR
if [ ! -f jars/aws-java-sdk-bundle-1.11.1026.jar ]; then
  echo "Downloading aws-java-sdk-bundle-1.11.1026.jar..."
  curl -o jars/aws-java-sdk-bundle-1.11.1026.jar https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.11.1026/aws-java-sdk-bundle-1.11.1026.jar
else
  echo "aws-java-sdk-bundle-1.12.517.jar already exists. Skipping download."
fi

# Download the dataset.
if [ ! -f dataset/weather.csv ]; then
  echo "Downloading weather.csv"
  curl -SLJk -o dataset/weather.csv https://corgis-edu.github.io/corgis/datasets/csv/weather/weather.csv
else
  echo "weather dataset already exists, skipping download"
fi

echo "Starting Docker Compose..."
docker-compose up -d

echo "Starting clickhouse"
cp ./clickhouse_binary/clickhouse  ./clickhouse_data
chmod +x ./clickhouse_data/clickhouse
cd ./clickhouse_data
./clickhouse server