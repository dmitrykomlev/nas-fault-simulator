#!/bin/bash
set -e

# Build the FUSE driver inside the container
cd "$(dirname "$0")/../"

# Start container if not running
docker-compose up -d fuse-dev

# Compile inside container
docker-compose exec -T fuse-dev \
  bash -c "cd /app/src/fuse-driver && make"

echo "Build completed. Binary location: src/fuse-driver/nas-emu-fuse"
