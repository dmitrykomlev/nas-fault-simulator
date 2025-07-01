#!/bin/bash
#=============================================================================
# test_error_nospace_write_high.sh - High no space error test on write operations
# 100% probability of -ENOSPC (no space left) errors on write operations
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_error_logic() {
    # Test parameters - 100% probability of no space errors on writes
    local num_writes=20  # Fewer attempts since we expect 100% failure
    local expected_probability=1.0
    local expected_error_code=-28  # -ENOSPC
    
    # Create test data
    local test_data="Test data for no space error injection testing on write operations. This simulates disk full scenarios."
    
    local failed_writes=0
    local successful_writes=0
    local total_writes=0
    
    echo "Running HIGH NO SPACE ERROR test on WRITE operations..."
    echo "Test data length: ${#test_data} bytes"
    echo "Expected error probability: ${expected_probability} (100%)"
    echo "Expected error code: ${expected_error_code} (-ENOSPC/No space left on device)"
    echo "Performing ${num_writes} write operations..."
    echo ""
    
    # Phase 1: Write operation tests (all should fail with ENOSPC)
    echo "=== Write No Space Error Injection Test ==="
    for i in $(seq 1 ${num_writes}); do
        local test_file="test_nospace_write_${i}.txt"
        total_writes=$((total_writes + 1))
        
        # Try to write data through SMB share
        if echo -n "${test_data}" > "${HOST_MOUNT_POINT}/${test_file}" 2>/dev/null; then
            # Write succeeded (unexpected)
            successful_writes=$((successful_writes + 1))
            echo "Write ${i}: UNEXPECTED SUCCESS"
            
            # Verify file actually exists in storage
            if [ -f "${DEV_HOST_STORAGE_PATH}/${test_file}" ]; then
                local stored_data=$(cat "${DEV_HOST_STORAGE_PATH}/${test_file}")
                if [ "${test_data}" = "${stored_data}" ]; then
                    echo "  → File verified in storage (should not have been created)"
                else
                    echo "  → WARNING: Data mismatch in storage"
                fi
            else
                echo "  → File not found in storage (consistent with expected failure)"
            fi
        else
            # Write failed (this is what we expect 100% of the time)
            failed_writes=$((failed_writes + 1))
            echo "Write ${i}: FAILED (expected no space error)"
            
            # Verify file was NOT created in storage
            if [ -f "${DEV_HOST_STORAGE_PATH}/${test_file}" ]; then
                echo "  → WARNING: File exists in storage despite write failure"
            else
                echo "  → Correctly no file in storage"
            fi
        fi
        
        # Small delay between operations
        sleep 0.1
    done
    
    echo ""
    echo "=== Write No Space Error Test Results ==="
    echo "Total write attempts: ${total_writes}"
    echo "Successful writes: ${successful_writes}"
    echo "Failed writes: ${failed_writes}"
    
    local actual_error_probability=$(awk "BEGIN {printf \"%.3f\", ($failed_writes * 1.0 / $total_writes)}")
    local actual_success_probability=$(awk "BEGIN {printf \"%.3f\", ($successful_writes * 1.0 / $total_writes)}")
    
    echo "Actual error probability: ${actual_error_probability} (${failed_writes}/${total_writes})"
    echo "Actual success probability: ${actual_success_probability} (${successful_writes}/${total_writes})"
    echo "Expected error probability: ${expected_probability}"
    
    # Verify 100% failure rate (no tolerance for this test)
    if [ ${failed_writes} -eq ${total_writes} ]; then
        echo "SUCCESS: All write operations failed as expected (100% error rate)"
        report_result "Write Error Rate" 0 "100% error rate achieved (${failed_writes}/${total_writes})"
    elif [ ${successful_writes} -eq 0 ]; then
        echo "PARTIAL SUCCESS: No successful writes, but not all operations tested"
        report_result "Write Error Rate" 0 "No successful writes (${failed_writes}/${total_writes} failed)"
    else
        echo "FAILURE: Some writes succeeded when all should fail"
        report_result "Write Error Rate" 1 "Error rate ${actual_error_probability} (expected 1.0)"
        return 1
    fi
    
    # Test append operations (should also fail with no space)
    echo ""
    echo "=== Append Operations Test (Should also fail) ==="
    
    # First create a test file directly in storage
    local append_test_file="test_append_nospace.txt"
    echo -n "Initial content" > "${DEV_HOST_STORAGE_PATH}/${append_test_file}"
    
    if [ -f "${DEV_HOST_STORAGE_PATH}/${append_test_file}" ]; then
        local append_failures=0
        local append_successes=0
        local num_appends=5
        
        for j in $(seq 1 ${num_appends}); do
            # Try to append to the existing file
            if echo -n " appended_${j}" >> "${HOST_MOUNT_POINT}/${append_test_file}" 2>/dev/null; then
                append_successes=$((append_successes + 1))
                echo "Append ${j}: UNEXPECTED SUCCESS"
            else
                append_failures=$((append_failures + 1))
                echo "Append ${j}: FAILED (expected no space error)"
            fi
        done
        
        echo "Append test results: ${append_failures}/${num_appends} failed, ${append_successes}/${num_appends} succeeded"
        
        if [ ${append_failures} -eq ${num_appends} ]; then
            report_result "Append Operations" 0 "All append operations failed (no space error correctly affects appends)"
        else
            report_result "Append Operations" 1 "${append_successes} appends succeeded (should all fail with no space)"
        fi
    else
        echo "WARNING: Could not create test file for append testing"
        report_result "Append Test Setup" 1 "Could not create test file for append operations"
    fi
    
    # Test read operations should NOT be affected (error fault only targets writes)
    echo ""
    echo "=== Read Operations Test (Should NOT be affected) ==="
    
    # Set up test files directly in storage for reading
    local read_failures=0
    local read_successes=0
    local num_reads=10
    
    for k in $(seq 1 ${num_reads}); do
        local read_test_file="test_read_verify_${k}.txt"
        echo -n "${test_data}" > "${DEV_HOST_STORAGE_PATH}/${read_test_file}"
        
        if cat "${HOST_MOUNT_POINT}/${read_test_file}" > /dev/null 2>&1; then
            read_successes=$((read_successes + 1))
        else
            read_failures=$((read_failures + 1))
            echo "Read ${k}: FAILED (unexpected)"
        fi
    done
    
    echo "Read test results: ${read_successes}/${num_reads} successful"
    
    if [ ${read_failures} -eq 0 ]; then
        report_result "Read Operations Unaffected" 0 "All ${num_reads} reads successful (no space error correctly targets only writes)"
    else
        report_result "Read Operations Unaffected" 1 "${read_failures} reads failed (no space error incorrectly affecting reads)"
        return 1
    fi
    
    # Test directory operations should NOT be affected (error fault only targets writes)
    echo ""
    echo "=== Directory Operations Test (Should NOT be affected) ==="
    
    # Create some directories directly in storage
    local dir_test_count=3
    local dir_read_failures=0
    local dir_read_successes=0
    
    for l in $(seq 1 ${dir_test_count}); do
        local test_dir="test_dir_${l}"
        mkdir -p "${DEV_HOST_STORAGE_PATH}/${test_dir}"
        
        # Try to list the directory
        if ls "${HOST_MOUNT_POINT}/${test_dir}" > /dev/null 2>&1; then
            dir_read_successes=$((dir_read_successes + 1))
        else
            dir_read_failures=$((dir_read_failures + 1))
            echo "Directory list ${l}: FAILED (unexpected)"
        fi
    done
    
    echo "Directory operations test: ${dir_read_successes}/${dir_test_count} successful"
    
    if [ ${dir_read_failures} -eq 0 ]; then
        report_result "Directory Operations Unaffected" 0 "All ${dir_test_count} directory operations successful (no space error correctly targets only writes)"
    else
        report_result "Directory Operations Unaffected" 1 "${dir_read_failures} directory operations failed (no space error incorrectly affecting directory ops)"
        return 1
    fi
    
    # Test mkdir operations (should NOT be affected since error fault targets only writes, not creates)
    echo ""
    echo "=== Directory Creation Test (Should NOT be affected) ==="
    
    local mkdir_failures=0
    local mkdir_successes=0
    local num_mkdirs=5
    
    for m in $(seq 1 ${num_mkdirs}); do
        local new_dir="test_mkdir_nospace_${m}"
        
        if mkdir "${HOST_MOUNT_POINT}/${new_dir}" 2>/dev/null; then
            mkdir_successes=$((mkdir_successes + 1))
            echo "Mkdir ${m}: SUCCESS (expected - mkdir is create, not write)"
        else
            mkdir_failures=$((mkdir_failures + 1))
            echo "Mkdir ${m}: FAILED (unexpected - should not be affected)"
        fi
    done
    
    echo "Directory creation test: ${mkdir_successes}/${num_mkdirs} successful"
    
    if [ ${mkdir_failures} -eq 0 ]; then
        report_result "Directory Creation Unaffected" 0 "All ${num_mkdirs} mkdir operations successful (no space error correctly targets only writes, not creates)"
    else
        report_result "Directory Creation Unaffected" 1 "${mkdir_failures} mkdir operations failed (no space error incorrectly affecting creates)"
        return 1
    fi
    
    # Summary
    echo ""
    echo "=== No Space Error Test Summary ==="
    echo "Write operations: ${failed_writes}/${total_writes} failed (expected: ${total_writes}/${total_writes})"
    echo "Non-write operations: Should remain unaffected"
    
    if [ ${failed_writes} -eq ${total_writes} ]; then
        echo "SUCCESS: No space error correctly affects only write operations with 100% failure rate"
        return 0
    else
        echo "FAILURE: No space error did not achieve expected 100% write failure rate"
        return 1
    fi
}

# Run the test using the framework
run_test_with_config "error_nospace_write_high.conf" "error_nospace_write_high" test_error_logic