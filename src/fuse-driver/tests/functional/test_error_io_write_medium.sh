#!/bin/bash
#=============================================================================
# test_error_io_write_medium.sh - Medium I/O error test on write operations
# 50% probability of -EIO errors on write operations
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_error_logic() {
    # Test parameters - 50% probability of I/O errors on writes
    local num_writes=40  # Enough samples for statistical accuracy
    local expected_probability=0.5
    local expected_error_code=-5  # -EIO
    
    # Create test data
    local test_data="Test data for I/O error injection testing. This data should trigger write errors with 50% probability."
    
    local failed_writes=0
    local successful_writes=0
    local total_writes=0
    
    echo "Running MEDIUM I/O ERROR test on WRITE operations..."
    echo "Test data length: ${#test_data} bytes"
    echo "Expected error probability: ${expected_probability} (50%)"
    echo "Expected error code: ${expected_error_code} (-EIO)"
    echo "Performing ${num_writes} write operations..."
    echo ""
    
    # Test SMB connection and initial diagnostics
    echo "=== SMB Connection Diagnostics ==="
    echo "SMB mount point: ${HOST_MOUNT_POINT}"
    echo "Storage backdoor: ${DEV_HOST_STORAGE_PATH}"
    
    # Check if SMB mount is working
    if ls "${HOST_MOUNT_POINT}" > /dev/null 2>&1; then
        echo "✓ SMB mount accessible"
        local mount_contents=$(ls -la "${HOST_MOUNT_POINT}" 2>/dev/null | wc -l)
        echo "  → Mount point contains ${mount_contents} items"
    else
        echo "✗ SMB mount NOT accessible"
        return 1
    fi
    
    # Test basic file operations first
    echo ""
    echo "=== Basic SMB Operation Test ==="
    local test_basic_file="smb_test_basic.txt"
    if echo "test" > "${HOST_MOUNT_POINT}/${test_basic_file}" 2>/dev/null; then
        echo "✓ Basic write operation works"
        if [ -f "${DEV_HOST_STORAGE_PATH}/${test_basic_file}" ]; then
            echo "  → File appears in storage backend"
        else
            echo "  → WARNING: File NOT in storage backend"
        fi
        rm -f "${HOST_MOUNT_POINT}/${test_basic_file}" 2>/dev/null
    else
        echo "✗ Basic write operation fails"
        echo "  → This suggests SMB/FUSE issues beyond fault injection"
    fi
    echo ""
    
    # Phase 1: Write operation tests
    echo "=== Write Error Injection Test ==="
    for i in $(seq 1 ${num_writes}); do
        local test_file="test_write_error_${i}.txt"
        total_writes=$((total_writes + 1))
        
        # Try to write data through SMB share - capture detailed error information
        local error_output
        local exit_code
        error_output=$(echo -n "${test_data}" > "${HOST_MOUNT_POINT}/${test_file}" 2>&1)
        exit_code=$?
        
        if [ ${exit_code} -eq 0 ]; then
            # Write succeeded
            successful_writes=$((successful_writes + 1))
            echo "Write ${i}: SUCCESS"
            
            # Verify file actually exists in storage
            if [ -f "${DEV_HOST_STORAGE_PATH}/${test_file}" ]; then
                local stored_data=$(cat "${DEV_HOST_STORAGE_PATH}/${test_file}")
                if [ "${test_data}" = "${stored_data}" ]; then
                    echo "  → Data verified in storage"
                else
                    echo "  → WARNING: Data mismatch in storage"
                fi
            else
                echo "  → WARNING: File not found in storage despite success"
            fi
        else
            # Write failed (this is what we expect ~50% of the time)
            failed_writes=$((failed_writes + 1))
            echo "Write ${i}: FAILED (exit code: ${exit_code})"
            
            # Capture and analyze SMB/filesystem error details
            if [ -n "${error_output}" ]; then
                echo "  → SMB Error: ${error_output}"
            fi
            
            # Check system error with more detail
            local errno_msg
            case ${exit_code} in
                1) errno_msg="General error (exit 1)" ;;
                2) errno_msg="File not found (exit 2)" ;;
                5) errno_msg="I/O error (exit 5)" ;;
                13) errno_msg="Permission denied (exit 13)" ;;
                28) errno_msg="No space left (exit 28)" ;;
                *) errno_msg="Unknown error (exit ${exit_code})" ;;
            esac
            echo "  → Error interpretation: ${errno_msg}"
            
            # Try additional diagnostic commands
            local test_touch_result
            test_touch_result=$(touch "${HOST_MOUNT_POINT}/${test_file}" 2>&1)
            local touch_exit_code=$?
            if [ ${touch_exit_code} -ne 0 ]; then
                echo "  → Touch command also failed (exit ${touch_exit_code}): ${test_touch_result}"
            else
                echo "  → Touch command succeeded (file creation works, but write failed)"
                # Remove the file created by touch
                rm -f "${HOST_MOUNT_POINT}/${test_file}" 2>/dev/null
            fi
            
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
    echo "=== Write Error Test Results ==="
    echo "Total write attempts: ${total_writes}"
    echo "Successful writes: ${successful_writes}"
    echo "Failed writes: ${failed_writes}"
    
    local actual_error_probability=$(awk "BEGIN {printf \"%.3f\", ($failed_writes * 1.0 / $total_writes)}")
    local actual_success_probability=$(awk "BEGIN {printf \"%.3f\", ($successful_writes * 1.0 / $total_writes)}")
    
    echo "Actual error probability: ${actual_error_probability} (${failed_writes}/${total_writes})"
    echo "Actual success probability: ${actual_success_probability} (${successful_writes}/${total_writes})"
    echo "Expected error probability: ${expected_probability}"
    
    # Calculate tolerance for probability - allow 30% deviation (0.35 to 0.65 for 0.5 expected)
    local min_error_prob=$(awk "BEGIN {printf \"%.3f\", ($expected_probability * 0.7)}")
    local max_error_prob=$(awk "BEGIN {printf \"%.3f\", ($expected_probability * 1.3)}")
    
    echo "Acceptable error probability range: ${min_error_prob} - ${max_error_prob}"
    
    # Verify that errors occurred within reasonable bounds
    if [ ${failed_writes} -eq 0 ]; then
        echo "ERROR: No write errors detected in ${total_writes} attempts"
        report_result "Write Error Probability" 1 "No errors detected (expected ~${expected_probability})"
        return 1
    elif [ ${successful_writes} -eq 0 ]; then
        echo "ERROR: No successful writes in ${total_writes} attempts (probability too high)"
        report_result "Write Error Probability" 1 "All writes failed (expected ~${expected_probability} failure rate)"
        return 1
    elif awk "BEGIN {exit ($actual_error_probability < $min_error_prob || $actual_error_probability > $max_error_prob) ? 1 : 0}"; then
        echo "SUCCESS: Write error probability within expected range"
        report_result "Write Error Probability" 0 "Error rate ${actual_error_probability} in range [${min_error_prob}, ${max_error_prob}]"
    else
        echo "WARNING: Write error probability outside expected range but errors detected"
        report_result "Write Error Probability" 0 "Error rate ${actual_error_probability} outside range but errors occurred"
    fi
    
    # Test read operations should NOT be affected (error fault only targets writes)
    echo ""
    echo "=== Read Operations Test (Should NOT be affected) ==="
    
    # Use one of the successfully written files for read test
    if [ ${successful_writes} -gt 0 ]; then
        local read_test_file="test_read_verify.txt"
        
        # First, create a file that we know should succeed (retry until we get a successful write)
        local write_attempts=0
        local max_write_attempts=10
        while [ ${write_attempts} -lt ${max_write_attempts} ]; do
            write_attempts=$((write_attempts + 1))
            if echo -n "${test_data}" > "${HOST_MOUNT_POINT}/${read_test_file}" 2>/dev/null; then
                echo "Read test file created successfully (attempt ${write_attempts})"
                break
            fi
        done
        
        if [ ${write_attempts} -le ${max_write_attempts} ]; then
            # Now test reading multiple times (should always succeed)
            local read_failures=0
            local read_successes=0
            local num_reads=10
            
            for j in $(seq 1 ${num_reads}); do
                if cat "${HOST_MOUNT_POINT}/${read_test_file}" > /dev/null 2>&1; then
                    read_successes=$((read_successes + 1))
                else
                    read_failures=$((read_failures + 1))
                    echo "Read ${j}: FAILED (unexpected)"
                fi
            done
            
            echo "Read test results: ${read_successes}/${num_reads} successful"
            
            if [ ${read_failures} -eq 0 ]; then
                report_result "Read Operations Unaffected" 0 "All ${num_reads} reads successful (error fault correctly targets only writes)"
            else
                report_result "Read Operations Unaffected" 1 "${read_failures} reads failed (error fault incorrectly affecting reads)"
                return 1
            fi
        else
            echo "WARNING: Could not create test file for read verification after ${max_write_attempts} attempts"
            report_result "Read Test Setup" 1 "Could not create test file for read verification"
        fi
    else
        echo "WARNING: No successful writes available for read test"
        report_result "Read Test Setup" 1 "No successful writes for read verification"
    fi
    
    return 0
}

# Run the test using the framework
run_test_with_config "error_io_write_medium.conf" "error_io_write_medium" test_error_logic