#!/bin/bash
# Script to mount the SMB share on the host system for testing

set -e

# Source the central configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/config.sh"

# Define the local mount point
LOCAL_MOUNT_POINT="${PROJECT_ROOT}/nas-mount"

# Check if already mounted
if mount | grep -q "${LOCAL_MOUNT_POINT}"; then
    echo "SMB share is already mounted at ${LOCAL_MOUNT_POINT}"
    exit 0
fi

# Create the mount point if it doesn't exist
mkdir -p "${LOCAL_MOUNT_POINT}"

# Check if Docker container is running
if ! docker-compose ps | grep -q "fuse-dev.*Up"; then
    echo "Starting Docker container and FUSE driver..."
    ${SCRIPT_DIR}/run-fuse.sh
fi

# Provide feedback
echo "Mounting SMB share at ${LOCAL_MOUNT_POINT}..."
echo "Share: //localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME}"
echo "Username: ${SMB_USERNAME}"
echo "Password: ${SMB_PASSWORD}"

# Mount the share
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    mount_smbfs "//${SMB_USERNAME}:${SMB_PASSWORD}@localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME}" "${LOCAL_MOUNT_POINT}"
else
    # Linux
    mount -t cifs "//localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME}" "${LOCAL_MOUNT_POINT}" -o "username=${SMB_USERNAME},password=${SMB_PASSWORD},vers=3.0"
fi

# Check if the mount was successful
if mount | grep -q "${LOCAL_MOUNT_POINT}"; then
    echo "SMB share mounted successfully at ${LOCAL_MOUNT_POINT}"
    echo ""
    echo "You can now access the NAS Emulator filesystem at ${LOCAL_MOUNT_POINT}"
    echo "Write operations to this mount will go through the FUSE driver with fault injection."
else
    echo "Failed to mount SMB share"
    exit 1
fi