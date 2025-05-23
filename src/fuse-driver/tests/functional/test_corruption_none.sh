#!/bin/bash
#=============================================================================
# test_corruption_none.sh - No corruption test (0% probability)
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_corruption_logic() {
    # Test parameters - 0% probability should result in NO corruption
    local num_writes=20
    local num_sequential=5
    local expected_probability=0.0
    
    # Create larger test data (>100 bytes) for reliable corruption percentage testing
    local test_data="This is a comprehensive test data string designed to be large enough for reliable corruption percentage analysis. "
    test_data+="It contains exactly 200 characters total, providing sufficient data to accurately measure corruption percentages. "
    test_data+="X"  # Make it exactly 200 characters
    
    local corrupted_files=0
    local total_writes=0
    
    echo "Running NO corruption test (should observe zero corruption)..."
    echo "Test data length: ${#test_data} bytes"
    echo "Expected corruption probability: ${expected_probability} (${expected_probability}0%)"
    echo "Performing ${num_writes} individual writes + ${num_sequential} sequential writes..."
    echo ""
    
    # Phase 1: Individual write tests
    echo "=== Phase 1: Individual Writes ==="
    for i in $(seq 1 ${num_writes}); do
        local test_file="test_individual_${i}.txt"
        total_writes=$((total_writes + 1))
        
        # Create test file with known content
        echo -n "${test_data}" > "/tmp/${test_file}"
        
        # Write data through SMB share
        cp "/tmp/${test_file}" "${HOST_MOUNT_POINT}/${test_file}" 2>/dev/null
        
        # Small delay to ensure write completes
        sleep 0.1
        
        # Check if file exists in storage backdoor
        local storage_file="${DEV_HOST_STORAGE_PATH}/${test_file}"
        if [ ! -f "${storage_file}" ]; then
            echo "WARNING: Test file ${i} not found in storage"
            continue
        fi
        
        # Read stored content and check for corruption
        local stored_data=$(cat "${storage_file}")
        
        if [ "${test_data}" != "${stored_data}" ]; then
            corrupted_files=$((corrupted_files + 1))
            
            # Count corrupted bytes for this file
            local corruption_count=0
            for ((j=0; j<${#test_data} && j<${#stored_data}; j++)); do
                if [ "${test_data:$j:1}" != "${stored_data:$j:1}" ]; then
                    corruption_count=$((corruption_count + 1))
                fi
            done
            
            local corruption_percent=$(awk "BEGIN {printf \"%.1f\", ($corruption_count * 100.0 / ${#test_data})}")
            echo "File ${i}: CORRUPTED (${corruption_count} bytes, ${corruption_percent}%)"
        else
            echo "File ${i}: OK"
        fi
        
        # Cleanup temp file
        rm -f "/tmp/${test_file}"
    done
    
    # Phase 2: Sequential write tests
    echo ""
    echo "=== Phase 2: Sequential Writes ==="
    for i in $(seq 1 ${num_sequential}); do
        local test_file="test_sequential_${i}.txt"
        total_writes=$((total_writes + 1))
        
        # Create test file with known content
        echo -n "${test_data}" > "/tmp/${test_file}"
        
        # Write data through SMB share
        cp "/tmp/${test_file}" "${HOST_MOUNT_POINT}/${test_file}" 2>/dev/null
        
        # Immediately append more data (sequential write pattern)
        echo -n " APPENDED_DATA_${i}" >> "${HOST_MOUNT_POINT}/${test_file}" 2>/dev/null
        
        # Delay to ensure writes complete
        sleep 0.2
        
        # Check stored content
        local storage_file="${DEV_HOST_STORAGE_PATH}/${test_file}"
        if [ ! -f "${storage_file}" ]; then
            echo "WARNING: Sequential test file ${i} not found in storage"
            continue
        fi
        
        local expected_content="${test_data} APPENDED_DATA_${i}"
        local stored_data=$(cat "${storage_file}")
        
        if [ "${expected_content}" != "${stored_data}" ]; then
            corrupted_files=$((corrupted_files + 1))
            echo "Sequential File ${i}: CORRUPTED"
        else
            echo "Sequential File ${i}: OK"
        fi
        
        # Cleanup temp file
        rm -f "/tmp/${test_file}"
    done
    
    echo ""
    echo "=== Corruption Test Results ==="
    echo "Total writes: ${total_writes}"
    echo "Corrupted files: ${corrupted_files}"
    
    local actual_probability=$(awk "BEGIN {printf \"%.3f\", ($corrupted_files * 1.0 / $total_writes)}")
    echo "Actual corruption probability: ${actual_probability} (${corrupted_files}/${total_writes})"
    echo "Expected probability: ${expected_probability}"
    
    # For no-corruption test, we expect exactly zero corruption
    if [ ${corrupted_files} -eq 0 ]; then
        echo "SUCCESS: No corruption detected as expected"
        report_result "No Corruption Verification" 0 "Zero corruption observed (${corrupted_files}/${total_writes})"
    else
        echo "ERROR: Unexpected corruption detected"
        report_result "No Corruption Verification" 1 "Unexpected corruption: ${corrupted_files} files"
        return 1
    fi
    
    # Test read-back consistency
    local test_file="test_readback.txt"
    echo -n "${test_data}" > "/tmp/${test_file}"
    cp "/tmp/${test_file}" "${HOST_MOUNT_POINT}/${test_file}" 2>/dev/null
    sleep 0.2
    
    if [ -f "${HOST_MOUNT_POINT}/${test_file}" ]; then
        local smb_data=$(cat "${HOST_MOUNT_POINT}/${test_file}")
        local storage_data=$(cat "${DEV_HOST_STORAGE_PATH}/${test_file}")
        
        if [ "${smb_data}" = "${storage_data}" ]; then
            report_result "SMB Consistency" 0 "SMB read matches storage"
        else
            report_result "SMB Consistency" 1 "SMB read differs from storage"
            return 1
        fi
    else
        report_result "SMB Read-back" 1 "Cannot read file through SMB"
        return 1
    fi
    
    rm -f "/tmp/${test_file}"
    return 0
}

# Run the test using the framework
run_test_with_config "corruption_none.conf" "corruption_none" test_corruption_logic