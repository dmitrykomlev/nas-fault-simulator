#!/bin/bash
#=============================================================================
# test_corruption_corner_data.sh - Corner case: 100% probability, 0% data corruption
# Should observe NO corruption (0% data means no bytes actually corrupted)
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_corruption_logic() {
    # Test parameters - 100% probability but 0% data corruption should result in NO corruption
    local num_writes=10
    local expected_probability=1.0
    local expected_data_corruption=0.0
    
    # Create test data
    local test_data="This corner case test verifies that 0% data corruption prevents any actual corruption even with 100% probability. "
    test_data+="The corruption function should be triggered but should not modify any bytes when percentage is zero. "
    
    local corrupted_files=0
    local total_writes=0
    
    echo "Running CORNER CASE test (100% probability, 0% data - should observe NO corruption)..."
    echo "Test data length: ${#test_data} bytes"
    echo "Config: probability=100%, data_corruption=0%"
    echo "Expected result: NO corruption (0% data means no bytes modified)"
    echo ""
    
    for i in $(seq 1 ${num_writes}); do
        local test_file="test_corner_data_${i}.txt"
        total_writes=$((total_writes + 1))
        
        echo -n "${test_data}" > "/tmp/${test_file}"
        cp "/tmp/${test_file}" "${HOST_MOUNT_POINT}/${test_file}" 2>/dev/null
        sleep 0.1
        
        local storage_file="${DEV_HOST_STORAGE_PATH}/${test_file}"
        if [ ! -f "${storage_file}" ]; then
            echo "WARNING: Test file ${i} not found in storage"
            continue
        fi
        
        local stored_data=$(cat "${storage_file}")
        
        if [ "${test_data}" != "${stored_data}" ]; then
            corrupted_files=$((corrupted_files + 1))
            echo "File ${i}: CORRUPTED (UNEXPECTED)"
        else
            echo "File ${i}: OK"
        fi
        
        rm -f "/tmp/${test_file}"
    done
    
    echo ""
    echo "=== Corner Case Test Results ==="
    echo "Total writes: ${total_writes}"
    echo "Corrupted files: ${corrupted_files}"
    echo "Expected: 0 corrupted files (0% data corruption should modify no bytes)"
    
    if [ ${corrupted_files} -eq 0 ]; then
        echo "SUCCESS: Corner case verified - 0% data corruption modifies no bytes"
        report_result "Corner Case (0% data)" 0 "No corruption with 0% data percentage"
    else
        echo "ERROR: Unexpected corruption detected with 0% data corruption"
        report_result "Corner Case (0% data)" 1 "Unexpected corruption: ${corrupted_files} files"
        return 1
    fi
    
    return 0
}

# Run the test using the framework
run_test_with_config "corruption_corner_data.conf" "corruption_corner_data" test_corruption_logic