#!/bin/bash

# Test operations with larger files

set -e
source "$(dirname "$0")/test_helpers.sh"

TEST_NAME="large_file_ops"
TEST_DIR=""

setup() {
    # Create test directory
    TEST_DIR=$(setup_test_dir "$TEST_NAME")
    
    # Verify the directory was created
    if [ ! -d "$TEST_DIR" ]; then
        echo "Error: Failed to create test directory"
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

# Test large file creation and reading
test_large_file_read_write() {
    local TEST_FILE="$TEST_DIR/large_file.bin"
    local FILE_SIZE_KB=1024  # 1MB file
    
    # Create a large file
    echo "Creating $FILE_SIZE_KB KB test file..."
    create_test_file "$TEST_FILE" "$FILE_SIZE_KB"
    
    # Verify file exists
    assert_file_exists "$TEST_FILE"
    
    # Verify file size
    local FILE_SIZE=$(stat -c "%s" "$TEST_FILE")
    assert_equals "$FILE_SIZE" "$((FILE_SIZE_KB * 1024))"
    
    # Copy file to verify read operations
    local COPY_FILE="$TEST_DIR/large_file_copy.bin"
    cp "$TEST_FILE" "$COPY_FILE"
    
    # Verify files are identical
    assert_files_identical "$TEST_FILE" "$COPY_FILE"
    
    return 0
}

# Test partial reads and writes
test_partial_io() {
    local TEST_FILE="$TEST_DIR/partial_io.bin"
    local FILE_SIZE_KB=512  # 512KB file
    
    # Create test file
    create_test_file "$TEST_FILE" "$FILE_SIZE_KB"
    assert_file_exists "$TEST_FILE"
    
    # Read first 1KB
    local FIRST_KB_FILE="$TEST_DIR/first_kb.bin"
    dd if="$TEST_FILE" of="$FIRST_KB_FILE" bs=1024 count=1 2>/dev/null
    
    # Verify size of extracted portion
    local PART_SIZE=$(stat -c "%s" "$FIRST_KB_FILE")
    assert_equals "$PART_SIZE" "1024"
    
    # Read middle portion (100KB starting at offset 200KB)
    local MIDDLE_PART_FILE="$TEST_DIR/middle_part.bin"
    dd if="$TEST_FILE" of="$MIDDLE_PART_FILE" bs=1024 skip=200 count=100 2>/dev/null
    
    # Verify size of extracted portion
    local MIDDLE_SIZE=$(stat -c "%s" "$MIDDLE_PART_FILE")
    assert_equals "$MIDDLE_SIZE" "$((100 * 1024))"
    
    return 0
}

# Test performance of sequential reads and writes
test_sequential_performance() {
    local TEST_FILE="$TEST_DIR/seq_perf.bin"
    local FILE_SIZE_KB=2048  # 2MB
    
    # Time sequential write
    echo "Testing sequential write performance..."
    time_operation "Sequential Write $FILE_SIZE_KB KB" "dd if=/dev/urandom of='$TEST_FILE' bs=1024 count=$FILE_SIZE_KB 2>/dev/null"
    
    # Time sequential read
    echo "Testing sequential read performance..."
    time_operation "Sequential Read $FILE_SIZE_KB KB" "dd if='$TEST_FILE' of=/dev/null bs=1024 count=$FILE_SIZE_KB 2>/dev/null"
    
    return 0
}

# Test multiple file operations in parallel
test_parallel_operations() {
    echo "Testing parallel file operations..."
    
    # Create several test files in parallel
    for i in {1..5}; do
        create_test_file "$TEST_DIR/parallel_file_$i.bin" 100 &
    done
    
    # Wait for all background processes to complete
    wait
    
    # Verify all files were created correctly
    for i in {1..5}; do
        assert_file_exists "$TEST_DIR/parallel_file_$i.bin"
        local FILE_SIZE=$(stat -c "%s" "$TEST_DIR/parallel_file_$i.bin")
        assert_equals "$FILE_SIZE" "$((100 * 1024))"
    done
    
    return 0
}

# Main test function
run_tests() {
    begin_test_group "Large File Operations"
    
    setup
    
    run_test "Large File Read/Write" test_large_file_read_write
    run_test "Partial I/O Operations" test_partial_io
    run_test "Sequential Performance" test_sequential_performance
    run_test "Parallel Operations" test_parallel_operations
    
    teardown
    
    end_test_group
}

# Run the tests
run_tests