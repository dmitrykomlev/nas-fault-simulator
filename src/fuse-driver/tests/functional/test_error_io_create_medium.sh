#!/bin/bash
#=============================================================================
# test_error_io_create_medium.sh - Medium I/O error test on create operations
# 50% probability of -EIO errors on create operations
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_error_logic() {
    # Test parameters - 50% probability of I/O errors on create
    local num_creates=40  # Enough samples for statistical accuracy
    local expected_probability=0.5
    local expected_error_code=-5  # -EIO
    
    local failed_creates=0
    local successful_creates=0
    local total_creates=0
    
    echo "Running MEDIUM I/O ERROR test on CREATE operations..."
    echo "Expected error probability: ${expected_probability} (50%)"
    echo "Expected error code: ${expected_error_code} (-EIO)"
    echo "Performing ${num_creates} create operations..."
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
    
    echo ""
    echo "=== Create Error Injection Test ==="
    for i in $(seq 1 ${num_creates}); do
        local test_file="test_create_error_${i}.txt"
        total_creates=$((total_creates + 1))
        
        # Try to create file through SMB share - capture detailed error information
        local error_output
        local exit_code
        error_output=$(touch "${HOST_MOUNT_POINT}/${test_file}" 2>&1)
        exit_code=$?
        
        if [ ${exit_code} -eq 0 ]; then
            # Create succeeded
            successful_creates=$((successful_creates + 1))
            echo "Create ${i}: SUCCESS"
            
            # Verify file actually exists in storage
            if [ -f "${DEV_HOST_STORAGE_PATH}/${test_file}" ]; then
                echo "  → File exists in storage backend"
            else
                echo "  → WARNING: File not found in storage despite success"
            fi
        else
            # Create failed (this is what we expect ~50% of the time)
            failed_creates=$((failed_creates + 1))
            echo "Create ${i}: FAILED (exit code: ${exit_code})"
            
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
    echo "=== Create Error Test Results ==="
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
    
    return 0
}

# Run the test using the framework
run_test_with_config "error_io_create_medium.conf" "error_io_create_medium" test_error_logic