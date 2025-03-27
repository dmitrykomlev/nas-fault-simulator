#!/bin/bash

# Test basic filesystem operations

set -e
source "$(dirname "$0")/test_helpers.sh"

TEST_NAME="basic_ops"
TEST_DIR=""

setup() {
    # Create test directory - only capturing the actual path
    TEST_DIR=$(setup_test_dir "$TEST_NAME")
    
    # Check the return code from the last command
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create test directory"
        exit 1
    fi
    
    # Verify the directory was created
    if [ ! -d "$TEST_DIR" ]; then
        echo "Error: Directory does not exist: $TEST_DIR"
        exit 1
    fi
    
    # Change to the directory
    cd "$TEST_DIR" || {
        echo "Error: Failed to change to directory: $TEST_DIR"
        exit 1
    }
}

teardown() {
    cd /
    cleanup_test_dir "$TEST_DIR"
}

# Test file creation and basic read/write
test_file_create_read_write() {
    local TEST_FILE="$TEST_DIR/test_file.txt"
    local TEST_CONTENT="Hello World from FUSE!"
    
    # Create a file with content
    echo "$TEST_CONTENT" > "$TEST_FILE"
    
    # Verify file exists
    assert_file_exists "$TEST_FILE"
    
    # Verify content
    assert_file_content "$TEST_FILE" "$TEST_CONTENT"
    
    # Append content
    echo "Additional line" >> "$TEST_FILE"
    
    # Verify combined content
    assert_contains "$(cat "$TEST_FILE")" "$TEST_CONTENT"
    assert_contains "$(cat "$TEST_FILE")" "Additional line"
    
    return 0
}

# Test directory creation and listing
test_directory_operations() {
    local TEST_SUBDIR="$TEST_DIR/subdir"
    
    # Create directory
    mkdir -p "$TEST_SUBDIR"
    
    # Verify directory exists
    assert_dir_exists "$TEST_SUBDIR"
    
    # Create some files in the directory
    touch "$TEST_SUBDIR/file1.txt"
    touch "$TEST_SUBDIR/file2.txt"
    
    # Verify files exist
    assert_file_exists "$TEST_SUBDIR/file1.txt"
    assert_file_exists "$TEST_SUBDIR/file2.txt"
    
    # Verify directory listing contains our files
    local DIR_LISTING=$(ls -1 "$TEST_SUBDIR")
    assert_contains "$DIR_LISTING" "file1.txt"
    assert_contains "$DIR_LISTING" "file2.txt"
    
    return 0
}

# Test file permissions
test_file_permissions() {
    local TEST_FILE="$TEST_DIR/permissions_test.txt"
    
    # Create file with specific permissions
    touch "$TEST_FILE"
    chmod 640 "$TEST_FILE"
    
    # Verify permissions
    assert_file_permissions "$TEST_FILE" "640"
    
    # Change permissions and verify again
    chmod 600 "$TEST_FILE"
    assert_file_permissions "$TEST_FILE" "600"
    
    return 0
}

# Test file deletion
test_file_deletion() {
    local TEST_FILE="$TEST_DIR/delete_me.txt"
    
    # Create file
    touch "$TEST_FILE"
    assert_file_exists "$TEST_FILE"
    
    # Delete file
    rm "$TEST_FILE"
    
    # Verify file no longer exists
    assert_command_fails "test -f $TEST_FILE"
    
    return 0
}

# Test directory deletion
test_directory_deletion() {
    local TEST_SUBDIR="$TEST_DIR/delete_dir"
    
    # Create directory with files
    mkdir -p "$TEST_SUBDIR"
    touch "$TEST_SUBDIR/file1.txt"
    
    # Verify directory exists
    assert_dir_exists "$TEST_SUBDIR"
    
    # Delete directory (should fail since it's not empty)
    assert_command_fails "rmdir $TEST_SUBDIR"
    
    # Delete file then directory
    rm "$TEST_SUBDIR/file1.txt"
    rmdir "$TEST_SUBDIR"
    
    # Verify directory no longer exists
    assert_command_fails "test -d $TEST_SUBDIR"
    
    return 0
}

# Main test function
run_tests() {
    begin_test_group "Basic Filesystem Operations"
    
    setup
    
    run_test "File Creation and Read/Write" test_file_create_read_write
    run_test "Directory Operations" test_directory_operations
    run_test "File Permissions" test_file_permissions
    run_test "File Deletion" test_file_deletion
    run_test "Directory Deletion" test_directory_deletion
    
    teardown
    
    end_test_group
}

# Run the tests
run_tests