#!/bin/bash
# Script to run all functional tests for the FUSE driver

# Source the test helper functions
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/test_helpers.sh"

# Set the exit code variable
EXIT_CODE=0

# SANITY CHECK: Verify the FUSE driver is running properly
echo "=================================================="
echo "FUSE Driver Sanity Check"
echo "=================================================="
if ! verify_fuse_driver; then
    echo -e "${RED}CRITICAL: FUSE driver verification failed${NC}"
    echo "Cannot proceed with tests as the FUSE driver is not functioning correctly."
    echo "Please ensure the FUSE driver is properly mounted and running."
    echo "Try running the './scripts/run-fuse.sh' script first."
    exit 1
fi

# Print test suite header
echo "=================================================="
echo "Running FUSE Driver Functional Tests"
echo "=================================================="
echo "Mount point: ${NAS_MOUNT_POINT}"
echo "Storage path: ${NAS_STORAGE_PATH}"
echo "=================================================="

# Run the basic operations tests
echo "Running basic operations tests..."
if bash "${SCRIPT_DIR}/test_basic_ops.sh"; then
    echo -e "${GREEN}Basic operations tests PASSED${NC}"
else
    echo -e "${RED}Basic operations tests FAILED${NC}"
    EXIT_CODE=1
fi

# Run the large file operations tests
echo "Running large file operations tests..."
if bash "${SCRIPT_DIR}/test_large_file_ops.sh"; then
    echo -e "${GREEN}Large file operations tests PASSED${NC}"
else
    echo -e "${RED}Large file operations tests FAILED${NC}"
    EXIT_CODE=1
fi

# Add additional test suites here as they are created

# Print summary
echo "=================================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}All tests PASSED${NC}"
else
    echo -e "${RED}Some tests FAILED${NC}"
fi
echo "=================================================="

exit $EXIT_CODE