#!/bin/bash
#=============================================================================
# test_corruption_high.sh - High corruption test (100% probability, 70% data)
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_corruption_logic() {
    # Test parameters - 100% probability with 70% data corruption
    local num_writes=15  # Fewer samples since we expect 100% corruption
    local expected_probability=1.0
    local expected_data_corruption=70.0
    
    # Create larger test data (>100 bytes) for reliable corruption percentage testing
    local test_data="This is a comprehensive test data string designed to be large enough for reliable corruption percentage analysis. "
    test_data+="It contains exactly 200 characters total, providing sufficient data to accurately measure corruption percentages. "
    test_data+="X"  # Make it exactly 200 characters
    
    local corrupted_files=0
    local total_writes=0
    local total_corruption_percent=0
    
    echo "Running HIGH corruption test (100% probability, 70% data corruption)..."
    echo "Test data length: ${#test_data} bytes"
    echo "Expected corruption probability: ${expected_probability} (100%)"
    echo "Expected data corruption: ${expected_data_corruption}% when triggered"
    echo "Performing ${num_writes} writes..."
    echo ""
    
    for i in $(seq 1 ${num_writes}); do
        local test_file="test_high_${i}.txt"
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
        
        # Check if average corruption is close to expected (allow 20% deviation)
        local min_data_corruption=$(awk "BEGIN {printf \"%.1f\", ($expected_data_corruption * 0.8)}")
        local max_data_corruption=$(awk "BEGIN {printf \"%.1f\", ($expected_data_corruption * 1.2)}")
        
        if awk "BEGIN {exit ($avg_corruption >= $min_data_corruption && $avg_corruption <= $max_data_corruption) ? 0 : 1}"; then
            report_result "Data Corruption Percentage" 0 "Average ${avg_corruption}% in range [${min_data_corruption}%, ${max_data_corruption}%]"
        else
            report_result "Data Corruption Percentage" 1 "Average ${avg_corruption}% outside expected range"
        fi
    fi
    
    # For high corruption test, we expect close to 100% corruption probability
    if awk "BEGIN {exit ($actual_probability >= 0.9) ? 0 : 1}"; then
        echo "SUCCESS: High corruption probability achieved"
        report_result "High Corruption Probability" 0 "Probability ${actual_probability} (≥90%)"
    else
        echo "ERROR: Corruption probability too low for high corruption test"
        report_result "High Corruption Probability" 1 "Probability ${actual_probability} (<90%)"
        return 1
    fi
    
    return 0
}

# Run the test using the framework
run_test_with_config "corruption_high.conf" "corruption_high" test_corruption_logic