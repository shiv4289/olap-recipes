#!/bin/bash

set -e  # Exit on error

echo "Creating required directories..."
mkdir -p ./lakehouse
mkdir -p ./minio/data
mkdir -p ./clickhouse/data_import

echo "Setting full access permissions..."
sudo chmod -R 777 ./lakehouse
sudo chmod -R 777 ./minio/data
sudo chmod -R 777 ./clickhouse/data_import

echo "Copying database setup files..."
cp ./init-clickhouse.sh ./clickhouse
chmod +x ./clickhouse/init-clickhouse.sh

echo "Downloading and extracting dataset..."
BASE_URL="https://datasets-documentation.s3.eu-west-3.amazonaws.com/nyc-taxi"
DATA_IMPORT_DIR="./data_import"
FILES=( "trips_0" "trips_1" "trips_2" )
mkdir -p "$DATA_IMPORT_DIR"

for FILE in "${FILES[@]}"; do
    echo "Processing $FILE..."
    # Ensure .tsv file doesn't already exist before downloading
    if [ ! -f "$DATA_IMPORT_DIR/$FILE.tsv" ]; then
        echo "Downloading $FILE.gz..."
        curl -o "$DATA_IMPORT_DIR/$FILE.gz" "$BASE_URL/$FILE.gz"

        echo "Extracting $FILE.tsv..."
        gunzip -c "$DATA_IMPORT_DIR/$FILE.gz" > "$DATA_IMPORT_DIR/$FILE.tsv"
    else
        echo "$DATA_IMPORT_DIR/$FILE.tsv exists. Skipping download."
    fi
    # Copy the TSV file to the target ClickHouse directory
    cp "$DATA_IMPORT_DIR/$FILE.tsv" "./clickhouse/$DATA_IMPORT_DIR/$FILE.tsv"
done

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

echo "Starting Docker Compose..."
docker-compose up -d

sleep 5

echo "Inserting data into clickhouse table"
docker exec -it clickhouse /bin/sh -c "cd /var/lib/clickhouse && chmod +x ./init-clickhouse.sh && ./init-clickhouse.sh"