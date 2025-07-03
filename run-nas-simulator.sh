#!/bin/bash
# Simple end-user script for running NAS Fault Simulator
# This demonstrates the final user experience after web interface is added

set -e

# Default configuration
DEFAULT_CONFIG="no_faults.conf"
CONTAINER_NAME="nas-fault-simulator"
SMB_PORT=1445
HELP_TEXT="
NAS Fault Simulator - Easy-to-use local QA tool

Usage: $0 [OPTIONS]

Options:
  --config=FILE     Configuration file (default: no_faults.conf)
  --port=PORT       SMB port (default: 1445)
  --stop            Stop running container
  --help            Show this help

Examples:
  $0                              # Run with default config
  $0 --config=corruption_high.conf  # Run with specific config
  $0 --port=1446                  # Run on different port
  $0 --stop                       # Stop container

Once running, access SMB share at:
  smb://nasusr:naspass@localhost:1445/nasshare
"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --config=*)
      CONFIG_FILE="${1#*=}"
      shift
      ;;
    --port=*)
      SMB_PORT="${1#*=}"
      shift
      ;;
    --stop)
      echo "Stopping NAS Fault Simulator..."
      docker stop "${CONTAINER_NAME}" 2>/dev/null || true
      docker rm "${CONTAINER_NAME}" 2>/dev/null || true
      echo "Container stopped"
      exit 0
      ;;
    --help)
      echo "$HELP_TEXT"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Set default config if not specified
CONFIG_FILE="${CONFIG_FILE:-$DEFAULT_CONFIG}"

echo "=================================================="
echo "NAS Fault Simulator - Starting..."
echo "=================================================="
echo "Configuration: ${CONFIG_FILE}"
echo "SMB Port: ${SMB_PORT}"
echo "Container: ${CONTAINER_NAME}"
echo "=================================================="

# Check if port is available
if netstat -ln | grep -q ":${SMB_PORT} "; then
    echo "ERROR: Port ${SMB_PORT} is already in use"
    echo "Use --port=PORT to specify a different port"
    exit 1
fi

# Stop any existing container
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

# Check if image exists
if ! docker images nas-fault-simulator-fuse-dev | grep -q nas-fault-simulator-fuse-dev; then
    echo "ERROR: Docker image 'nas-fault-simulator-fuse-dev' not found"
    echo "Please build the image first with: ./scripts/build.sh"
    exit 1
fi

# Create storage directory
mkdir -p ./nas-storage

# Start container
echo "Starting container..."
docker run -d \
    --name "${CONTAINER_NAME}" \
    --privileged \
    --cap-add SYS_ADMIN \
    --device /dev/fuse:/dev/fuse \
    --security-opt apparmor:unconfined \
    -p "${SMB_PORT}:445" \
    -v "$(pwd)/nas-storage:/var/nas-storage" \
    -v "$(pwd)/src/fuse-driver/tests/configs:/configs:ro" \
    -e "CONFIG_FILE=${CONFIG_FILE}" \
    -e "NAS_MOUNT_POINT=/mnt/nas-mount" \
    -e "NAS_STORAGE_PATH=/var/nas-storage" \
    -e "NAS_LOG_FILE=/var/log/nas-emu.log" \
    -e "NAS_LOG_LEVEL=2" \
    -e "SMB_SHARE_NAME=nasshare" \
    -e "SMB_USERNAME=nasusr" \
    -e "SMB_PASSWORD=naspass" \
    -e "USE_HOST_STORAGE=true" \
    nas-fault-simulator-fuse-dev

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ NAS Fault Simulator started successfully!"
    echo ""
    echo "📁 SMB Share Access:"
    echo "  smb://nasusr:naspass@localhost:${SMB_PORT}/nasshare"
    echo ""
    echo "📂 Local Storage:"
    echo "  ./nas-storage/"
    echo ""
    echo "🔧 Configuration:"
    echo "  ${CONFIG_FILE}"
    echo ""
    echo "🛑 To stop:"
    echo "  $0 --stop"
    echo ""
    echo "📋 Container logs:"
    echo "  docker logs ${CONTAINER_NAME}"
    echo ""
else
    echo "❌ Failed to start container"
    exit 1
fi