#!/bin/bash
# test_large_file_ops.sh - Tests for large file operations

# Source the test helper functions
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/test_helpers.sh"

# File sizes for tests (in MB)
SMALL_FILE_SIZE=1
MEDIUM_FILE_SIZE=5
LARGE_FILE_SIZE=10

# Setup function - run before each test
setup() {
    # Nothing to do here yet
    return 0
}

# Teardown function - run after each test
teardown() {
    # Nothing to do here yet
    return 0
}

# Create a file of specified size with random data
create_test_file() {
    local FILE_PATH=$1
    local SIZE_MB=$2
    
    # Use dd to create a file with random data
    dd if=/dev/urandom of="$FILE_PATH" bs=1M count="$SIZE_MB" status=none
    
    # Return success if file created with correct size
    if [ -f "$FILE_PATH" ] && [ $(stat -c %s "$FILE_PATH") -eq $(($SIZE_MB * 1024 * 1024)) ]; then
        return 0
    else
        return 1
    fi
}

# Test large file read/write
test_large_file_read_write() {
    local TEST_FILE="large_file.bin"
    
    echo "Creating test file of ${LARGE_FILE_SIZE}MB..."
    create_test_file "$TEST_FILE" "$LARGE_FILE_SIZE"
    
    # Verify file exists
    assert_file_exists "$TEST_FILE"
    
    # Verify file size
    local EXPECTED_SIZE=$(($LARGE_FILE_SIZE * 1024 * 1024))
    local ACTUAL_SIZE=$(stat -c %s "$TEST_FILE")
    
    if [ "$ACTUAL_SIZE" -ne "$EXPECTED_SIZE" ]; then
        echo "FAIL: File size mismatch. Expected: $EXPECTED_SIZE, Actual: $ACTUAL_SIZE"
        return 1
    fi
    
    # Read the file to verify it can be read
    echo "Reading test file..."
    local READ_SIZE=$(cat "$TEST_FILE" | wc -c)
    
    if [ "$READ_SIZE" -ne "$EXPECTED_SIZE" ]; then
        echo "FAIL: Read size mismatch. Expected: $EXPECTED_SIZE, Actual: $READ_SIZE"
        return 1
    fi
    
    # Clean up
    rm -f "$TEST_FILE"
    
    return 0
}

# Test multiple file read/write
test_multiple_files() {
    local TEST_FILES=()
    local NUM_FILES=3
    
    echo "Creating $NUM_FILES test files..."
    
    # Create files of different sizes
    TEST_FILES[0]="small_file.bin"
    TEST_FILES[1]="medium_file.bin"
    TEST_FILES[2]="large_file.bin"
    
    create_test_file "${TEST_FILES[0]}" "$SMALL_FILE_SIZE"
    create_test_file "${TEST_FILES[1]}" "$MEDIUM_FILE_SIZE"
    create_test_file "${TEST_FILES[2]}" "$LARGE_FILE_SIZE"
    
    # Verify files exist
    for file in "${TEST_FILES[@]}"; do
        assert_file_exists "$file"
    done
    
    # Verify file sizes
    local EXPECTED_SIZES=($SMALL_FILE_SIZE $MEDIUM_FILE_SIZE $LARGE_FILE_SIZE)
    
    for i in $(seq 0 $(($NUM_FILES - 1))); do
        local EXPECTED_SIZE=$((${EXPECTED_SIZES[$i]} * 1024 * 1024))
        local ACTUAL_SIZE=$(stat -c %s "${TEST_FILES[$i]}")
        
        if [ "$ACTUAL_SIZE" -ne "$EXPECTED_SIZE" ]; then
            echo "FAIL: File size mismatch for ${TEST_FILES[$i]}. Expected: $EXPECTED_SIZE, Actual: $ACTUAL_SIZE"
            return 1
        fi
    done
    
    # Clean up
    for file in "${TEST_FILES[@]}"; do
        rm -f "$file"
    done
    
    return 0
}

# Test file append
test_file_append() {
    local TEST_FILE="append_test.bin"
    local APPEND_SIZE=1  # MB
    
    # Create initial file
    echo "Creating initial test file of ${SMALL_FILE_SIZE}MB..."
    create_test_file "$TEST_FILE" "$SMALL_FILE_SIZE"
    
    # Verify file exists
    assert_file_exists "$TEST_FILE"
    
    # Get initial size
    local INITIAL_SIZE=$(stat -c %s "$TEST_FILE")
    
    # Append data
    echo "Appending ${APPEND_SIZE}MB to test file..."
    dd if=/dev/urandom of="$TEST_FILE" bs=1M count="$APPEND_SIZE" oflag=append conv=notrunc status=none
    
    # Verify new size
    local EXPECTED_SIZE=$(($INITIAL_SIZE + $APPEND_SIZE * 1024 * 1024))
    local ACTUAL_SIZE=$(stat -c %s "$TEST_FILE")
    
    if [ "$ACTUAL_SIZE" -ne "$EXPECTED_SIZE" ]; then
        echo "FAIL: File size mismatch after append. Expected: $EXPECTED_SIZE, Actual: $ACTUAL_SIZE"
        return 1
    fi
    
    # Clean up
    rm -f "$TEST_FILE"
    
    return 0
}

# Run all tests
run_all_tests() {
    local RESULT=0
    
    begin_test_group "Large File Operations"
    
    # Run the tests
    run_test test_large_file_read_write "Large file read/write"
    run_test test_multiple_files "Multiple files of different sizes"
    run_test test_file_append "File append operations"
    
    # End the test group
    end_test_group
    RESULT=$?
    
    return $RESULT
}

# Run the tests
run_all_tests
exit $?