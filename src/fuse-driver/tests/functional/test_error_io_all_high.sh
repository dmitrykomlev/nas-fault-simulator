#!/bin/bash
#=============================================================================
# test_error_io_all_high.sh - High I/O error test on all operations
# 100% probability of -EIO errors on all filesystem operations
#=============================================================================

# Source the test framework
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/test_framework.sh"

# Test-specific logic function
test_error_logic() {
    # Test parameters - 100% probability of I/O errors on ALL operations
    local expected_probability=1.0
    local expected_error_code=-5  # -EIO
    
    # Create test data
    local test_data="Test data for comprehensive I/O error injection testing on all operations."
    
    echo "Running HIGH I/O ERROR test on ALL operations..."
    echo "Test data length: ${#test_data} bytes"
    echo "Expected error probability: ${expected_probability} (100%)"
    echo "Expected error code: ${expected_error_code} (-EIO)"
    echo "Testing that ALL filesystem operations fail with I/O errors..."
    echo ""
    
    local total_tests=0
    local expected_failures=0
    local actual_failures=0
    
    # Test 1: File creation should fail
    echo "=== Test 1: File Creation (create/open operations) ==="
    total_tests=$((total_tests + 1))
    expected_failures=$((expected_failures + 1))
    
    local create_file="test_create_fail.txt"
    if echo -n "${test_data}" > "${HOST_MOUNT_POINT}/${create_file}" 2>/dev/null; then
        echo "Create operation: UNEXPECTED SUCCESS"
        report_result "Create Operation Error" 1 "Create should have failed but succeeded"
    else
        echo "Create operation: FAILED (expected)"
        actual_failures=$((actual_failures + 1))
        report_result "Create Operation Error" 0 "Create correctly failed with error"
    fi
    
    # Test 2: Directory creation should fail
    echo ""
    echo "=== Test 2: Directory Creation (mkdir operation) ==="
    total_tests=$((total_tests + 1))
    expected_failures=$((expected_failures + 1))
    
    local test_dir="test_mkdir_fail"
    if mkdir "${HOST_MOUNT_POINT}/${test_dir}" 2>/dev/null; then
        echo "Mkdir operation: UNEXPECTED SUCCESS"
        report_result "Mkdir Operation Error" 1 "Mkdir should have failed but succeeded"
    else
        echo "Mkdir operation: FAILED (expected)"
        actual_failures=$((actual_failures + 1))
        report_result "Mkdir Operation Error" 0 "Mkdir correctly failed with error"
    fi
    
    # Test 3: Try to set up a test file directly in storage for read tests
    echo ""
    echo "=== Test 3: Setting up test file for read/stat tests ==="
    local read_test_file="test_read_fail.txt"
    echo -n "${test_data}" > "${DEV_HOST_STORAGE_PATH}/${read_test_file}"
    
    if [ -f "${DEV_HOST_STORAGE_PATH}/${read_test_file}" ]; then
        echo "Test file created in storage (bypassing SMB for setup)"
        
        # Test 3a: File reading should fail
        echo ""
        echo "=== Test 3a: File Reading (read operation) ==="
        total_tests=$((total_tests + 1))
        expected_failures=$((expected_failures + 1))
        
        if cat "${HOST_MOUNT_POINT}/${read_test_file}" > /dev/null 2>&1; then
            echo "Read operation: UNEXPECTED SUCCESS"
            report_result "Read Operation Error" 1 "Read should have failed but succeeded"
        else
            echo "Read operation: FAILED (expected)"
            actual_failures=$((actual_failures + 1))
            report_result "Read Operation Error" 0 "Read correctly failed with error"
        fi
        
        # Test 3b: File stat/getattr should fail
        echo ""
        echo "=== Test 3b: File Stat (getattr operation) ==="
        total_tests=$((total_tests + 1))
        expected_failures=$((expected_failures + 1))
        
        if stat "${HOST_MOUNT_POINT}/${read_test_file}" > /dev/null 2>&1; then
            echo "Stat operation: UNEXPECTED SUCCESS"
            report_result "Stat Operation Error" 1 "Stat should have failed but succeeded"
        else
            echo "Stat operation: FAILED (expected)"
            actual_failures=$((actual_failures + 1))
            report_result "Stat Operation Error" 0 "Stat correctly failed with error"
        fi
        
        # Test 3c: File access check should fail
        echo ""
        echo "=== Test 3c: File Access Check (access operation) ==="
        total_tests=$((total_tests + 1))
        expected_failures=$((expected_failures + 1))
        
        if test -r "${HOST_MOUNT_POINT}/${read_test_file}" 2>/dev/null; then
            echo "Access operation: UNEXPECTED SUCCESS"
            report_result "Access Operation Error" 1 "Access should have failed but succeeded"
        else
            echo "Access operation: FAILED (expected)"
            actual_failures=$((actual_failures + 1))
            report_result "Access Operation Error" 0 "Access correctly failed with error"
        fi
        
    else
        echo "WARNING: Could not create test file in storage for read tests"
        report_result "Test Setup" 1 "Could not create test file for read operations testing"
    fi
    
    # Test 4: Directory listing should fail
    echo ""
    echo "=== Test 4: Directory Listing (readdir operation) ==="
    total_tests=$((total_tests + 1))
    expected_failures=$((expected_failures + 1))
    
    if ls "${HOST_MOUNT_POINT}/" > /dev/null 2>&1; then
        echo "Directory listing: UNEXPECTED SUCCESS"
        report_result "Readdir Operation Error" 1 "Directory listing should have failed but succeeded"
    else
        echo "Directory listing: FAILED (expected)"
        actual_failures=$((actual_failures + 1))
        report_result "Readdir Operation Error" 0 "Directory listing correctly failed with error"
    fi
    
    # Test 5: Test multiple operation attempts to verify consistency
    echo ""
    echo "=== Test 5: Multiple Operation Consistency Check ==="
    echo "Testing that errors are consistent across multiple attempts..."
    
    local consistency_tests=10
    local consistency_failures=0
    
    for i in $(seq 1 ${consistency_tests}); do
        # Try creating different files - all should fail
        local test_file="consistency_test_${i}.txt"
        if echo -n "test" > "${HOST_MOUNT_POINT}/${test_file}" 2>/dev/null; then
            echo "Consistency test ${i}: UNEXPECTED SUCCESS"
        else
            consistency_failures=$((consistency_failures + 1))
        fi
    done
    
    echo "Consistency results: ${consistency_failures}/${consistency_tests} operations failed"
    
    if [ ${consistency_failures} -eq ${consistency_tests} ]; then
        report_result "Error Consistency" 0 "All ${consistency_tests} operations consistently failed (100% error rate)"
    else
        local success_count=$((consistency_tests - consistency_failures))
        report_result "Error Consistency" 1 "${success_count} operations unexpectedly succeeded (should be 100% failure)"
    fi
    
    # Summary
    echo ""
    echo "=== High Error Rate Test Results ==="
    echo "Total operation types tested: ${total_tests}"
    echo "Expected failures: ${expected_failures}"
    echo "Actual failures: ${actual_failures}"
    
    local actual_failure_rate=$(awk "BEGIN {printf \"%.3f\", ($actual_failures * 1.0 / $total_tests)}")
    echo "Actual failure rate: ${actual_failure_rate} (${actual_failures}/${total_tests})"
    echo "Expected failure rate: ${expected_probability} (100%)"
    
    if [ ${actual_failures} -eq ${expected_failures} ]; then
        echo "SUCCESS: All operations failed as expected with 100% error rate"
        report_result "Overall Error Rate" 0 "100% error rate achieved (${actual_failures}/${expected_failures})"
    else
        echo "FAILURE: Not all operations failed as expected"
        report_result "Overall Error Rate" 1 "Error rate ${actual_failure_rate} (expected 1.0)"
        return 1
    fi
    
    return 0
}

# Run the test using the framework
run_test_with_config "error_io_all_high.conf" "error_io_all_high" test_error_logic