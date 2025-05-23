#!/bin/bash
# Script to run the FUSE driver inside the Docker container

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

# Default config file location
DEFAULT_CONFIG_FILE="/app/src/fuse-driver/nas-emu-fuse.conf"
CONTAINER_CONFIG_FILE="${DEFAULT_CONFIG_FILE}"

# Handle stopping container if requested
if [ "$STOP_CONTAINER" = true ]; then
    echo "Stopping the container..."
    docker-compose down
    exit 0
fi

# Check if Docker container is running
if ! docker-compose ps | grep -q "fuse-dev.*Up"; then
    echo "Starting Docker container..."
    docker-compose up -d
fi

# Handle custom config file if provided
if [ -n "${CONFIG_FILE}" ]; then
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "ERROR: Specified config file does not exist: ${CONFIG_FILE}"
        exit 1
    fi
    
    # Determine the container path for the config file
    if [[ "${CONFIG_FILE}" == "${PROJECT_ROOT}"* ]]; then
        # If the path is within the project root, map it to the container's /app path
        REL_PATH="${CONFIG_FILE#${PROJECT_ROOT}/}"
        CONTAINER_CONFIG_FILE="/app/${REL_PATH}"
    else
        # If it's an external path, copy it to the container
        FILENAME=$(basename "${CONFIG_FILE}")
        echo "Copying config file to container..."
        docker cp "${CONFIG_FILE}" fuse-dev:/tmp/${FILENAME}
        CONTAINER_CONFIG_FILE="/tmp/${FILENAME}"
    fi
    
    echo "Using config file: ${CONFIG_FILE}"
    echo "Mapped to container path: ${CONTAINER_CONFIG_FILE}"
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
        # Everything is fine, check for SMB service status
        check_smb_service
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

# Run the FUSE driver with the specified config
docker-compose exec -d fuse-dev /app/src/fuse-driver/nas-emu-fuse \
    "${NAS_MOUNT_POINT}" \
    --storage="${NAS_STORAGE_PATH}" \
    --log="${NAS_LOG_FILE}" \
    --loglevel="${NAS_LOG_LEVEL}" \
    --config="${CONTAINER_CONFIG_FILE}"

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

# Function to check SMB service status and restart if needed
check_smb_service() {
    # Check if Samba is installed
    if ! docker-compose exec fuse-dev which smbd > /dev/null 2>&1; then
        echo "Samba is not installed in the container. Installing Samba..."
        docker-compose exec fuse-dev apt-get update
        docker-compose exec fuse-dev apt-get install -y samba smbclient

        # Create Samba user
        docker-compose exec fuse-dev bash -c "id ${SMB_USERNAME} || useradd -m ${SMB_USERNAME}"
        docker-compose exec fuse-dev bash -c "(echo ${SMB_PASSWORD}; echo ${SMB_PASSWORD}) | smbpasswd -a ${SMB_USERNAME} -s"

        # Configure Samba
        echo "Configuring Samba..."
        docker-compose exec fuse-dev bash -c "cat > /etc/samba/smb.conf << EOF
[global]
    workgroup = WORKGROUP
    server string = NAS Emulator
    security = user
    map to guest = bad user
    log file = /var/log/samba/log.%m
    max log size = 50
    dns proxy = no
    interfaces = lo eth0
    bind interfaces only = yes

[${SMB_SHARE_NAME}]
    path = ${NAS_MOUNT_POINT}
    browseable = yes
    read only = no
    writable = yes
    create mask = 0777
    directory mask = 0777
    valid users = ${SMB_USERNAME}
    force user = root
EOF"
    fi

    # Check if SMB is running - try different methods
    if ! docker-compose exec fuse-dev pgrep smbd > /dev/null 2>&1; then
        echo "SMB service is not running. Starting SMB service..."
        # Try service command first
        docker-compose exec fuse-dev service smbd start || \
        # If that fails, try systemctl
        docker-compose exec fuse-dev systemctl start smbd || \
        # As a last resort, start smbd directly
        docker-compose exec fuse-dev bash -c "smbd -D"

        # Start nmbd similarly
        docker-compose exec fuse-dev service nmbd start || \
        docker-compose exec fuse-dev systemctl start nmbd || \
        docker-compose exec fuse-dev bash -c "nmbd -D"
    else
        echo "SMB service is already running"
    fi

    # Provide connection information
    echo ""
    echo "SMB share is available at:"
    echo "  - Share name: ${SMB_SHARE_NAME}"
    echo "  - Username: ${SMB_USERNAME}"
    echo "  - Password: ${SMB_PASSWORD}"
    echo "  - Port: ${NAS_SMB_PORT}"
    echo ""
    echo "You can connect to the SMB share using the following command:"
    echo "  smbclient //localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME} -U ${SMB_USERNAME}%${SMB_PASSWORD}"
    echo ""
    echo "Or mount it on your local system with:"
    echo "  mkdir -p ~/nas-mount"
    echo "  mount -t cifs //localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME} ~/nas-mount -o username=${SMB_USERNAME},password=${SMB_PASSWORD},vers=3.0"
}

# Check SMB service status
check_smb_service

echo "FUSE driver is running."
echo "Storage path: ${NAS_STORAGE_PATH}"
echo "Mount point: ${NAS_MOUNT_POINT}"
echo ""
echo "You can access the FUSE filesystem inside the container at ${NAS_MOUNT_POINT}"