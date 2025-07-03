#!/bin/bash
# Simplified build script for multi-stage Docker build
# This replaces the old build-fuse.sh script

set -e

# Source the central configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/config.sh"

echo "Building NAS Fault Simulator using multi-stage Docker build..."
cd "${PROJECT_ROOT}"

# Build the multi-stage image
echo "Building Docker image with integrated FUSE compilation..."
docker build -t nas-fault-simulator-fuse-dev .

if [ $? -eq 0 ]; then
    echo "✅ Build completed successfully!"
    echo "📦 Image: nas-fault-simulator-fuse-dev"
    echo "🚀 Ready to run with: docker-compose up -d"
else
    echo "❌ Build failed!"
    exit 1
fi

echo ""
echo "Build Summary:"
echo "- FUSE driver compiled in builder stage"
echo "- Runtime image created with compiled binary"
echo "- No build artifacts left on host"
echo "- Ready for deployment"