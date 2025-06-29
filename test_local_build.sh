#!/bin/bash

# Local test script to validate the PostgreSQL build and TimescaleDB extension
# This mimics what the GitHub Actions workflow does

echo "Testing PostgreSQL build with TimescaleDB extension..."

# Check if the Docker image was built successfully
if ! docker images postgres-test:local > /dev/null 2>&1; then
    echo "ERROR: Docker image postgres-test:local not found. Build it first with:"
    echo "docker build -f Dockerfile-17 -t postgres-test:local ."
    exit 1
fi

echo "✓ Docker image found"

# Start a container to test the database
CONTAINER_ID=$(docker run -d \
    -e POSTGRES_PASSWORD=postgres \
    -e POSTGRES_DB=test \
    postgres-test:local)

echo "Started test container: $CONTAINER_ID"

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to start..."
sleep 10

# Test basic PostgreSQL functionality
echo "Testing basic PostgreSQL connection..."
docker exec $CONTAINER_ID psql -U postgres -d test -c "SELECT version();" > /dev/null
if [ $? -eq 0 ]; then
    echo "✓ PostgreSQL is working"
else
    echo "✗ PostgreSQL connection failed"
    docker logs $CONTAINER_ID
    docker rm -f $CONTAINER_ID
    exit 1
fi

# Test TimescaleDB extension
echo "Testing TimescaleDB extension..."
docker exec $CONTAINER_ID psql -U postgres -d test -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" > /dev/null
if [ $? -eq 0 ]; then
    echo "✓ TimescaleDB extension created successfully"
else
    echo "✗ TimescaleDB extension failed to create"
    docker logs $CONTAINER_ID
    docker rm -f $CONTAINER_ID
    exit 1
fi

# Test TimescaleDB functionality
echo "Testing TimescaleDB functionality..."
docker exec $CONTAINER_ID psql -U postgres -d test -c "
    CREATE TABLE sensor_data (
        time TIMESTAMPTZ NOT NULL,
        sensor_id INTEGER,
        temperature DOUBLE PRECISION
    );
    SELECT create_hypertable('sensor_data', 'time');
    INSERT INTO sensor_data VALUES (NOW(), 1, 20.5);
    SELECT * FROM sensor_data;
" > /dev/null

if [ $? -eq 0 ]; then
    echo "✓ TimescaleDB hypertable functionality works"
else
    echo "✗ TimescaleDB hypertable functionality failed"
    docker logs $CONTAINER_ID
    docker rm -f $CONTAINER_ID
    exit 1
fi

# Show TimescaleDB version
echo "TimescaleDB version:"
docker exec $CONTAINER_ID psql -U postgres -d test -c "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';"

# Cleanup
docker rm -f $CONTAINER_ID > /dev/null
echo "✓ All tests passed! TimescaleDB extension is working correctly."
