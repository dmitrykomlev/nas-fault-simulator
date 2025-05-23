#!/bin/bash
# Script to unmount the SMB share from the host system

set -e

# Source the central configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/config.sh"

# Define the local mount point
LOCAL_MOUNT_POINT="${PROJECT_ROOT}/nas-mount"

# Check if mounted
if ! mount | grep -q "${LOCAL_MOUNT_POINT}"; then
    echo "No SMB share is mounted at ${LOCAL_MOUNT_POINT}"
    exit 0
fi

# Unmount the share
echo "Unmounting SMB share from ${LOCAL_MOUNT_POINT}..."

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    umount "${LOCAL_MOUNT_POINT}"
else
    # Linux
    umount "${LOCAL_MOUNT_POINT}"
fi

# Check if the unmount was successful
if ! mount | grep -q "${LOCAL_MOUNT_POINT}"; then
    echo "SMB share unmounted successfully"
else
    echo "Failed to unmount SMB share"
    exit 1
fi