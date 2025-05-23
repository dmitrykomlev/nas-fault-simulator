#!/bin/bash
# test_helpers.sh - Common test helper functions

# Source the central configuration
# Handle different readlink implementations (macOS vs Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS doesn't have readlink -f
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
else
    # Linux
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
fi

# First go to the functional tests dir, then up to tests, then up to fuse-driver, then up to src, then up to project root
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
source "${PROJECT_ROOT}/scripts/config.sh"

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test group tracking
CURRENT_TEST_GROUP=""
TEST_GROUP_FAILED=0
TEST_GROUP_COUNT=0

# Verify the FUSE driver is running properly
verify_fuse_driver() {
    echo "Verifying FUSE driver is running..."
    
    # Check if there's a FUSE filesystem mounted at the mount point
    if ! mount | grep -q "fuse.*${NAS_MOUNT_POINT}"; then
        echo -e "${RED}ERROR: No FUSE filesystem is mounted at ${NAS_MOUNT_POINT}${NC}"
        echo "Regular filesystem mount (if any):"
        mount | grep "${NAS_MOUNT_POINT}" || echo "No filesystem mounted at ${NAS_MOUNT_POINT}"
        return 1
    fi
    
    # Check if the FUSE driver process is running
    if ! pgrep -f nas-emu-fuse > /dev/null; then
        echo -e "${RED}ERROR: FUSE driver process (nas-emu-fuse) is not running${NC}"
        return 1
    fi
    
    # Create a test file with a unique identifier
    local TEST_ID="fuse-driver-test-$(date +%s)"
    local TEST_FILE="${NAS_MOUNT_POINT}/${TEST_ID}"
    
    # Write to the test file
    echo "${TEST_ID}" > "${TEST_FILE}"
    
    # Check if the file was created in the backing storage
    if [ ! -f "${NAS_STORAGE_PATH}/${TEST_ID}" ]; then
        echo -e "${RED}ERROR: Test file not found in backing storage${NC}"
        echo "This suggests the FUSE driver is not properly intercepting file operations"
        return 1
    fi
    
    # Check if the content matches
    local STORAGE_CONTENT=$(cat "${NAS_STORAGE_PATH}/${TEST_ID}")
    if [ "${STORAGE_CONTENT}" != "${TEST_ID}" ]; then
        echo -e "${RED}ERROR: Test file content doesn't match in backing storage${NC}"
        echo "FUSE mount content: ${TEST_ID}"
        echo "Storage content: ${STORAGE_CONTENT}"
        return 1
    fi
    
    # Clean up the test file
    rm -f "${TEST_FILE}"
    
    echo -e "${GREEN}FUSE driver verification successful${NC}"
    return 0
}

# Begin a test group
begin_test_group() {
    CURRENT_TEST_GROUP="$1"
    TEST_GROUP_FAILED=0
    TEST_GROUP_COUNT=0
    echo -e "\n${YELLOW}=== Test Group: $CURRENT_TEST_GROUP ===${NC}"
}

# End a test group
end_test_group() {
    if [ $TEST_GROUP_FAILED -eq 0 ]; then
        echo -e "${GREEN}All $TEST_GROUP_COUNT tests in group '$CURRENT_TEST_GROUP' passed${NC}"
        return 0
    else
        echo -e "${RED}$TEST_GROUP_FAILED/$TEST_GROUP_COUNT tests in group '$CURRENT_TEST_GROUP' failed${NC}"
        return 1
    fi
}

# Run a test function
run_test() {
    local TEST_FUNC=$1
    local TEST_DESC=$2
    
    TEST_GROUP_COUNT=$((TEST_GROUP_COUNT + 1))
    
    echo -ne "Running test: $TEST_DESC ... "
    
    # Create a temporary directory for the test
    local TEST_DIR=$(setup_test_dir "${TEST_FUNC}")
    
    # Change to the test directory
    local ORIG_DIR=$(pwd)
    cd "$TEST_DIR"
    
    # Run the test function
    $TEST_FUNC
    local RESULT=$?
    
    # Change back to the original directory
    cd "$ORIG_DIR"
    
    # Clean up the test directory
    cleanup_test_dir "$TEST_DIR"
    
    # Print the result
    if [ $RESULT -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        TEST_GROUP_FAILED=$((TEST_GROUP_FAILED + 1))
    fi
    
    return $RESULT
}

# Setup test directory
setup_test_dir() {
    local TEST_NAME=$1
    # Use a temporary directory within the project root instead of NAS_MOUNT_POINT
    local TEST_DIR="${PROJECT_ROOT}/tmp_test_${TEST_NAME}_$(date +%s)"
    mkdir -p "$TEST_DIR"
    echo "$TEST_DIR"
}

# Cleanup test directory
cleanup_test_dir() {
    local TEST_DIR=$1
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

# Assert file exists
assert_file_exists() {
    local FILE_PATH=$1
    if [ ! -f "$FILE_PATH" ]; then
        echo -e "${RED}FAIL: File does not exist: $FILE_PATH${NC}"
        return 1
    fi
    return 0
}

# Assert file content
assert_file_content() {
    local FILE_PATH=$1
    local EXPECTED_CONTENT=$2
    
    local ACTUAL_CONTENT="$(cat "$FILE_PATH")"
    if [ "$ACTUAL_CONTENT" != "$EXPECTED_CONTENT" ]; then
        echo -e "${RED}FAIL: File content mismatch for $FILE_PATH${NC}"
        echo "Expected: $EXPECTED_CONTENT"
        echo "Actual: $ACTUAL_CONTENT"
        return 1
    fi
    return 0
}

# Assert directory exists
assert_dir_exists() {
    local DIR_PATH=$1
    if [ ! -d "$DIR_PATH" ]; then
        echo -e "${RED}FAIL: Directory does not exist: $DIR_PATH${NC}"
        return 1
    fi
    return 0
}

# Assert command succeeds
assert_cmd_succeeds() {
    local CMD=$1
    local MSG=${2:-"Command should succeed: $CMD"}
    
    if ! eval "$CMD"; then
        echo -e "${RED}FAIL: $MSG${NC}"
        return 1
    fi
    return 0
}

# Assert command fails
assert_cmd_fails() {
    local CMD=$1
    local MSG=${2:-"Command should fail: $CMD"}
    
    if eval "$CMD" 2>/dev/null; then
        echo -e "${RED}FAIL: $MSG${NC}"
        return 1
    fi
    return 0
}

# Print test result
print_test_result() {
    local TEST_NAME=$1
    local RESULT=$2
    
    if [ $RESULT -eq 0 ]; then
        echo -e "${GREEN}PASS: $TEST_NAME${NC}"
    else
        echo -e "${RED}FAIL: $TEST_NAME${NC}"
    fi
    return $RESULT
}