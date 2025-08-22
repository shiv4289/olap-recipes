#!/bin/bash

set -e  # Exit on error

echo "Creating required directories..."
mkdir -p ./minio/data
mkdir -p ./clickhouse_data
mkdir -p ./olake-data
mkdir -p ./lakehouse
mkdir -p ./clickhouse_binary

echo "Setting full access permissions..."
sudo chmod -R 777 ./clickhouse_data
sudo chmod -R 777 ./minio/data
sudo chmod -R 777 ./olake-data

echo "Downloading Clickhouse Binary"
if [ ! -f ./clickhouse_binary/clickhouse ]; then
  echo "Downloading binary"
  mkdir -p ./clickhouse_binary

  OS="$(uname -s)"
  ARCH="$(uname -m)"
  BASE="https://clickhouse-builds.s3.amazonaws.com/PRs/84684/644986c66e75c14a69f7723d971a63f0d5223879"

  if [[ "$OS" == "Darwin" && "$ARCH" == "arm64" ]]; then
    URL="$BASE/build_arm_darwin/clickhouse"
  elif [[ "$OS" == "Linux" && ( "$ARCH" == "aarch64" || "$ARCH" == "arm64" ) ]]; then
    URL="$BASE/build_arm_binary/clickhouse"
  elif [[ "$OS" == "Linux" && ( "$ARCH" == "x86_64" || "$ARCH" == "amd64" ) ]]; then
    URL="$BASE/build_amd_binary/clickhouse"
  else
    echo "Unsupported platform: $OS $ARCH"
    exit 1
  fi

  echo "Fetching from $URL"
  curl -L --fail -o ./clickhouse_binary/clickhouse "$URL"
  chmod +x ./clickhouse_binary/clickhouse
fi

./clickhouse_binary/clickhouse --version


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