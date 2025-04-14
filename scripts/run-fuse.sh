#!/bin/bash
# Script to run the FUSE driver inside the Docker container

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
if [ ! -f ./src/fuse-driver/nas-emu-fuse ]; then
    echo "FUSE driver not found, building first..."
    ${SCRIPT_DIR}/build-fuse.sh
fi

# Check if FUSE is already mounted - specifically look for a FUSE filesystem
if docker-compose exec fuse-dev mount | grep -q "fuse.*${NAS_MOUNT_POINT}"; then
    echo "FUSE filesystem is already mounted at ${NAS_MOUNT_POINT}"
    
    # Verify the process is running
    if ! docker-compose exec fuse-dev pgrep -f nas-emu-fuse > /dev/null; then
        echo "Warning: FUSE mount exists but process not found. Attempting to remount..."
        # Unmount the stale mount
        docker-compose exec fuse-dev umount -f "${NAS_MOUNT_POINT}" || {
            echo "Failed to unmount stale FUSE filesystem. Will attempt to continue anyway."
        }
        # Continue to remounting
    else
        # Everything is fine, exit
        echo "FUSE driver is running."
        echo "Storage path: ${NAS_STORAGE_PATH}"
        echo "Mount point: ${NAS_MOUNT_POINT}"
        echo ""
        echo "You can access the FUSE filesystem inside the container at ${NAS_MOUNT_POINT}"
        exit 0
    fi
fi

# Check if the mount point is in use by a non-FUSE filesystem
if docker-compose exec fuse-dev mount | grep -q "${NAS_MOUNT_POINT}"; then
    echo "Warning: Mount point ${NAS_MOUNT_POINT} is in use by a non-FUSE filesystem."
    echo "Attempting to unmount..."
    docker-compose exec fuse-dev umount -f "${NAS_MOUNT_POINT}" || {
        echo "ERROR: Failed to unmount existing filesystem at ${NAS_MOUNT_POINT}"
        echo "Please manually unmount it or choose a different mount point."
        exit 1
    }
    echo "Successfully unmounted existing filesystem."
fi

echo "Mounting FUSE filesystem at ${NAS_MOUNT_POINT}..."

# Create mount directory if it doesn't exist
docker-compose exec fuse-dev mkdir -p "${NAS_MOUNT_POINT}"

# Kill any existing FUSE process
docker-compose exec fuse-dev pkill -f nas-emu-fuse || true

# Run the FUSE driver
docker-compose exec -d fuse-dev /app/src/fuse-driver/nas-emu-fuse \
    "${NAS_MOUNT_POINT}" \
    --storage="${NAS_STORAGE_PATH}" \
    --log="${NAS_LOG_FILE}" \
    --loglevel="${NAS_LOG_LEVEL}"

# Wait a moment for the filesystem to mount
sleep 2

# Verify the mount
if docker-compose exec fuse-dev mount | grep -q "fuse.*${NAS_MOUNT_POINT}"; then
    echo "FUSE filesystem mounted successfully at ${NAS_MOUNT_POINT}"
else
    echo "Warning: FUSE mount not detected after startup."
    # Check if the process is at least running
    if docker-compose exec fuse-dev pgrep -f nas-emu-fuse > /dev/null; then
        echo "FUSE driver process is running. It may still be initializing."
    else
        echo "ERROR: FUSE driver process is not running. Mount failed!"
        # Try to see what went wrong
        echo "Checking logs for errors:"
        docker-compose exec fuse-dev cat "${NAS_LOG_FILE}" 2>/dev/null || echo "No log file found."
        exit 1
    fi
fi

echo "FUSE driver is running."
echo "Storage path: ${NAS_STORAGE_PATH}"
echo "Mount point: ${NAS_MOUNT_POINT}"
echo ""
echo "You can access the FUSE filesystem inside the container at ${NAS_MOUNT_POINT}"