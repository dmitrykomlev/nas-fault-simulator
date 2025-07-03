# Multi-stage build for NAS Fault Simulator
# Build stage - compile FUSE driver
FROM ubuntu:22.04 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    fuse \
    libfuse-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Set build-time environment variables
ENV NAS_MOUNT_POINT=/mnt/nas-mount \
    NAS_STORAGE_PATH=/var/nas-storage \
    NAS_LOG_FILE=/var/log/nas-emu.log \
    NAS_LOG_LEVEL=2

# Copy source code
WORKDIR /app/src/fuse-driver
COPY src/fuse-driver/src/ ./src/
COPY src/fuse-driver/Makefile ./

# Build the FUSE driver
RUN make clean && make

# Runtime stage - final image
FROM ubuntu:22.04 AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    fuse \
    samba \
    smbclient \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Set environment variables with default values
ENV NAS_MOUNT_POINT=/mnt/nas-mount \
    NAS_STORAGE_PATH=/var/nas-storage \
    NAS_LOG_FILE=/var/log/nas-emu.log \
    NAS_LOG_LEVEL=2 \
    SMB_SHARE_NAME=nasshare \
    SMB_USERNAME=nasusr \
    SMB_PASSWORD=naspass \
    USE_HOST_STORAGE=false \
    CONFIG_FILE=""

# Create necessary directories and SMB user
RUN mkdir -p ${NAS_MOUNT_POINT} && \
    mkdir -p ${NAS_STORAGE_PATH} && \
    mkdir -p $(dirname ${NAS_LOG_FILE}) && \
    mkdir -p /var/log/samba && \
    mkdir -p /configs && \
    useradd -m ${SMB_USERNAME}

# Copy built FUSE binary from builder stage
COPY --from=builder /app/src/fuse-driver/nas-emu-fuse /usr/local/bin/nas-emu-fuse
RUN chmod +x /usr/local/bin/nas-emu-fuse

# Copy SMB configuration template
COPY src/fuse-driver/docker/smb.conf /etc/samba/smb.conf.template

# Copy test configuration files
COPY src/fuse-driver/tests/configs/ /configs/

# Copy and setup entrypoint script
COPY src/fuse-driver/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Use entrypoint to configure and run all services  
ENTRYPOINT ["/entrypoint.sh"]