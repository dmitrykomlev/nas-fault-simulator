#!/bin/bash
# Script to run all tests - basic tests inside container, advanced tests from host

set -e

# Source the central configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/config.sh"

echo "=================================================="
echo "NAS Fault Simulator - Full Test Suite"
echo "=================================================="

# Step 1: Build FUSE driver once for all tests
echo "Step 1: Building FUSE driver..."
${SCRIPT_DIR}/build-fuse.sh
if [ $? -eq 0 ]; then
    echo -e "\033[0;32mFUSE driver built successfully\033[0m"
else
    echo -e "\033[0;31mFUSE driver build failed - aborting tests\033[0m"
    exit 1
fi

# Step 2: Start container and mount FUSE with no_faults.conf for basic tests
echo "Step 2: Starting container and mounting FUSE for basic tests..."
${SCRIPT_DIR}/run-fuse.sh --config=no_faults.conf

# Step 3: Copy basic test scripts into container and run them
echo "Step 3: Running basic functional tests..."
docker compose exec fuse-dev mkdir -p /tests
docker cp "${PROJECT_ROOT}/src/fuse-driver/tests/functional/run_all_tests.sh" $(docker compose ps -q fuse-dev):/tests/
docker cp "${PROJECT_ROOT}/src/fuse-driver/tests/functional/test_helpers.sh" $(docker compose ps -q fuse-dev):/tests/
docker cp "${PROJECT_ROOT}/src/fuse-driver/tests/functional/test_basic_ops.sh" $(docker compose ps -q fuse-dev):/tests/
docker cp "${PROJECT_ROOT}/src/fuse-driver/tests/functional/test_large_file_ops.sh" $(docker compose ps -q fuse-dev):/tests/

BASIC_EXIT_CODE=0
if ! docker compose exec fuse-dev bash -c "cd /tests && ./run_all_tests.sh"; then
    echo -e "\033[0;31mBasic functional tests FAILED\033[0m"
    BASIC_EXIT_CODE=1
else
    echo -e "\033[0;32mBasic functional tests PASSED\033[0m"
fi

# Step 4: Run advanced tests if basic tests passed
if [ $BASIC_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "Step 4: Running advanced tests (corruption tests with SMB)..."
    
    # Set environment variable to skip build in advanced tests
    export SKIP_FUSE_BUILD=true
    
    # Save current directory and ensure we're in project root
    ORIGINAL_DIR=$(pwd)
    cd "${PROJECT_ROOT}"

    # Run each advanced test (they manage their own container lifecycle)
    ADVANCED_EXIT_CODE=0
    ADVANCED_TESTS=(
        "test_corruption_none.sh"
        "test_corruption_medium.sh" 
        "test_corruption_high.sh"
        "test_corruption_corner_prob.sh"
        "test_corruption_corner_data.sh"
    )
    
    for test in "${ADVANCED_TESTS[@]}"; do
        echo "Running ${test}..."
        if bash "./src/fuse-driver/tests/functional/${test}"; then
            echo -e "\033[0;32m${test} PASSED\033[0m"
        else
            echo -e "\033[0;31m${test} FAILED\033[0m"
            ADVANCED_EXIT_CODE=1
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