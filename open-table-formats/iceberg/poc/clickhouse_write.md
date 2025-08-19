# ClickHouse Iceberg Write Feature Testing Guide

This guide documents how to test ClickHouse's new Iceberg write functionality introduced in [PR #84684](https://github.com/ClickHouse/ClickHouse/pull/84684).

## Overview

The new feature allows ClickHouse to write directly to Iceberg tables using REST catalog without requiring PyIceberg as an intermediary. This is a significant improvement for data lake integrations.

## Prerequisites

- Docker and Docker Compose
- `curl` and `unzip` utilities
- Local ClickHouse server running

## Step 1: Download ClickHouse Binary

Download the ClickHouse binary with Iceberg write support from the GitHub Actions build:

### 1.1 Create Download Directory

```bash
mkdir -p ~/clickhouse-iceberg-test
cd ~/clickhouse-iceberg-test
```

### 1.2 Download Binary from GitHub Actions

The binary is available from the build artifacts of [PR #84684](https://github.com/ClickHouse/ClickHouse/pull/84684):

**For Intel/AMD (x86_64) systems:**
```bash
# Download the binary artifact from GitHub Actions
# Note: You may need to be signed in to GitHub to access build artifacts
# Alternative: Use a direct download link if available

# For now, we'll use the build from the specific action run
curl -L -o clickhouse-binary.zip "https://github.com/ClickHouse/ClickHouse/actions/runs/16633452096/artifacts/download"
```

**Alternative method - Use a released binary with similar features:**
```bash
# If the specific build artifact is not accessible, use the latest nightly build
curl -L -o clickhouse "https://builds.clickhouse.com/master/amd64/clickhouse"
chmod +x clickhouse
```

### 1.3 Extract and Prepare Binary

If you downloaded a zip file:
```bash
unzip clickhouse-binary.zip
chmod +x clickhouse
```

### 1.4 Verify Binary

```bash
./clickhouse --version
```

Expected output should show a version that includes the Iceberg write functionality.

## Step 2: Create Docker Compose Configuration

Create a directory for the test infrastructure:

```bash
mkdir -p ~/clickhouse-iceberg-test/compose
cd ~/clickhouse-iceberg-test/compose
```

Create the `docker-compose-iceberg.yml` file with the following content:

```yaml
services:
  spark-iceberg:
    image: tabulario/spark-iceberg:3.5.5_1.8.1
    depends_on:
      rest:
        condition: service_healthy
      minio:
        condition: service_started
    environment:
      - AWS_ACCESS_KEY_ID=admin
      - AWS_SECRET_ACCESS_KEY=password
      - AWS_REGION=us-east-1
    ports:
      - 8080:8080
      - 10000:10000
      - 10001:10001
  rest:
    image: tabulario/iceberg-rest:1.6.0
    ports:
      - 8182:8181
    environment:
      - AWS_ACCESS_KEY_ID=minio
      - AWS_SECRET_ACCESS_KEY=ClickHouse_Minio_P@ssw0rd
      - AWS_REGION=us-east-1
      - CATALOG_WAREHOUSE=s3://warehouse-rest/
      - CATALOG_IO__IMPL=org.apache.iceberg.aws.s3.S3FileIO
      - CATALOG_S3_ENDPOINT=http://minio:9000
    healthcheck:
      test: ["CMD", "bash", "-c", "echo > /dev/tcp/localhost/8181"]
      interval: 1s
      timeout: 5s
      retries: 10
      start_period: 30s
  minio:
    image: minio/minio:RELEASE.2024-07-31T05-46-26Z
    environment:
      - MINIO_ROOT_USER=minio
      - MINIO_ROOT_PASSWORD=ClickHouse_Minio_P@ssw0rd
      - MINIO_DOMAIN=minio
    networks:
      default:
        aliases:
          - warehouse-rest.minio
    ports:
      - "9002:9000"
      - "9003:9001"
    command: ["server", "/data", "--console-address", ":9001"]
  mc:
    depends_on:
      - minio
    image: minio/mc:RELEASE.2025-04-16T18-13-26Z
    environment:
      - AWS_ACCESS_KEY_ID=minio
      - AWS_SECRET_ACCESS_KEY=ClickHouse_Minio_P@ssw0rd
      - AWS_REGION=us-east-1
    entrypoint: >
      /bin/sh -c "
      until (/usr/bin/mc config host add minio http://minio:9000 minio ClickHouse_Minio_P@ssw0rd) do echo '...waiting...' && sleep 1; done;
      /usr/bin/mc rm -r --force minio/warehouse-rest;
      /usr/bin/mc mb minio/warehouse-rest --ignore-existing;
      /usr/bin/mc policy set public minio/warehouse-rest;
      tail -f /dev/null
      "
```

You can create this file using:

```bash
cat > docker-compose-iceberg.yml << 'EOF'
services:
  spark-iceberg:
    image: tabulario/spark-iceberg:3.5.5_1.8.1
    depends_on:
      rest:
        condition: service_healthy
      minio:
        condition: service_started
    environment:
      - AWS_ACCESS_KEY_ID=admin
      - AWS_SECRET_ACCESS_KEY=password
      - AWS_REGION=us-east-1
    ports:
      - 8080:8080
      - 10000:10000
      - 10001:10001
  rest:
    image: tabulario/iceberg-rest:1.6.0
    ports:
      - 8182:8181
    environment:
      - AWS_ACCESS_KEY_ID=minio
      - AWS_SECRET_ACCESS_KEY=ClickHouse_Minio_P@ssw0rd
      - AWS_REGION=us-east-1
      - CATALOG_WAREHOUSE=s3://warehouse-rest/
      - CATALOG_IO__IMPL=org.apache.iceberg.aws.s3.S3FileIO
      - CATALOG_S3_ENDPOINT=http://minio:9000
    healthcheck:
      test: ["CMD", "bash", "-c", "echo > /dev/tcp/localhost/8181"]
      interval: 1s
      timeout: 5s
      retries: 10
      start_period: 30s
  minio:
    image: minio/minio:RELEASE.2024-07-31T05-46-26Z
    environment:
      - MINIO_ROOT_USER=minio
      - MINIO_ROOT_PASSWORD=ClickHouse_Minio_P@ssw0rd
      - MINIO_DOMAIN=minio
    networks:
      default:
        aliases:
          - warehouse-rest.minio
    ports:
      - "9002:9000"
      - "9003:9001"
    command: ["server", "/data", "--console-address", ":9001"]
  mc:
    depends_on:
      - minio
    image: minio/mc:RELEASE.2025-04-16T18-13-26Z
    environment:
      - AWS_ACCESS_KEY_ID=minio
      - AWS_SECRET_ACCESS_KEY=ClickHouse_Minio_P@ssw0rd
      - AWS_REGION=us-east-1
    entrypoint: >
      /bin/sh -c "
      until (/usr/bin/mc config host add minio http://minio:9000 minio ClickHouse_Minio_P@ssw0rd) do echo '...waiting...' && sleep 1; done;
      /usr/bin/mc rm -r --force minio/warehouse-rest;
      /usr/bin/mc mb minio/warehouse-rest --ignore-existing;
      /usr/bin/mc policy set public minio/warehouse-rest;
      tail -f /dev/null
      "
EOF
```

## Step 3: Start Infrastructure Services

Start the Iceberg REST catalog and MinIO services:

```bash
docker-compose -f docker-compose-iceberg.yml up -d
```

Verify services are running:

```bash
docker-compose -f docker-compose-iceberg.yml ps
```

Expected output:
```
NAME            IMAGE                         COMMAND                  SERVICE   CREATED          STATUS                    PORTS
compose-mc-1    minio/mc:RELEASE.2025-04-16   "/bin/sh -c 'until (…"   mc        43 minutes ago   Up 43 minutes             
compose-minio-1 minio/minio:RELEASE.2024-07-… "/usr/bin/docker-ent…"   minio     43 minutes ago   Up 43 minutes (healthy)   0.0.0.0:9002->9000/tcp, 0.0.0.0:9003->9001/tcp
compose-rest-1  tabulario/iceberg-rest:1.6.0  "java -jar iceberg-r…"   rest      43 minutes ago   Up 43 minutes (healthy)   0.0.0.0:8182->8181/tcp
```

## Step 2: Verify Service Endpoints

### Test REST Catalog Endpoint

```bash
curl -s http://localhost:8182/v1/config | jq .
```

Expected response:
```json
{
  "defaults": {},
  "overrides": {}
}
```

### Test MinIO Health

```bash
curl -I http://localhost:9002/minio/health/live
```

Expected response:
```
HTTP/1.1 200 OK
Accept-Ranges: bytes
Content-Length: 0
```

### List MinIO Buckets

```bash
docker exec compose-mc-1 mc ls minio/
```

Expected output:
```
[2025-08-13 05:17:45 UTC]     0B warehouse-rest/
```

## Step 4: ClickHouse Commands

Navigate back to your ClickHouse binary directory:

```bash
cd ~/clickhouse-iceberg-test
```

### 4.1 Create Database with REST Catalog

```sql
SET allow_experimental_database_iceberg=true; 
CREATE DATABASE demo ENGINE = DataLakeCatalog('http://localhost:8182/v1', 'minio', 'ClickHouse_Minio_P@ssw0rd') 
SETTINGS catalog_type='rest',warehouse='demo',storage_endpoint='http://localhost:9002/warehouse-rest';
```

**Execute:**
```bash
./clickhouse client --query "SET allow_experimental_database_iceberg=true; CREATE DATABASE demo ENGINE = DataLakeCatalog('http://localhost:8182/v1', 'minio', 'ClickHouse_Minio_P@ssw0rd') SETTINGS catalog_type='rest',warehouse='demo',storage_endpoint='http://localhost:9002/warehouse-rest';"
```

### 4.2 Verify Database Creation

```bash
./clickhouse client --query "SHOW DATABASES;"
```

Expected output should include:
```
demo
```

### 4.3 Create Iceberg Table

```sql
SET allow_experimental_database_iceberg=true; 
SET write_full_path_in_iceberg_metadata=1; 

CREATE TABLE demo.`test_namespace.sample_table` (x String) ENGINE = IcebergS3('http://localhost:9002/warehouse-rest/sample_table/', 'minio', 'ClickHouse_Minio_P@ssw0rd') SETTINGS storage_catalog_type='rest',storage_warehouse='demo',storage_region='us-east-1',storage_catalog_url='http://localhost:8182/v1';
```

**Execute:**
```bash
./clickhouse client --query "SET allow_experimental_database_iceberg=true; SET write_full_path_in_iceberg_metadata=1; CREATE TABLE demo.\`test_namespace.sample_table\` (x String) ENGINE = IcebergS3('http://localhost:9002/warehouse-rest/sample_table/', 'minio', 'ClickHouse_Minio_P@ssw0rd') SETTINGS storage_catalog_type='rest',storage_warehouse='demo',storage_region='us-east-1',storage_catalog_url='http://localhost:8182/v1';"
```

### 4.4 Verify Table Creation

```bash
./clickhouse client --query "SHOW TABLES FROM demo;"
```

Expected output:
```
test_namespace.sample_table
```

### 4.5 Insert Data into Iceberg Table

```sql
SET allow_experimental_insert_into_iceberg=1; 
SET write_full_path_in_iceberg_metadata=1; 
INSERT INTO demo.`test_namespace.sample_table` VALUES ('AAPL');
```

**Execute:**
```bash
./clickhouse client --query "SET allow_experimental_insert_into_iceberg=1; SET write_full_path_in_iceberg_metadata=1; INSERT INTO demo.\`test_namespace.sample_table\` VALUES ('AAPL');"
```

### 4.6 Insert Additional Data

```bash
./clickhouse client --query "SET allow_experimental_insert_into_iceberg=1; SET write_full_path_in_iceberg_metadata=1; INSERT INTO demo.\`test_namespace.sample_table\` VALUES ('GOOGL');"
```

### 4.7 Query Data from Iceberg Table

```bash
./clickhouse client --query "SELECT * FROM demo.\`test_namespace.sample_table\` ORDER BY x;"
```

Expected output:
```
AAPL
GOOGL
```

## Step 5: Verify Iceberg Metadata Files in MinIO

### List Metadata Files

```bash
docker exec compose-mc-1 mc ls minio/warehouse-rest/sample_table/metadata/
```

Expected output (file names will be different UUIDs):
```
[2025-08-13 06:19:45 UTC]   895B STANDARD 00000-7a314194-b11c-471c-bec1-88203f63fac5.metadata.json
[2025-08-13 06:19:57 UTC] 1.8KiB STANDARD 00001-2582a339-9895-484c-b870-48f45164175b.metadata.json
[2025-08-13 06:20:09 UTC] 2.7KiB STANDARD 00002-115695e3-b7c0-42d8-b509-a95eb4972433.metadata.json
[2025-08-13 06:20:09 UTC] 2.4KiB STANDARD d24da68c-d124-4ee6-bad0-848b265a7f50.avro
[2025-08-13 06:19:57 UTC] 2.4KiB STANDARD ea3dc8e2-33a0-462a-adc3-9e51af8adc1d.avro
[2025-08-13 06:20:09 UTC] 1.6KiB STANDARD snap-1008929022-2-36a685fc-089f-4168-8c85-525ab5ddc902.avro
[2025-08-13 06:19:57 UTC] 1.5KiB STANDARD snap-179729873-2-f7dc5e79-72b8-42b0-a60e-2d3f4afe7af2.avro
[2025-08-13 06:19:57 UTC] 2.4KiB STANDARD v1-f5728dfb-d2cc-4ef4-b704-2c5c8483045f.metadata.json
[2025-08-13 06:19:12 UTC] 1.1KiB STANDARD v1.metadata.json
[2025-08-13 06:20:09 UTC] 3.5KiB STANDARD v2-c54624c6-f728-4d07-b858-ca1debfd9a72.metadata.json
```

### List Data Files

```bash
docker exec compose-mc-1 mc ls minio/warehouse-rest/sample_table/data/
```

## Step 6: Advanced Testing

### Test Table Schema Information

```bash
./clickhouse client --query "DESCRIBE demo.\`test_namespace.sample_table\`;"
```

### Test Table Creation Statement

```bash
./clickhouse client --query "SHOW CREATE TABLE demo.\`test_namespace.sample_table\`;"
```

### Test with Different Data Types

Create a more complex table:

```bash
./clickhouse client --query "SET allow_experimental_database_iceberg=true; SET write_full_path_in_iceberg_metadata=1; CREATE TABLE demo.\`test_namespace.complex_table\` (id Int64, name String, price Float64, created_at DateTime64(6)) ENGINE = IcebergS3('http://localhost:9002/warehouse-rest/complex_table/', 'minio', 'ClickHouse_Minio_P@ssw0rd') SETTINGS storage_catalog_type='rest',storage_warehouse='demo',storage_region='us-east-1',storage_catalog_url='http://localhost:8182/v1';"
```

Insert complex data:

```bash
./clickhouse client --query "SET allow_experimental_insert_into_iceberg=1; SET write_full_path_in_iceberg_metadata=1; INSERT INTO demo.\`test_namespace.complex_table\` VALUES (1, 'Apple Inc', 193.24, '2024-01-01 12:00:00.000000');"
```

## Step 7: Cleanup

### Stop Services

```bash
cd ~/clickhouse-iceberg-test/compose
docker-compose -f docker-compose-iceberg.yml down
```

### Drop Database

```bash
cd ~/clickhouse-iceberg-test
./clickhouse client --query "DROP DATABASE IF EXISTS demo;"
```

## Troubleshooting

### Common Issues

1. **Port Conflicts**: If ClickHouse server is running on port 9000, MinIO is mapped to 9002
2. **Permission Errors**: Ensure Docker has proper permissions
3. **Service Health**: Wait for services to be healthy before creating tables

### Logs

Check service logs:

```bash
cd ~/clickhouse-iceberg-test/compose
docker-compose -f docker-compose-iceberg.yml logs rest
docker-compose -f docker-compose-iceberg.yml logs minio
```

## Service Endpoints Summary

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| REST Catalog | 8181 | 8182 | Iceberg REST API |
| MinIO S3 API | 9000 | 9002 | Object storage |
| MinIO Console | 9001 | 9003 | Web interface |

## MinIO Web Interface

Access MinIO console at: http://localhost:9003

**Credentials:**
- Username: `minio`
- Password: `ClickHouse_Minio_P@ssw0rd`

Navigate to the `warehouse-rest` bucket to see the Iceberg files created by ClickHouse.

## Key Settings Explained

- `allow_experimental_database_iceberg`: Enables DataLakeCatalog database engine
- `allow_experimental_insert_into_iceberg`: Enables INSERT operations to Iceberg tables
- `write_full_path_in_iceberg_metadata`: Writes full S3 paths in metadata
- `storage_catalog_type='rest'`: Uses REST catalog for table registration
- `storage_warehouse='demo'`: Warehouse name in the catalog
- `storage_region='us-east-1'`: AWS region (required even for MinIO)
- `storage_catalog_url`: REST catalog endpoint

## Success Indicators

- Database created successfully
- Table listed in `SHOW TABLES FROM demo`
- Data inserted without errors
- Data queried correctly
- Metadata files created in MinIO
- Multiple INSERT operations work

This confirms that ClickHouse's new Iceberg write functionality is working correctly.
