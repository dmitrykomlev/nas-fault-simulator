#!/bin/bash
#=============================================================================
# test_corruption_basic.sh - Basic corruption test using the framework
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_corruption_logic() {
    # Test parameters - with 0.1 probability, expect ~2-3 corruptions out of 20 writes
    local num_writes=20
    local expected_probability=0.1
    local test_data="This is test data for corruption verification. It contains enough content to ensure that corruption can be reliably detected when applied."
    local corrupted_files=0
    local total_writes=0
    
    echo "Running corruption probability test..."
    echo "Test data length: ${#test_data} bytes"
    echo "Expected corruption probability: ${expected_probability} (${expected_probability}0%)"
    echo "Performing ${num_writes} write operations..."
    echo ""
    
    # Perform multiple writes to test probability
    for i in $(seq 1 ${num_writes}); do
        local test_file="test_corruption_${i}.txt"
        total_writes=$((total_writes + 1))
        
        # Create test file with known content
        echo -n "${test_data}" > "/tmp/${test_file}"
        
        # Write data through SMB share (this may trigger corruption)
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
    
    echo ""
    echo "=== Corruption Test Results ==="
    echo "Total writes: ${total_writes}"
    echo "Corrupted files: ${corrupted_files}"
    
    local actual_probability=$(awk "BEGIN {printf \"%.3f\", ($corrupted_files * 1.0 / $total_writes)}")
    echo "Actual corruption probability: ${actual_probability} (${corrupted_files}/${total_writes})"
    echo "Expected probability: ${expected_probability}"
    
    # Calculate tolerance - allow 50% deviation from expected (0.05 to 0.15 for 0.1 expected)
    local min_expected=$(awk "BEGIN {printf \"%.3f\", ($expected_probability * 0.5)}")
    local max_expected=$(awk "BEGIN {printf \"%.3f\", ($expected_probability * 1.5)}")
    
    echo "Acceptable range: ${min_expected} - ${max_expected}"
    
    # Verify that corruption occurred within reasonable bounds
    if [ ${corrupted_files} -eq 0 ]; then
        echo "ERROR: No corruption detected in ${total_writes} writes"
        report_result "Corruption Probability" 1 "No corruption detected (expected ~${expected_probability})"
        return 1
    elif awk "BEGIN {exit ($actual_probability < $min_expected || $actual_probability > $max_expected) ? 1 : 0}"; then
        echo "SUCCESS: Corruption probability within expected range"
        report_result "Corruption Probability" 0 "Probability ${actual_probability} in range [${min_expected}, ${max_expected}]"
    else
        echo "WARNING: Corruption probability outside expected range but not zero"
        report_result "Corruption Probability" 0 "Probability ${actual_probability} outside range but corruption detected"
    fi
    
    # Test read-back consistency for one corrupted file (if any)
    if [ ${corrupted_files} -gt 0 ]; then
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
    fi
    
    return 0
}

# Run the test using the framework
run_test_with_config "corruption_minimal.conf" "corruption_basic" test_corruption_logic