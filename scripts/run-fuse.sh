#!/bin/bash
set -e

# Run the FUSE driver in the container
cd "$(dirname "$0")/../"

# Start container if not running
docker-compose up -d fuse-dev

# Make sure mount directory exists
docker-compose exec -T fuse-dev \
  bash -c "mkdir -p /mnt/fs-fault"

# Run FUSE driver with storage path from environment
echo "Running FUSE driver in Docker container..."
docker-compose exec -T fuse-dev \
  bash -c "cd /app/src/fuse-driver && ./nas-emu-fuse /mnt/fs-fault -f \
  --storage=\${STORAGE_PATH:-/var/nas-storage} \
  --log=/var/log/nas-emu-fuse.log \
  --loglevel=3"

# Note: The -f flag keeps FUSE in the foreground