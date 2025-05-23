#!/bin/bash
set -e

# Configure storage based on USE_HOST_STORAGE
if [ "$USE_HOST_STORAGE" = "true" ]; then
    echo "Using host storage volume mount at: $NAS_STORAGE_PATH"
    # Storage directory should be mounted as volume
    if [ ! -d "$NAS_STORAGE_PATH" ]; then
        echo "ERROR: Host storage path $NAS_STORAGE_PATH not mounted"
        exit 1
    fi
else
    echo "Using container internal storage at: $NAS_STORAGE_PATH"
    # Ensure internal storage directory exists
    mkdir -p "$NAS_STORAGE_PATH"
    chmod 755 "$NAS_STORAGE_PATH"
fi

# Set SMB password
(echo "$SMB_PASSWORD"; echo "$SMB_PASSWORD") | smbpasswd -a "$SMB_USERNAME" -s

# Generate SMB config from template with env var substitution
envsubst < /etc/samba/smb.conf.template > /etc/samba/smb.conf

# Ensure directories exist
mkdir -p "$NAS_MOUNT_POINT" "$(dirname "$NAS_LOG_FILE")"

# Start SMB services in background
service smbd start
service nmbd start

# Determine config file path
if [ -n "$CONFIG_FILE" ]; then
    if [[ "$CONFIG_FILE" != /* ]] && [[ "$CONFIG_FILE" != ./* ]]; then
        FUSE_CONFIG="/configs/$CONFIG_FILE"
    else
        FUSE_CONFIG="$CONFIG_FILE"
    fi
    echo "Using FUSE config: $FUSE_CONFIG"
else
    FUSE_CONFIG="/configs/no_faults.conf"
    echo "Using default config: $FUSE_CONFIG"
fi

# Start FUSE driver
echo "Starting FUSE driver with config: $FUSE_CONFIG"
/usr/local/bin/nas-emu-fuse "$NAS_MOUNT_POINT" \
    --storage="$NAS_STORAGE_PATH" \
    --log="$NAS_LOG_FILE" \
    --loglevel="$NAS_LOG_LEVEL" \
    --config="$FUSE_CONFIG" &

# Wait a moment for FUSE to initialize
sleep 2

# Keep container running and monitor services
echo "All services started successfully"
tail -f /dev/null