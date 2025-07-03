#!/bin/bash
# Script to run all tests - basic tests inside container, advanced tests from host

set -e

# Source the central configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/config.sh"

echo "=================================================="
echo "NAS Fault Simulator - Full Test Suite"
echo "=================================================="

# Step 1: Build Docker image once for all tests
echo "Step 1: Building Docker image with FUSE driver..."
${SCRIPT_DIR}/build.sh
if [ $? -eq 0 ]; then
    echo -e "\033[0;32mDocker image built successfully\033[0m"
else
    echo -e "\033[0;31mDocker image build failed - aborting tests\033[0m"
    exit 1
fi

# Step 2: Start container and mount FUSE with no_faults.conf for basic tests
echo "Step 2: Starting container and mounting FUSE for basic tests..."
${SCRIPT_DIR}/run-fuse.sh --config=no_faults.conf

# Step 3: Copy basic test scripts into container and run them
echo "Step 3: Running basic functional tests..."
CONTAINER_NAME="nas-fault-simulator"
docker exec "${CONTAINER_NAME}" mkdir -p /tests
docker cp "${PROJECT_ROOT}/src/fuse-driver/tests/functional/run_all_tests.sh" "${CONTAINER_NAME}:/tests/"
docker cp "${PROJECT_ROOT}/src/fuse-driver/tests/functional/test_helpers.sh" "${CONTAINER_NAME}:/tests/"
docker cp "${PROJECT_ROOT}/src/fuse-driver/tests/functional/test_basic_ops.sh" "${CONTAINER_NAME}:/tests/"
docker cp "${PROJECT_ROOT}/src/fuse-driver/tests/functional/test_large_file_ops.sh" "${CONTAINER_NAME}:/tests/"

BASIC_EXIT_CODE=0
if ! docker exec "${CONTAINER_NAME}" bash -c "cd /tests && ./run_all_tests.sh"; then
    echo -e "\033[0;31mBasic functional tests FAILED\033[0m"
    BASIC_EXIT_CODE=1
else
    echo -e "\033[0;32mBasic functional tests PASSED\033[0m"
fi

# Step 4: Run advanced tests if basic tests passed
if [ $BASIC_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "Step 4: Stopping basic test container and running advanced tests..."
    
    # Stop the basic test container to free up resources
    echo "Stopping basic test container..."
    docker stop "${CONTAINER_NAME}" 2>/dev/null || true
    docker rm "${CONTAINER_NAME}" 2>/dev/null || true
    
    echo "Running advanced tests (corruption & error fault tests with SMB)..."
    
    # Set environment variable to skip build in advanced tests
    export SKIP_BUILD=true
    
    # Default behavior: cleanup on failure to prevent cascade failures
    # Set PRESERVE_ON_FAILURE=true to debug individual test failures
    export PRESERVE_ON_FAILURE=${PRESERVE_ON_FAILURE:-false}
    
    # Save current directory and ensure we're in project root
    ORIGINAL_DIR=$(pwd)
    cd "${PROJECT_ROOT}"

    # Run each advanced test (they manage their own container lifecycle)
    ADVANCED_EXIT_CODE=0
    
    # Corruption fault tests
    CORRUPTION_TESTS=(
        "test_corruption_none.sh"
        "test_corruption_medium.sh" 
        "test_corruption_high.sh"
        "test_corruption_corner_prob.sh"
        "test_corruption_corner_data.sh"
    )
    
    # Error fault tests
    ERROR_TESTS=(
        "test_error_io_write_medium.sh"
        "test_error_io_read_medium.sh"
        "test_error_io_create_medium.sh"
        "test_error_io_create_high.sh"
        "test_error_io_all_high.sh"
        "test_error_access_create_medium.sh"
        "test_error_nospace_write_high.sh"
    )
    
    # Combine all advanced tests
    ADVANCED_TESTS=("${CORRUPTION_TESTS[@]}" "${ERROR_TESTS[@]}")
    
    for test in "${ADVANCED_TESTS[@]}"; do
        echo "Running ${test}..."
        if bash "./src/fuse-driver/tests/functional/${test}"; then
            echo -e "\033[0;32m${test} PASSED\033[0m"
        else
            echo -e "\033[0;31m${test} FAILED\033[0m"
            ADVANCED_EXIT_CODE=1
            
            # If test environment is preserved, stop running subsequent tests
            # to avoid cascade failures due to resource conflicts
            if [ "$PRESERVE_ON_FAILURE" = "true" ]; then
                echo -e "\033[0;33mStopping test execution due to failure with environment preservation enabled\033[0m"
                echo -e "\033[0;33mClean up the failed test environment before running remaining tests\033[0m"
                break
            fi
        fi
        echo ""
    done

    # Restore original directory
    cd "${ORIGINAL_DIR}"
else
    echo ""
    echo -e "\033[0;33mStep 4: Skipping advanced tests because basic tests failed\033[0m"
    ADVANCED_EXIT_CODE=1
fi

# Step 5: Final summary
echo ""
echo "=================================================="
echo "Test Results Summary:"
echo "=================================================="
if [ $BASIC_EXIT_CODE -eq 0 ]; then
    echo -e "Basic tests: \033[0;32mPASSED\033[0m"
else
    echo -e "Basic tests: \033[0;31mFAILED\033[0m"
fi

if [ $ADVANCED_EXIT_CODE -eq 0 ]; then
    echo -e "Advanced tests: \033[0;32mPASSED\033[0m"
else
    echo -e "Advanced tests: \033[0;31mFAILED\033[0m"
fi

if [ $BASIC_EXIT_CODE -eq 0 ] && [ $ADVANCED_EXIT_CODE -eq 0 ]; then
    echo -e "\nOverall result: \033[0;32mALL TESTS PASSED\033[0m"
    exit 0
else
    echo -e "\nOverall result: \033[0;31mSOME TESTS FAILED\033[0m"
    exit 1
fi