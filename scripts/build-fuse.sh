#!/bin/bash
# Script to build the FUSE driver inside the Docker container

set -e

# Source the central configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/config.sh"

# Use separate build container for building
echo "Building FUSE driver using build container..."
cd "${PROJECT_ROOT}"
docker compose -f docker-compose.build.yml build fuse-builder
docker compose -f docker-compose.build.yml run --rm fuse-builder || {
    echo "ERROR: FUSE driver build command failed!"
    echo "Checking for common issues..."
    
    # Check if source files exist
    echo "Checking source files..."
    ls -la src/fuse-driver/src/
    
    # Check if we have build dependencies
    echo "Build failed. Try running: sudo apt-get install build-essential libfuse-dev pkg-config"
    
    # Check obj directory permissions
    echo "Checking obj directory permissions..."
    mkdir -p src/fuse-driver/obj && ls -la src/fuse-driver/
    
    exit 1
}

# Verify the build
if [ -f ./src/fuse-driver/nas-emu-fuse ]; then
    echo "FUSE driver built successfully!"
else
    echo "ERROR: Failed to build FUSE driver binary!"
    exit 1
fi

echo "Build complete. FUSE driver binary is at ./src/fuse-driver/nas-emu-fuse"