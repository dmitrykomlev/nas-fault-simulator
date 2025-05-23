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

# Export config file for docker-compose
export CONFIG_FILE

# Start the container - the entrypoint will handle everything
docker compose up -d

echo "Container started successfully"
echo "FUSE driver will be available shortly"