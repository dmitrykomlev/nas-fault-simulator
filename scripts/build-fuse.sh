#!/bin/bash
# Script to build the FUSE driver inside the Docker container

set -e

# Source the central configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/config.sh"

# Check if Docker container is running
if ! docker-compose ps | grep -q "fuse-dev.*Up"; then
    echo "Starting Docker container..."
    docker-compose up -d
fi

# Build the FUSE driver
echo "Building FUSE driver..."
docker-compose exec fuse-dev bash -c "cd /app/src/fuse-driver && make clean && make VERBOSE=1" || {
    echo "ERROR: FUSE driver build command failed!"
    echo "Checking for common issues..."
    
    # Check if source files exist
    docker-compose exec fuse-dev bash -c "ls -la /app/src/fuse-driver/src/"
    
    # Check pkg-config fuse
    echo "Checking FUSE development package..."
    docker-compose exec fuse-dev bash -c "pkg-config --cflags --libs fuse || echo 'FUSE development package not properly installed'"
    
    # Check obj directory permissions
    echo "Checking obj directory permissions..."
    docker-compose exec fuse-dev bash -c "mkdir -p /app/src/fuse-driver/obj && ls -la /app/src/fuse-driver/"
    
    exit 1
}

# Verify the build
if docker-compose exec fuse-dev test -f /app/src/fuse-driver/nas-emu-fuse; then
    echo "FUSE driver built successfully!"
else
    echo "ERROR: Failed to build FUSE driver binary!"
    exit 1
fi

echo "Build complete. FUSE driver binary is at ./src/fuse-driver/nas-emu-fuse"