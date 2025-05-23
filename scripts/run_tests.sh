#!/bin/bash
# Script to run all tests inside the Docker container

set -e

# Source the central configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/config.sh"

# Check if Docker container is running
if ! docker compose ps | grep -q "fuse-dev.*Up"; then
    echo "Starting Docker container..."
    docker compose up -d
fi

# Ensure the FUSE driver is built
if ! docker compose exec fuse-dev test -f /app/src/fuse-driver/nas-emu-fuse; then
    echo "FUSE driver not found, building first..."
    ${SCRIPT_DIR}/build-fuse.sh
fi

# Check if FUSE is already mounted
if ! docker compose exec fuse-dev mount | grep -q "${NAS_MOUNT_POINT}"; then
    echo "FUSE filesystem not mounted, mounting first..."
    ${SCRIPT_DIR}/run-fuse.sh --config=no_faults.conf
fi

# Run basic functional tests (inside container)
echo "Running basic functional tests..."
BASIC_EXIT_CODE=0
if ! docker compose exec fuse-dev bash -c "cd /app/src/fuse-driver/tests/functional && ./run_all_tests.sh"; then
    echo -e "\033[0;31mBasic functional tests FAILED\033[0m"
    BASIC_EXIT_CODE=1
else
    echo -e "\033[0;32mBasic functional tests PASSED\033[0m"
fi

# Only run advanced tests if basic tests passed
if [ $BASIC_EXIT_CODE -eq 0 ]; then
    # Run advanced tests (corruption tests using framework on host)
    echo ""
    echo "Running corruption tests (advanced framework)..."

    # Save current directory and ensure we're in project root
    ORIGINAL_DIR=$(pwd)
    cd "${PROJECT_ROOT}"

    # Run corruption tests on host with proper project root context
    CORRUPTION_EXIT_CODE=0
    echo "Running corruption basic tests..."
    if bash "./src/fuse-driver/tests/functional/test_corruption_basic.sh"; then
        echo -e "\033[0;32mCorruption basic tests PASSED\033[0m"
    else
        echo -e "\033[0;31mCorruption basic tests FAILED\033[0m"
        CORRUPTION_EXIT_CODE=1
    fi

    echo "Running corruption fault tests..."
    if bash "./src/fuse-driver/tests/functional/test_corruption_faults.sh"; then
        echo -e "\033[0;32mCorruption fault tests PASSED\033[0m"
    else
        echo -e "\033[0;31mCorruption fault tests FAILED\033[0m"
        CORRUPTION_EXIT_CODE=1
    fi

    # Restore original directory
    cd "${ORIGINAL_DIR}"
else
    echo ""
    echo -e "\033[0;33mSkipping advanced tests because basic tests failed\033[0m"
    CORRUPTION_EXIT_CODE=1
fi

# Final summary
echo ""
echo "=================================================="
echo "Test Results Summary:"
if [ $BASIC_EXIT_CODE -eq 0 ]; then
    echo -e "Basic tests: \033[0;32mPASSED\033[0m"
else
    echo -e "Basic tests: \033[0;31mFAILED\033[0m"
fi

if [ $CORRUPTION_EXIT_CODE -eq 0 ]; then
    echo -e "Corruption tests: \033[0;32mPASSED\033[0m"
else
    echo -e "Corruption tests: \033[0;31mFAILED\033[0m"
fi

if [ $BASIC_EXIT_CODE -eq 0 ] && [ $CORRUPTION_EXIT_CODE -eq 0 ]; then
    echo -e "\nOverall result: \033[0;32mALL TESTS PASSED\033[0m"
else
    echo -e "\nOverall result: \033[0;31mSOME TESTS FAILED\033[0m"
fi
echo "=================================================="

echo "All tests completed!"