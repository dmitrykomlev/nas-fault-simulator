#!/bin/bash
set -e

# Run the FUSE driver in the container
cd "$(dirname "$0")/../"

# Start container if not running
docker-compose up -d fuse-dev

# Make sure mount directory exists
docker-compose exec -T fuse-dev \
  bash -c "mkdir -p /mnt/fs-fault"

# Run FUSE driver
echo "Running FUSE driver in Docker container..."
docker-compose exec -T fuse-dev \
  bash -c "cd /app/src/fuse-driver && ./nas-emu-fuse /mnt/fs-fault -f"

# Note: The -f flag keeps FUSE in the foreground
