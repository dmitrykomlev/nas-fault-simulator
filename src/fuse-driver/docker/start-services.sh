#!/bin/bash
# Start services in the container

# Replace environment variables in smb.conf
sed -i "s|\${SMB_SHARE_NAME}|$SMB_SHARE_NAME|g" /etc/samba/smb.conf
sed -i "s|\${NAS_MOUNT_POINT}|$NAS_MOUNT_POINT|g" /etc/samba/smb.conf
sed -i "s|\${SMB_USERNAME}|$SMB_USERNAME|g" /etc/samba/smb.conf

# Make sure the FUSE mount directory exists and has correct permissions
mkdir -p $NAS_MOUNT_POINT
chmod 777 $NAS_MOUNT_POINT

# Start Samba services
service smbd start
service nmbd start

# Keep container running
tail -f /dev/null