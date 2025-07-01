#!/bin/bash
#=============================================================================
# test_framework.sh - Reusable test framework for production scenarios
#=============================================================================
# This framework provides a reusable test infrastructure that:
# 1. Starts a fresh container with specified configuration
# 2. Mounts SMB share on the host
# 3. Calls user-provided test logic function
# 4. Cleans up container and resources
#
# Usage:
#   source test_framework.sh
#   run_test_with_config "config_name.conf" "test_name" test_function
#
# The test_function will be called with:
#   - $HOST_MOUNT_POINT: Path to mounted SMB share
#   - $DEV_HOST_STORAGE_PATH: Path to storage backdoor
#   - $TEST_NAME: Name of the test
#=============================================================================

# Handle different readlink implementations (macOS vs Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
else
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
fi

# Get project root and source configuration
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
source "${PROJECT_ROOT}/scripts/config.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0

# Function to report test results
report_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name - $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name - $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Cleanup function
cleanup_test_environment() {
    echo -e "\n${YELLOW}Cleaning up test environment...${NC}"
    
    # Unmount SMB share
    if mount | grep -q "${HOST_MOUNT_POINT}"; then
        echo "Unmounting SMB share..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            umount -f "${HOST_MOUNT_POINT}" 2>/dev/null || true
        else
            umount -fl "${HOST_MOUNT_POINT}" 2>/dev/null || true
        fi
    fi
    
    # Clean up entire test directory
    if [ -d "${TEST_DIR}" ]; then
        rm -rf "${TEST_DIR}" 2>/dev/null || true
    fi
    
    # Stop container (pure docker approach)
    echo "Stopping test container..."
    docker stop "${CONTAINER_NAME}" 2>/dev/null || true
    docker rm "${CONTAINER_NAME}" 2>/dev/null || true
    
    echo -e "${GREEN}Cleanup completed${NC}"
}

