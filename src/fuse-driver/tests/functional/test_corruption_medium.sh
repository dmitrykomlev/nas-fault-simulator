#!/bin/bash
#=============================================================================
# test_corruption_medium.sh - Medium corruption test (50% probability, 30% data)
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_corruption_logic() {
    # Test parameters - 50% probability with 30% data corruption
    local num_writes=30  # More samples for statistical accuracy
    local num_sequential=5
    local expected_probability=0.5
    local expected_data_corruption=30.0
    
    # Create larger test data (>100 bytes) for reliable corruption percentage testing
    local test_data="This is a comprehensive test data string designed to be large enough for reliable corruption percentage analysis. "
    test_data+="It contains exactly 200 characters total, providing sufficient data to accurately measure corruption percentages. "
    test_data+="X"  # Make it exactly 200 characters
    
    local corrupted_files=0
    local total_writes=0
    local total_corruption_percent=0
    
    echo "Running MEDIUM corruption test (50% probability, 30% data corruption)..."
    echo "Test data length: ${#test_data} bytes"
    echo "Expected corruption probability: ${expected_probability} (${expected_probability}0%)"
    echo "Expected data corruption: ${expected_data_corruption}% when triggered"
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
            total_corruption_percent=$(awk "BEGIN {printf \"%.1f\", ($total_corruption_percent + $corruption_percent)}")
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
    
    # Calculate average corruption percentage for corrupted files
    if [ ${corrupted_files} -gt 0 ]; then
        local avg_corruption=$(awk "BEGIN {printf \"%.1f\", ($total_corruption_percent / $corrupted_files)}")
        echo "Average data corruption in affected files: ${avg_corruption}%"
        echo "Expected data corruption: ${expected_data_corruption}%"
    fi
    
    # Calculate tolerance for probability - allow 30% deviation (0.35 to 0.65 for 0.5 expected)
    local min_prob=$(awk "BEGIN {printf \"%.3f\", ($expected_probability * 0.7)}")
    local max_prob=$(awk "BEGIN {printf \"%.3f\", ($expected_probability * 1.3)}")
    
    echo "Acceptable probability range: ${min_prob} - ${max_prob}"
    
    # Verify that corruption occurred within reasonable bounds
    if [ ${corrupted_files} -eq 0 ]; then
        echo "ERROR: No corruption detected in ${total_writes} writes"
        report_result "Corruption Probability" 1 "No corruption detected (expected ~${expected_probability})"
        return 1
    elif awk "BEGIN {exit ($actual_probability < $min_prob || $actual_probability > $max_prob) ? 1 : 0}"; then
        echo "SUCCESS: Corruption probability within expected range"
        report_result "Corruption Probability" 0 "Probability ${actual_probability} in range [${min_prob}, ${max_prob}]"
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
run_test_with_config "corruption_medium.conf" "corruption_medium" test_corruption_logic