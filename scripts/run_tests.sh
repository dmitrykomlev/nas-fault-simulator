#!/bin/bash
# Script to run all tests inside the Docker container

set -e

# Source the central configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/config.sh"

# Check if Docker container is running
if ! docker-compose ps | grep -q "fuse-dev.*Up"; then
    echo "Starting Docker container..."
    docker-compose up -d
fi

# Ensure the FUSE driver is built
if ! docker-compose exec fuse-dev test -f /app/src/fuse-driver/nas-emu-fuse; then
    echo "FUSE driver not found, building first..."
    ${SCRIPT_DIR}/build-fuse.sh
fi

# Check if FUSE is already mounted
if ! docker-compose exec fuse-dev mount | grep -q "${NAS_MOUNT_POINT}"; then
    echo "FUSE filesystem not mounted, mounting first..."
    ${SCRIPT_DIR}/run-fuse.sh
fi

# Run all the functional tests
echo "Running all functional tests..."
docker-compose exec fuse-dev bash -c "cd /app/src/fuse-driver/tests/functional && ./run_all_tests.sh"

echo "All tests completed!"