# Main test runner function
run_test_with_config() {
    local config_name="$1"
    local test_name="$2"
    local test_function="$3"
    
    if [ -z "$config_name" ] || [ -z "$test_name" ] || [ -z "$test_function" ]; then
        echo -e "${RED}ERROR: Missing required parameters${NC}"
        echo "Usage: run_test_with_config \"config_name.conf\" \"test_name\" test_function [--cleanup-on-failure]"
        return 1
    fi
    
    # Check if cleanup on failure is requested (for automated test runs)
    local cleanup_on_failure=false
    if [ "$CLEANUP_ON_FAILURE" = "true" ] || [[ "$*" =~ --cleanup-on-failure ]]; then
        cleanup_on_failure=true
    fi
    
    # Load environment variables from .env file with defaults first
    source "${PROJECT_ROOT}/.env" 2>/dev/null || true
    
    # Set up test variables (these override .env settings)
    export TEST_NAME="$test_name"
    export CONFIG_NAME="$config_name"
    export CONTAINER_NAME="nas-fault-simulator-fuse-dev-1"
    
    # Test-specific directory structure (SMB mount and storage backdoor)
    export TEST_DIR="${PROJECT_ROOT}/tests-${test_name}"
    export HOST_MOUNT_POINT="${TEST_DIR}/smb-mount"          # Where SMB share gets mounted on host
    export DEV_HOST_STORAGE_PATH="${TEST_DIR}/nas-storage"   # Storage backdoor for verification
    
    # Clean up any existing test directory from previous runs
    if [ -d "${TEST_DIR}" ]; then
        # Unmount SMB if mounted
        if mount | grep -q "${HOST_MOUNT_POINT}"; then
            umount "${HOST_MOUNT_POINT}" 2>/dev/null || true
        fi
        # Remove entire test directory
        rm -rf "${TEST_DIR}"
    fi
    
    local test_start_time=$(date +%s)
    
    echo "==================================================================="
    echo "NAS Fault Simulator - Test Framework"
    echo "==================================================================="
    echo "Test: ${TEST_NAME}"
    echo "Config: ${CONFIG_NAME}"
    echo "Test directory: ${TEST_DIR}"
    echo "SMB mount point: ${HOST_MOUNT_POINT}"
    echo "Storage backdoor: ${DEV_HOST_STORAGE_PATH}"
    echo "Storage mode: Host volume (USE_HOST_STORAGE=true)"
    echo "==================================================================="
    
    # Set cleanup trap only for interruptions (not normal exit)
    trap cleanup_test_environment INT TERM
    
    # Step 1: Build FUSE driver (unless skip is requested)
    if [ "${SKIP_FUSE_BUILD}" != "true" ]; then
        echo -e "\n${YELLOW}Step 1: Building FUSE driver...${NC}"
        cd "${PROJECT_ROOT}"
        
        "${PROJECT_ROOT}/scripts/build-fuse.sh" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            report_result "FUSE Build" 0 "FUSE driver built successfully"
        else
            report_result "FUSE Build" 1 "FUSE driver build failed"
            return 1
        fi
    else
        echo -e "\n${YELLOW}Step 1: Skipping FUSE build (already built)${NC}"
        report_result "FUSE Build" 0 "FUSE driver build skipped (pre-built)"
    fi
    
    # Step 2: Start container with FUSE and SMB services
    echo -e "\n${YELLOW}Step 2: Starting container with configuration...${NC}"
    
    # Create test directory structure (SMB mount and storage backdoor)
    mkdir -p "${TEST_DIR}"
    mkdir -p "${HOST_MOUNT_POINT}"
    mkdir -p "${DEV_HOST_STORAGE_PATH}"
    
    # Stop any existing containers (pure docker approach)
    docker stop "${CONTAINER_NAME}" 2>/dev/null || true
    docker rm "${CONTAINER_NAME}" 2>/dev/null || true
    
    # Build the image if it doesn't exist
    cd "${PROJECT_ROOT}"
    if ! docker images nas-fault-simulator-fuse-dev | grep -q nas-fault-simulator-fuse-dev; then
        echo "Building container image..."
        docker compose build fuse-dev > /dev/null 2>&1
    fi
    
    # Find a free port for SMB (start from 1445)
    local smb_port=1445
    while netstat -ln | grep -q ":${smb_port} "; do
        smb_port=$((smb_port + 1))
    done
    
    # Environment variables already loaded at the beginning
    
    # Start container with dynamic config mounting using pure docker run
    # This approach keeps the container test-agnostic while allowing test configs
    docker run -d \
        --name "${CONTAINER_NAME}" \
        --privileged \
        --cap-add SYS_ADMIN \
        --device /dev/fuse:/dev/fuse \
        --security-opt apparmor:unconfined \
        -p "${smb_port}:445" \
        -v "${TEST_DIR}/nas-storage:${NAS_STORAGE_PATH:-/var/nas-storage}" \
        -v "${PROJECT_ROOT}/src/fuse-driver/tests/configs:/configs:ro" \
        -e "NAS_MOUNT_POINT=${NAS_MOUNT_POINT:-/mnt/nas-mount}" \
        -e "NAS_STORAGE_PATH=${NAS_STORAGE_PATH:-/var/nas-storage}" \
        -e "NAS_LOG_FILE=${NAS_LOG_FILE:-/var/log/nas-emu.log}" \
        -e "NAS_LOG_LEVEL=${NAS_LOG_LEVEL:-3}" \
        -e "SMB_SHARE_NAME=${SMB_SHARE_NAME:-nasshare}" \
        -e "SMB_USERNAME=${SMB_USERNAME:-nasusr}" \
        -e "SMB_PASSWORD=${SMB_PASSWORD:-naspass}" \
        -e "CONFIG_FILE=${CONFIG_NAME}" \
        -e "USE_HOST_STORAGE=true" \
        nas-fault-simulator-fuse-dev > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        sleep 5  # Allow services to initialize
        export NAS_SMB_PORT="${smb_port}"  # Update port for SMB mounting
        report_result "Container Startup" 0 "Container with FUSE and SMB started successfully (port ${smb_port})"
    else
        report_result "Container Startup" 1 "Failed to start container with services"
        return 1
    fi
    
    # Step 3: Mount SMB share
    echo -e "\n${YELLOW}Step 3: Mounting SMB share...${NC}"
    
    mkdir -p "${HOST_MOUNT_POINT}"
    sleep 5  # Wait for SMB service
    
    local mount_success=1
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mount_smbfs "//${SMB_USERNAME}:${SMB_PASSWORD}@localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME}" "${HOST_MOUNT_POINT}" 2>/dev/null
        mount_success=$?
    else
        mount -t cifs "//localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME}" "${HOST_MOUNT_POINT}" \
            -o "username=${SMB_USERNAME},password=${SMB_PASSWORD},vers=3.0" 2>/dev/null
        mount_success=$?
    fi
    
    if [ ${mount_success} -eq 0 ] && mount | grep -q "${HOST_MOUNT_POINT}"; then
        report_result "SMB Mount" 0 "SMB share mounted successfully"
    else
        report_result "SMB Mount" 1 "Failed to mount SMB share"
        return 1
    fi
    
    # Step 4: Run user-provided test logic
    echo -e "\n${YELLOW}Step 4: Running test logic...${NC}"
    
    # Call the user's test function
    if $test_function; then
        report_result "Test Logic" 0 "User test completed successfully"
    else
        report_result "Test Logic" 1 "User test failed"
        return 1
    fi
    
    # Step 5: Report results
    echo -e "\n==================================================================="
    echo "Test Results Summary"
    echo "==================================================================="
    
    local test_end_time=$(date +%s)
    local test_duration=$((test_end_time - test_start_time))
    
    echo "Test: ${TEST_NAME}"
    echo "Duration: ${test_duration} seconds"
    echo "Tests passed: ${TESTS_PASSED}"
    echo "Tests failed: ${TESTS_FAILED}"
    
    # Decide whether to clean up based on test result and cleanup policy
    if [ ${TESTS_FAILED} -eq 0 ]; then
        # Always clean up on success
        cleanup_test_environment
        echo -e "${GREEN}Overall result: SUCCESS${NC}"
        return 0
    else
        # On failure, only clean up if explicitly requested
        if [ "$cleanup_on_failure" = "true" ]; then
            cleanup_test_environment
            echo -e "${RED}Overall result: FAILURE (${TESTS_FAILED} failed)${NC}"
        else
            echo -e "${YELLOW}Test environment preserved for debugging${NC}"
            echo -e "${YELLOW}Container: ${CONTAINER_NAME}${NC}"
            echo -e "${YELLOW}SMB mount: ${HOST_MOUNT_POINT}${NC}"
            echo -e "${YELLOW}Storage: ${DEV_HOST_STORAGE_PATH}${NC}"
            echo -e "${YELLOW}To clean up manually, run:${NC}"
            echo -e "${YELLOW}  docker stop ${CONTAINER_NAME} && docker rm ${CONTAINER_NAME}${NC}"
            echo -e "${YELLOW}  umount '${HOST_MOUNT_POINT}' 2>/dev/null || true${NC}"
            echo -e "${YELLOW}  rm -rf '${TEST_DIR}'${NC}"
            echo -e "${RED}Overall result: FAILURE (${TESTS_FAILED} failed)${NC}"
        fi
        return 1
    fi
}