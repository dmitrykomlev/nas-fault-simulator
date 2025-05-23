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
    
    # Stop container
    echo "Stopping test container..."
    cd "${PROJECT_ROOT}"
    docker compose down || true
    
    echo -e "${GREEN}Cleanup completed${NC}"
}

# Main test runner function
run_test_with_config() {
    local config_name="$1"
    local test_name="$2"
    local test_function="$3"
    
    if [ -z "$config_name" ] || [ -z "$test_name" ] || [ -z "$test_function" ]; then
        echo -e "${RED}ERROR: Missing required parameters${NC}"
        echo "Usage: run_test_with_config \"config_name.conf\" \"test_name\" test_function"
        return 1
    fi
    
    # Set up test variables
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
    
    # Step 1: Build FUSE driver
    echo -e "\n${YELLOW}Step 1: Building FUSE driver...${NC}"
    cd "${PROJECT_ROOT}"
    
    "${PROJECT_ROOT}/scripts/build-fuse.sh" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        report_result "FUSE Build" 0 "FUSE driver built successfully"
    else
        report_result "FUSE Build" 1 "FUSE driver build failed"
        return 1
    fi
    
    # Step 2: Start container with FUSE and SMB services
    echo -e "\n${YELLOW}Step 2: Starting container with configuration...${NC}"
    
    # Create test directory structure (SMB mount and storage backdoor)
    mkdir -p "${TEST_DIR}"
    mkdir -p "${HOST_MOUNT_POINT}"
    mkdir -p "${DEV_HOST_STORAGE_PATH}"
    
    # Stop any existing container
    docker compose down || true
    
    # Use host storage for advanced tests to allow backdoor access for verification
    export USE_HOST_STORAGE=true
    export DEV_HOST_STORAGE_PATH="${TEST_DIR}/nas-storage"
    
    # Start container with test-specific config and internal storage
    cd "${PROJECT_ROOT}"
    export CONFIG_FILE="${CONFIG_NAME}"
    docker compose up -d > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 5  # Allow services to initialize
        report_result "Container Startup" 0 "Container with FUSE and SMB started successfully"
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
    
    # Clean up test environment on normal completion
    cleanup_test_environment
    
    if [ ${TESTS_FAILED} -eq 0 ]; then
        echo -e "${GREEN}Overall result: SUCCESS${NC}"
        return 0
    else
        echo -e "${RED}Overall result: FAILURE (${TESTS_FAILED} failed)${NC}"
        return 1
    fi
}