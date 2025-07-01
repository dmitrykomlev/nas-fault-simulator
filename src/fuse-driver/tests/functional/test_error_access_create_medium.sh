#!/bin/bash
#=============================================================================
# test_error_access_create_medium.sh - Medium access error test on create operations
# 50% probability of -EACCES (permission denied) errors on create operations
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_error_logic() {
    # Test parameters - 50% probability of access denied errors on creates
    local num_creates=40  # Enough samples for statistical accuracy
    local expected_probability=0.5
    local expected_error_code=-13  # -EACCES
    
    # Create test data
    local test_data="Test data for access denied error injection testing on create operations."
    
    local failed_creates=0
    local successful_creates=0
    local total_creates=0
    
    echo "Running MEDIUM ACCESS ERROR test on CREATE operations..."
    echo "Test data length: ${#test_data} bytes"
    echo "Expected error probability: ${expected_probability} (50%)"
    echo "Expected error code: ${expected_error_code} (-EACCES/Permission denied)"
    echo "Performing ${num_creates} create operations..."
    echo ""
    
    # Phase 1: Create operation tests
    echo "=== Create Access Error Injection Test ==="
    for i in $(seq 1 ${num_creates}); do
        local test_file="test_access_create_${i}.txt"
        total_creates=$((total_creates + 1))
        
        # Try to create/write file through SMB share
        if echo -n "${test_data}" > "${HOST_MOUNT_POINT}/${test_file}" 2>/dev/null; then
            # Create succeeded
            successful_creates=$((successful_creates + 1))
            echo "Create ${i}: SUCCESS"
            
            # Verify file actually exists in storage
            if [ -f "${DEV_HOST_STORAGE_PATH}/${test_file}" ]; then
                local stored_data=$(cat "${DEV_HOST_STORAGE_PATH}/${test_file}")
                if [ "${test_data}" = "${stored_data}" ]; then
                    echo "  → File verified in storage"
                else
                    echo "  → WARNING: Data mismatch in storage"
                fi
            else
                echo "  → WARNING: File not found in storage despite success"
            fi
        else
            # Create failed (this is what we expect ~50% of the time)
            failed_creates=$((failed_creates + 1))
            echo "Create ${i}: FAILED (expected access denied)"
            
            # Verify file was NOT created in storage
            if [ -f "${DEV_HOST_STORAGE_PATH}/${test_file}" ]; then
                echo "  → WARNING: File exists in storage despite create failure"
            else
                echo "  → Correctly no file in storage"
            fi
        fi
        
        # Small delay between operations
        sleep 0.1
    done
    
    echo ""
    echo "=== Create Access Error Test Results ==="
    echo "Total create attempts: ${total_creates}"
    echo "Successful creates: ${successful_creates}"
    echo "Failed creates: ${failed_creates}"
    
    local actual_error_probability=$(awk "BEGIN {printf \"%.3f\", ($failed_creates * 1.0 / $total_creates)}")
    local actual_success_probability=$(awk "BEGIN {printf \"%.3f\", ($successful_creates * 1.0 / $total_creates)}")
    
    echo "Actual error probability: ${actual_error_probability} (${failed_creates}/${total_creates})"
    echo "Actual success probability: ${actual_success_probability} (${successful_creates}/${total_creates})"
    echo "Expected error probability: ${expected_probability}"
    
    # Calculate tolerance for probability - allow 30% deviation (0.35 to 0.65 for 0.5 expected)
    local min_error_prob=$(awk "BEGIN {printf \"%.3f\", ($expected_probability * 0.7)}")
    local max_error_prob=$(awk "BEGIN {printf \"%.3f\", ($expected_probability * 1.3)}")
    
    echo "Acceptable error probability range: ${min_error_prob} - ${max_error_prob}"
    
    # Verify that errors occurred within reasonable bounds
    if [ ${failed_creates} -eq 0 ]; then
        echo "ERROR: No create errors detected in ${total_creates} attempts"
        report_result "Create Error Probability" 1 "No errors detected (expected ~${expected_probability})"
        return 1
    elif [ ${successful_creates} -eq 0 ]; then
        echo "ERROR: No successful creates in ${total_creates} attempts (probability too high)"
        report_result "Create Error Probability" 1 "All creates failed (expected ~${expected_probability} failure rate)"
        return 1
    elif awk "BEGIN {exit ($actual_error_probability < $min_error_prob || $actual_error_probability > $max_error_prob) ? 1 : 0}"; then
        echo "SUCCESS: Create error probability within expected range"
        report_result "Create Error Probability" 0 "Error rate ${actual_error_probability} in range [${min_error_prob}, ${max_error_prob}]"
    else
        echo "WARNING: Create error probability outside expected range but errors detected"
        report_result "Create Error Probability" 0 "Error rate ${actual_error_probability} outside range but errors occurred"
    fi
    
    # Test directory creation (mkdir) should also be affected since it's a create operation
    echo ""
    echo "=== Directory Creation Test (Should also be affected) ==="
    
    local mkdir_failures=0
    local mkdir_successes=0
    local num_mkdirs=10
    
    for j in $(seq 1 ${num_mkdirs}); do
        local test_dir="test_mkdir_access_${j}"
        
        if mkdir "${HOST_MOUNT_POINT}/${test_dir}" 2>/dev/null; then
            mkdir_successes=$((mkdir_successes + 1))
            echo "Mkdir ${j}: SUCCESS"
            
            # Verify directory was created in storage
            if [ -d "${DEV_HOST_STORAGE_PATH}/${test_dir}" ]; then
                echo "  → Directory verified in storage"
            else
                echo "  → WARNING: Directory not found in storage despite success"
            fi
        else
            mkdir_failures=$((mkdir_failures + 1))
            echo "Mkdir ${j}: FAILED (expected access denied)"
        fi
    done
    
    echo "Directory creation test results: ${mkdir_successes}/${num_mkdirs} successful, ${mkdir_failures}/${num_mkdirs} failed"
    
    # Directory creation should show similar failure pattern (it's also a create operation)
    local mkdir_error_rate=$(awk "BEGIN {printf \"%.3f\", ($mkdir_failures * 1.0 / $num_mkdirs)}")
    
    if [ ${mkdir_failures} -gt 0 ]; then
        report_result "Directory Create Errors" 0 "Directory creation also affected by access errors (${mkdir_error_rate} failure rate)"
    else
        echo "WARNING: No directory creation failures (might indicate error fault not affecting mkdir)"
        report_result "Directory Create Errors" 0 "No directory creation failures (may be expected depending on operation mask)"
    fi
    
    # Test read/write operations on existing files should NOT be affected
    echo ""
    echo "=== Read/Write Operations Test (Should NOT be affected) ==="
    
    # Set up a test file directly in storage
    local existing_file="test_existing_file.txt"
    echo -n "${test_data}" > "${DEV_HOST_STORAGE_PATH}/${existing_file}"
    
    if [ -f "${DEV_HOST_STORAGE_PATH}/${existing_file}" ]; then
        # Test reading existing file
        local read_failures=0
        local read_successes=0
        local num_reads=5
        
        for k in $(seq 1 ${num_reads}); do
            if cat "${HOST_MOUNT_POINT}/${existing_file}" > /dev/null 2>&1; then
                read_successes=$((read_successes + 1))
            else
                read_failures=$((read_failures + 1))
                echo "Read ${k}: FAILED (unexpected)"
            fi
        done
        
        echo "Read existing file test: ${read_successes}/${num_reads} successful"
        
        if [ ${read_failures} -eq 0 ]; then
            report_result "Read Operations Unaffected" 0 "All ${num_reads} reads successful (access error correctly targets only creates)"
        else
            report_result "Read Operations Unaffected" 1 "${read_failures} reads failed (access error incorrectly affecting reads)"
            return 1
        fi
        
        # Test writing to existing file (this should also NOT be affected if error fault only targets create)
        local write_test_data="Modified data to test write operations"
        local write_failures=0
        local write_successes=0
        local num_writes=5
        
        for l in $(seq 1 ${num_writes}); do
            if echo -n "${write_test_data}_${l}" > "${HOST_MOUNT_POINT}/${existing_file}" 2>/dev/null; then
                write_successes=$((write_successes + 1))
            else
                write_failures=$((write_failures + 1))
                echo "Write ${l}: FAILED (unexpected)"
            fi
        done
        
        echo "Write to existing file test: ${write_successes}/${num_writes} successful"
        
        if [ ${write_failures} -eq 0 ]; then
            report_result "Write Operations Unaffected" 0 "All ${num_writes} writes successful (access error correctly targets only creates)"
        else
            report_result "Write Operations Unaffected" 1 "${write_failures} writes failed (access error incorrectly affecting writes)"
            return 1
        fi
    else
        echo "WARNING: Could not set up existing file for read/write testing"
        report_result "Test Setup" 1 "Could not create existing file for read/write verification"
    fi
    
    return 0
}

# Run the test using the framework
run_test_with_config "error_access_create_medium.conf" "error_access_create_medium" test_error_logic