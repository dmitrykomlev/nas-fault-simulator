#!/bin/bash
# Simple wrapper to run FUSE driver with specified config

set -e

# Handle command line arguments
CONFIG_FILE=""
STOP_CONTAINER=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --config=*)
      CONFIG_FILE="${1#*=}"
      shift
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --stop)
      STOP_CONTAINER=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--config=/path/to/config.conf] [--stop]"
      exit 1
      ;;
  esac
done

# Source the central configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/config.sh"

# Handle stop request
if [ "$STOP_CONTAINER" = true ]; then
    echo "Stopping containers..."
    docker compose down
    exit 0
fi

# Validate config file is provided
if [ -z "${CONFIG_FILE}" ]; then
    echo "ERROR: CONFIG_FILE must be specified"
    echo "Usage: $0 --config=config_file.conf"
    exit 1
fi

# Check if config file exists (if it's a path, not just filename)
if [[ "${CONFIG_FILE}" == /* ]] || [[ "${CONFIG_FILE}" == ./* ]]; then
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "ERROR: Config file does not exist: ${CONFIG_FILE}"
        exit 1
    fi
fi

echo "Starting FUSE driver with config: ${CONFIG_FILE}"

# Check if image exists, build if needed
if ! docker images nas-fault-simulator-fuse-dev | grep -q nas-fault-simulator-fuse-dev; then
    echo "Docker image not found, building..."
    "${SCRIPT_DIR}/build.sh"
fi

# Start container with pure docker run
CONTAINER_NAME="nas-fault-simulator"

# Stop any existing container
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

# Find a free port for SMB (start from 1445)
SMB_PORT=1445
while netstat -ln | grep -q ":${SMB_PORT} "; do
    SMB_PORT=$((SMB_PORT + 1))
done

# Start container with dynamic port
docker run -d \
    --name "${CONTAINER_NAME}" \
    --privileged \
    --cap-add SYS_ADMIN \
    --device /dev/fuse:/dev/fuse \
    --security-opt apparmor:unconfined \
    -p "${SMB_PORT}:445" \
    -v "${PROJECT_ROOT}/nas-storage:/var/nas-storage" \
    -v "${PROJECT_ROOT}/src/fuse-driver/tests/configs:/configs:ro" \
    -e "CONFIG_FILE=${CONFIG_FILE}" \
    -e "NAS_MOUNT_POINT=/mnt/nas-mount" \
    -e "NAS_STORAGE_PATH=/var/nas-storage" \
    -e "NAS_LOG_FILE=/var/log/nas-emu.log" \
    -e "NAS_LOG_LEVEL=3" \
    -e "SMB_SHARE_NAME=nasshare" \
    -e "SMB_USERNAME=nasusr" \
    -e "SMB_PASSWORD=naspass" \
    -e "USE_HOST_STORAGE=true" \
    nas-fault-simulator-fuse-dev

if [ $? -eq 0 ]; then
    echo "Container started successfully"
    echo "Container name: ${CONTAINER_NAME}"
    echo "SMB port: ${SMB_PORT}"
    echo "FUSE driver will be available shortly"
    echo ""
    echo "To access SMB share:"
    echo "  smb://nasusr:naspass@localhost:${SMB_PORT}/nasshare"
    echo ""
    echo "To stop container:"
    echo "  docker stop ${CONTAINER_NAME}"
else
    echo "Failed to start container"
    exit 1
fi