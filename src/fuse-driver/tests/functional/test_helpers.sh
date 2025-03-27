#!/bin/bash

# Helper functions for FUSE filesystem tests

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Common test variables
TEST_MOUNT_DIR="/mnt/fs-fault"

# Begin test group
begin_test_group() {
    echo -e "${YELLOW}====== Starting Test Group: $1 ======${NC}"
    echo "Test started at: $(date)"
    echo
}

# End test group
end_test_group() {
    echo
    echo -e "${GREEN}====== Test Group Completed Successfully ======${NC}"
    echo
}

# Assert file exists
assert_file_exists() {
    if [ ! -f "$1" ]; then
        echo -e "${RED}ERROR: File $1 does not exist${NC}"
        exit 1
    fi
}

# Assert directory exists
assert_dir_exists() {
    if [ ! -d "$1" ]; then
        echo -e "${RED}ERROR: Directory $1 does not exist${NC}"
        exit 1
    fi
}

# Assert file content matches expected
assert_file_content() {
    local FILE="$1"
    local EXPECTED="$2"
    local CONTENT=$(cat "$FILE")
    
    if [ "$CONTENT" != "$EXPECTED" ]; then
        echo -e "${RED}ERROR: Content mismatch in $FILE${NC}"
        echo "Expected: $EXPECTED"
        echo "Actual: $CONTENT"
        exit 1
    fi
}

# Assert two values are equal
assert_equals() {
    if [ "$1" != "$2" ]; then
        echo -e "${RED}ERROR: Values not equal${NC}"
        echo "Expected: $2"
        echo "Actual: $1"
        exit 1
    fi
}

# Assert string contains substring
assert_contains() {
    if [[ "$1" != *"$2"* ]]; then
        echo -e "${RED}ERROR: String does not contain expected value${NC}"
        echo "String: $1"
        echo "Expected to contain: $2"
        exit 1
    fi
}

# Assert exit code is as expected
assert_exit_code() {
    local COMMAND="$1"
    local EXPECTED_CODE="$2"
    
    eval "$COMMAND"
    local ACTUAL_CODE=$?
    
    if [ $ACTUAL_CODE -ne $EXPECTED_CODE ]; then
        echo -e "${RED}ERROR: Command '$COMMAND' exited with code $ACTUAL_CODE, expected $EXPECTED_CODE${NC}"
        exit 1
    fi
}

# Run a command and verify it succeeds
assert_command_succeeds() {
    if ! eval "$1"; then
        echo -e "${RED}ERROR: Command failed: $1${NC}"
        exit 1
    fi
}

# Run a command and verify it fails
assert_command_fails() {
    if eval "$1" 2>/dev/null; then
        echo -e "${RED}ERROR: Command succeeded but should have failed: $1${NC}"
        exit 1
    fi
}

# Verify file permissions
assert_file_permissions() {
    local FILE="$1"
    local EXPECTED_PERMS="$2"
    
    local ACTUAL_PERMS=$(stat -c "%a" "$FILE")
    
    if [ "$ACTUAL_PERMS" != "$EXPECTED_PERMS" ]; then
        echo -e "${RED}ERROR: File permissions mismatch for $FILE${NC}"
        echo "Expected: $EXPECTED_PERMS"
        echo "Actual: $ACTUAL_PERMS"
        exit 1
    fi
}

# Create a random test file of specified size (in KB)
create_test_file() {
    local FILE="$1"
    local SIZE_KB="$2"
    
    dd if=/dev/urandom of="$FILE" bs=1024 count="$SIZE_KB" 2>/dev/null
}

# Compare two files and verify they are identical
assert_files_identical() {
    local FILE1="$1"
    local FILE2="$2"
    
    if ! cmp -s "$FILE1" "$FILE2"; then
        echo -e "${RED}ERROR: Files are not identical${NC}"
        echo "File 1: $FILE1"
        echo "File 2: $FILE2"
        exit 1
    fi
}

# Measure and log operation timing
time_operation() {
    local DESC="$1"
    local CMD="$2"
    
    echo "Timing operation: $DESC"
    local START_TIME=$(date +%s)
    eval "$CMD"
    local RESULT=$?
    local END_TIME=$(date +%s)
    local ELAPSED=$((END_TIME - START_TIME))
    
    echo "Operation completed in $ELAPSED seconds"
    return $RESULT
}

# Function to run a test and report status
run_test() {
    local TEST_NAME="$1"
    local TEST_FUNC="$2"
    
    echo -e "${YELLOW}→ Running test: $TEST_NAME${NC}"
    
    # Run test with error capture
    if $TEST_FUNC; then
        echo -e "${GREEN}✓ PASS: $TEST_NAME${NC}"
        return 0
    else
        local EXIT_CODE=$?
        echo -e "${RED}✗ FAIL: $TEST_NAME (code: $EXIT_CODE)${NC}"
        # Show current directory on failure for debugging
        echo -e "${RED}Failed in directory: $(pwd)${NC}"
        return 1
    fi
}

# Create a test environment directory
setup_test_dir() {
    local DIR_NAME="$1"
    local TEST_DIR="$TEST_MOUNT_DIR/$DIR_NAME"
    
    # Output essential diagnostic message to stderr
    echo "Setting up test directory: $TEST_DIR" >&2
    
    # Check if mount point exists - critical check, keep this
    if [ ! -d "$TEST_MOUNT_DIR" ]; then
        echo "ERROR: Mount point $TEST_MOUNT_DIR does not exist!" >&2
        return 1
    fi
    
    # Remove and create directory - no need for messages in normal operation
    rm -rf "$TEST_DIR" 2>/dev/null
    mkdir -p "$TEST_DIR" 2>/dev/null
    
    # Always verify - critical check, keep this
    if [ ! -d "$TEST_DIR" ]; then
        echo "ERROR: Failed to create directory: $TEST_DIR" >&2
        return 1
    fi
    
    # Return only the directory path to stdout
    echo "$TEST_DIR"
}

# Clean up test directory
cleanup_test_dir() {
    local TEST_DIR="$1"
    
    echo "Cleaning up test directory: $TEST_DIR"
    rm -rf "$TEST_DIR" 2>/dev/null
}