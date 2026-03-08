#!/bin/bash
#=============================================================================
# test_production_skeleton.sh - Simple test skeleton for production scenarios
#=============================================================================
# This is a simple test skeleton that demonstrates the new testing approach:
# 1. Runs Docker container with a specific test configuration
# 2. Mounts the SMB share on the host system (macOS/Linux compatible)
# 3. Waits 5 seconds
# 4. Shuts down the container and exits
#
# This skeleton serves as the foundation for more complex tests that will:
# - Test file read/write operations through the mounted share
# - Verify fault injection behavior according to configuration
# - Access real FUSE driver storage through the host nas-storage directory
#
# Usage:
#   ./test_production_skeleton.sh [config_name]
#   
# Example:
#   ./test_production_skeleton.sh corruption_high.conf
#
# Requirements:
#   - Docker and docker compose
#   - SMB client utilities (smbclient, mount commands)
#   - Appropriate privileges for mounting filesystems
#=============================================================================

set -e  # Exit on any error

# Handle different readlink implementations (macOS vs Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS doesn't have readlink -f
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
else
    # Linux
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
fi

# Get project root (go up from functional -> tests -> fuse-driver -> src -> project root)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)

# Source configuration
source "${PROJECT_ROOT}/scripts/config.sh"

# Test configuration
CONFIG_NAME="${1:-corruption_high.conf}"
CONFIGS_DIR="${PROJECT_ROOT}/src/fuse-driver/tests/configs"
HOST_MOUNT_POINT="${PROJECT_ROOT}/nas-mount-test"
CONTAINER_NAME="nas-fault-simulator-fuse-dev-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "==================================================================="
echo "NAS Fault Simulator - Production Test Skeleton"
echo "==================================================================="
echo "Test config: ${CONFIG_NAME}"
echo "Host mount point: ${HOST_MOUNT_POINT}"
echo "Host storage path: ${DEV_HOST_STORAGE_PATH}"
echo "Container: ${CONTAINER_NAME}"
echo "==================================================================="

# Cleanup function to ensure clean shutdown
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    
    # Unmount SMB share if mounted
    if mount | grep -q "${HOST_MOUNT_POINT}"; then
        echo "Unmounting SMB share..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            umount -f "${HOST_MOUNT_POINT}" 2>/dev/null || true
        else
            umount -fl "${HOST_MOUNT_POINT}" 2>/dev/null || true
        fi
    fi
    
    # Remove mount point directory
    if [ -d "${HOST_MOUNT_POINT}" ]; then
        rmdir "${HOST_MOUNT_POINT}" 2>/dev/null || true
    fi
    
    # Stop container
    echo "Stopping container..."
    cd "${PROJECT_ROOT}"
    docker compose down || true
    
    echo -e "${GREEN}Cleanup completed${NC}"
}

# Set trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

# Step 1: Verify configuration exists
echo -e "\n${YELLOW}Step 1: Verifying configuration...${NC}"
CONFIG_FILE="${CONFIGS_DIR}/${CONFIG_NAME}"
if [ ! -f "${CONFIG_FILE}" ]; then
    echo -e "${RED}ERROR: Configuration file not found: ${CONFIG_FILE}${NC}"
    echo "Available configurations:"
    ls -1 "${CONFIGS_DIR}/"
    exit 1
fi
echo -e "${GREEN}Configuration found: ${CONFIG_FILE}${NC}"

# Step 2: Stop any existing container and start fresh with config
echo -e "\n${YELLOW}Step 2: Starting container with configuration...${NC}"
cd "${PROJECT_ROOT}"

# Stop any existing container
echo "Stopping any existing container..."
docker compose down || true

# Set the CONFIG_FILE environment variable for docker-compose
export CONFIG_FILE="${CONFIG_NAME}"
echo "Using CONFIG_FILE environment variable: ${CONFIG_FILE}"

# Start container
echo "Starting container..."
docker compose up -d

# Wait for container to be ready
echo "Waiting for container to start..."
sleep 3

# Verify container is running
if ! docker ps | grep -q "${CONTAINER_NAME}"; then
    echo -e "${RED}ERROR: Container ${CONTAINER_NAME} is not running${NC}"
    docker compose logs
    exit 1
