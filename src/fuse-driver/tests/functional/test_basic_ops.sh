#!/bin/bash
# test_basic_ops.sh - Basic filesystem operations tests

# Source the test helper functions
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/test_helpers.sh"

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

# Test file creation and basic read/write
test_file_create_read_write() {
    local TEST_FILE="test_file.txt"
    local TEST_CONTENT="Hello World from FUSE!"
    
    # Create a file with content
    echo "$TEST_CONTENT" > "$TEST_FILE"
    
    # Verify file exists
    assert_file_exists "$TEST_FILE"
    
    # Verify content
    assert_file_content "$TEST_FILE" "$TEST_CONTENT"
    
    # Clean up
    rm -f "$TEST_FILE"
    
    return 0
}

# Test directory creation and listing
test_directory_create_list() {
    local TEST_DIR="test_dir"
    local TEST_FILE="${TEST_DIR}/test_file.txt"
    local TEST_CONTENT="Hello from directory!"
    
    # Create directory
    mkdir -p "$TEST_DIR"
    
    # Verify directory exists
    assert_dir_exists "$TEST_DIR"
    
    # Create a file inside the directory
    echo "$TEST_CONTENT" > "$TEST_FILE"
    
    # Verify file exists
    assert_file_exists "$TEST_FILE"
    
    # Verify content
    assert_file_content "$TEST_FILE" "$TEST_CONTENT"
    
    # Clean up
    rm -rf "$TEST_DIR"
    
    return 0
}

# Test file permissions
test_file_permissions() {
    local TEST_FILE="test_perm_file.txt"
    local TEST_CONTENT="Permission test content"
    
    # Create a file with content
    echo "$TEST_CONTENT" > "$TEST_FILE"
    
    # Check the initial permissions
    echo "Initial file permissions:"
    ls -l "$TEST_FILE"
    
    # Change permissions to read-only
    chmod 400 "$TEST_FILE"
    
    # Verify the permissions were changed
    echo "After chmod 400:"
    ls -l "$TEST_FILE"
    
    # Verify file exists
    assert_file_exists "$TEST_FILE"
    
    # Verify content can be read
    assert_file_content "$TEST_FILE" "$TEST_CONTENT"
    
    # Try to write to the file using cat - this should fail
    echo "Attempting to write to read-only file..."
    if ! bash -c "echo 'New content' > $TEST_FILE" 2>/dev/null; then
        echo "SUCCESS: Could not write to read-only file (as expected)"
    else
        echo "FAIL: Was able to write to read-only file"
        chmod 600 "$TEST_FILE"
        rm -f "$TEST_FILE"
        return 1
    fi
    
    # Verify content hasn't changed
    assert_file_content "$TEST_FILE" "$TEST_CONTENT"
    
    # Clean up (need to make writable first)
    chmod 600 "$TEST_FILE"
    rm -f "$TEST_FILE"
    
    return 0
}

# Test file rename
test_file_rename() {
    local TEST_FILE="test_orig.txt"
    local NEW_NAME="test_renamed.txt"
    local TEST_CONTENT="Rename test content"
    
    # Create a file with content
    echo "$TEST_CONTENT" > "$TEST_FILE"
    
    # Verify file exists
    assert_file_exists "$TEST_FILE"
    
    # Rename the file
    mv "$TEST_FILE" "$NEW_NAME"
    
    # Verify original doesn't exist
    if [ -f "$TEST_FILE" ]; then
        echo "FAIL: Original file still exists after rename: $TEST_FILE"
        return 1
    fi
    
    # Verify new file exists
    assert_file_exists "$NEW_NAME"
    
    # Verify content
    assert_file_content "$NEW_NAME" "$TEST_CONTENT"
    
    # Clean up
    rm -f "$NEW_NAME"
    
    return 0
}

# Test file delete
test_file_delete() {
    local TEST_FILE="test_delete.txt"
    local TEST_CONTENT="Delete test content"
    
    # Create a file with content
    echo "$TEST_CONTENT" > "$TEST_FILE"
    
    # Verify file exists
    assert_file_exists "$TEST_FILE"
    
    # Delete the file
    rm -f "$TEST_FILE"
    
    # Verify file doesn't exist
    if [ -f "$TEST_FILE" ]; then
        echo "FAIL: File still exists after delete: $TEST_FILE"
        return 1
    fi
    
    return 0
}

# Run all tests
run_all_tests() {
    local RESULT=0
    
    begin_test_group "Basic Filesystem Operations"
    
    # Run the tests
    run_test test_file_create_read_write "File creation and read/write"
    run_test test_directory_create_list "Directory creation and listing"
    run_test test_file_permissions "File permissions"
    run_test test_file_rename "File rename"
    run_test test_file_delete "File delete"
    
    # End the test group
    end_test_group
    RESULT=$?
    
    return $RESULT
}

# Run the tests
run_all_tests
exit $?