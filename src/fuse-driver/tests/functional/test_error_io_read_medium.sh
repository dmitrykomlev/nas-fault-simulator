#!/bin/bash
#=============================================================================
# test_error_io_read_medium.sh - Medium I/O error test on read operations
# 50% probability of -EIO errors on read operations
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_error_logic() {
    # Test parameters - 50% probability of I/O errors on reads
    local num_reads=40  # Enough samples for statistical accuracy
    local num_test_files=10  # Create multiple files to read from
    local expected_probability=0.5
    local expected_error_code=-5  # -EIO
    
    # Create test data
    local test_data="Test data for I/O error injection testing on read operations. This file should trigger read errors with 50% probability."
    
    local failed_reads=0
    local successful_reads=0
    local total_reads=0
    
    echo "Running MEDIUM I/O ERROR test on READ operations..."
    echo "Test data length: ${#test_data} bytes"
    echo "Expected error probability: ${expected_probability} (50%)"
    echo "Expected error code: ${expected_error_code} (-EIO)"
    echo "Setting up ${num_test_files} test files, then performing ${num_reads} read operations..."
    echo ""
    
    # Phase 1: Set up test files (writes should NOT be affected by read-only error faults)
    echo "=== Setting up test files (writes should succeed) ==="
    local setup_files=0
    for i in $(seq 1 ${num_test_files}); do
        local test_file="test_read_error_${i}.txt"
        
        # Write test data directly to storage (bypass SMB to avoid any write interference)
        echo -n "${test_data}" > "${DEV_HOST_STORAGE_PATH}/${test_file}"
        
        if [ -f "${DEV_HOST_STORAGE_PATH}/${test_file}" ]; then
            setup_files=$((setup_files + 1))
            echo "File ${i}: Created in storage"
        else
            echo "File ${i}: FAILED to create"
        fi
    done
    
    if [ ${setup_files} -eq 0 ]; then
        echo "ERROR: Could not create any test files"
        report_result "Test Setup" 1 "No test files created"
        return 1
    fi
    
    echo "Successfully created ${setup_files} test files for reading"
    
    # Phase 2: Read operation tests
    echo ""
    echo "=== Read Error Injection Test ==="
    for i in $(seq 1 ${num_reads}); do
        # Select a test file to read from (cycle through available files)
        local file_index=$(( ((i - 1) % setup_files) + 1 ))
        local test_file="test_read_error_${file_index}.txt"
        total_reads=$((total_reads + 1))
        
        # Try to read data through SMB share
        local read_data
        if read_data=$(cat "${HOST_MOUNT_POINT}/${test_file}" 2>/dev/null); then
            # Read succeeded
            successful_reads=$((successful_reads + 1))
            echo "Read ${i} (file ${file_index}): SUCCESS"
            
            # Verify data integrity
            if [ "${test_data}" = "${read_data}" ]; then
                echo "  → Data integrity verified"
            else
                echo "  → WARNING: Data corruption detected"
            fi
        else
            # Read failed (this is what we expect ~50% of the time)
            failed_reads=$((failed_reads + 1))
            echo "Read ${i} (file ${file_index}): FAILED (expected error)"
        fi
        
        # Small delay between operations
        sleep 0.1
    done
    
    echo ""
    echo "=== Read Error Test Results ==="
    echo "Total read attempts: ${total_reads}"
    echo "Successful reads: ${successful_reads}"
    echo "Failed reads: ${failed_reads}"
    
    local actual_error_probability=$(awk "BEGIN {printf \"%.3f\", ($failed_reads * 1.0 / $total_reads)}")
    local actual_success_probability=$(awk "BEGIN {printf \"%.3f\", ($successful_reads * 1.0 / $total_reads)}")
    
    echo "Actual error probability: ${actual_error_probability} (${failed_reads}/${total_reads})"
    echo "Actual success probability: ${actual_success_probability} (${successful_reads}/${total_reads})"
    echo "Expected error probability: ${expected_probability}"
    
    # Calculate tolerance for probability - allow 15% deviation (0.425 to 0.575 for 0.5 expected)
    local min_error_prob=$(awk "BEGIN {printf \"%.3f\", ($expected_probability * 0.85)}")
    local max_error_prob=$(awk "BEGIN {printf \"%.3f\", ($expected_probability * 1.15)}")
    
    echo "Acceptable error probability range: ${min_error_prob} - ${max_error_prob}"
    
    # Verify that errors occurred within reasonable bounds
    if [ ${failed_reads} -eq 0 ]; then
        echo "ERROR: No read errors detected in ${total_reads} attempts"
        report_result "Read Error Probability" 1 "No errors detected (expected ~${expected_probability})"
        return 1
    elif [ ${successful_reads} -eq 0 ]; then
        echo "ERROR: No successful reads in ${total_reads} attempts (probability too high)"
        report_result "Read Error Probability" 1 "All reads failed (expected ~${expected_probability} failure rate)"
        return 1
    elif awk "BEGIN {exit ($actual_error_probability < $min_error_prob || $actual_error_probability > $max_error_prob) ? 1 : 0}"; then
        echo "SUCCESS: Read error probability within expected range"
        report_result "Read Error Probability" 0 "Error rate ${actual_error_probability} in range [${min_error_prob}, ${max_error_prob}]"
    else
        echo "ERROR: Read error probability outside expected range"
        report_result "Read Error Probability" 1 "Error rate ${actual_error_probability} outside range [${min_error_prob}, ${max_error_prob}]"
        return 1
    fi
    
    # Test write operations should NOT be affected (error fault only targets reads)
    echo ""
    echo "=== Write Operations Test (Should NOT be affected) ==="
    
    local write_failures=0
    local write_successes=0
    local num_writes=10
    
    for j in $(seq 1 ${num_writes}); do
        local write_test_file="test_write_verify_${j}.txt"
        
        if echo -n "${test_data}" > "${HOST_MOUNT_POINT}/${write_test_file}" 2>/dev/null; then
            write_successes=$((write_successes + 1))
            
            # Verify file was created in storage
            if [ -f "${DEV_HOST_STORAGE_PATH}/${write_test_file}" ]; then
                echo "Write ${j}: SUCCESS (verified in storage)"
            else
                echo "Write ${j}: SUCCESS (but not found in storage - WARNING)"
            fi
        else
            write_failures=$((write_failures + 1))
            echo "Write ${j}: FAILED (unexpected)"
        fi
    done
    
    echo "Write test results: ${write_successes}/${num_writes} successful"
    
    if [ ${write_failures} -eq 0 ]; then
        report_result "Write Operations Unaffected" 0 "All ${num_writes} writes successful (error fault correctly targets only reads)"
    else
        report_result "Write Operations Unaffected" 1 "${write_failures} writes failed (error fault incorrectly affecting writes)"
        return 1
    fi
    
    return 0
}

# Run the test using the framework
run_test_with_config "error_io_read_medium.conf" "error_io_read_medium" test_error_logic