fi
echo -e "${GREEN}Container started successfully${NC}"

# Step 3: Build and start FUSE driver with test configuration
echo -e "\n${YELLOW}Step 3: Configuring FUSE driver...${NC}"

# Build FUSE driver
echo "Building FUSE driver..."
"${PROJECT_ROOT}/scripts/build-fuse.sh"

# Start FUSE driver with test configuration using our updated script
echo "Starting FUSE driver with test configuration..."
CONFIG_FILE="${CONFIG_NAME}" "${PROJECT_ROOT}/scripts/run-fuse.sh"

echo -e "${GREEN}FUSE driver started with configuration: ${CONFIG_NAME}${NC}"

# Step 4: Mount SMB share on host
echo -e "\n${YELLOW}Step 4: Mounting SMB share on host...${NC}"

# Create mount point
mkdir -p "${HOST_MOUNT_POINT}"

# Wait a bit for SMB service to be fully ready
sleep 3

# Mount based on OS
echo "Attempting to mount SMB share..."
MOUNT_SUCCESS=1

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if command -v mount_smbfs >/dev/null 2>&1; then
        mount_smbfs "//${SMB_USERNAME}:${SMB_PASSWORD}@localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME}" "${HOST_MOUNT_POINT}" 2>/dev/null
        MOUNT_SUCCESS=$?
    else
        echo -e "${RED}ERROR: mount_smbfs not available on macOS${NC}"
        exit 1
    fi
else
    # Linux
    if command -v mount >/dev/null 2>&1; then
        mount -t cifs "//localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME}" "${HOST_MOUNT_POINT}" \
            -o "username=${SMB_USERNAME},password=${SMB_PASSWORD},vers=3.0" 2>/dev/null
        MOUNT_SUCCESS=$?
    else
        echo -e "${RED}ERROR: mount command not available on Linux${NC}"
        exit 1
    fi
fi

if [ ${MOUNT_SUCCESS} -eq 0 ] && mount | grep -q "${HOST_MOUNT_POINT}"; then
    echo -e "${GREEN}SMB share mounted successfully at ${HOST_MOUNT_POINT}${NC}"
    
    # Test basic access
    if touch "${HOST_MOUNT_POINT}/test_access.txt" 2>/dev/null; then
        echo -e "${GREEN}Write access to share confirmed${NC}"
        rm -f "${HOST_MOUNT_POINT}/test_access.txt"
    else
        echo -e "${RED}WARNING: Write access to share failed${NC}"
    fi
else
    echo -e "${RED}ERROR: Failed to mount SMB share${NC}"
    echo "This could be due to:"
    echo "- SMB service not fully initialized yet"
    echo "- Network connectivity issues"
    echo "- Authentication problems"
    echo "- Missing mount utilities"
    exit 1
fi

# Step 5: Display status and wait
echo -e "\n${YELLOW}Step 5: System status and wait...${NC}"
echo "Container status:"
docker ps | grep "${CONTAINER_NAME}" || echo "Container not found"

echo -e "\nMount status:"
mount | grep "${HOST_MOUNT_POINT}" || echo "Share not mounted"

echo -e "\nHost storage backdoor access:"
echo "Storage path: ${DEV_HOST_STORAGE_PATH}"
if [ -d "${DEV_HOST_STORAGE_PATH}" ]; then
    echo "Storage contents:"
    ls -la "${DEV_HOST_STORAGE_PATH}" | head -10
else
    echo "Storage directory not found"
fi

echo -e "\nConfiguration verification:"
echo "Active config: ${CONFIG_NAME}"
echo "Config file contents:"
echo "$(head -5 "${CONFIG_FILE}")"

echo -e "\n${GREEN}System ready for testing!${NC}"
echo "SMB share mounted at: ${HOST_MOUNT_POINT}"
echo "Storage backdoor at: ${DEV_HOST_STORAGE_PATH}"
echo "Waiting 5 seconds before shutdown..."

# Wait for 5 seconds
sleep 5

echo -e "\n${YELLOW}Test skeleton completed successfully${NC}"
echo "Container will be stopped and share unmounted by cleanup function"