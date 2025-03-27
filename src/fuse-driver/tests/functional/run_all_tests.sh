#!/bin/bash

# Main script to run all functional tests

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR"

# Make all test scripts executable
chmod +x test_*.sh

# Store test results
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_TEST_NAMES=()

echo -e "${BOLD}${BLUE}====== NAS Emulator FUSE Driver Functional Tests ======${NC}"
echo "Started at: $(date)"
echo

# Run each test script
for test_script in test_*.sh; do
    if [ -f "$test_script" ] && [ "$test_script" != "test_helpers.sh" ]; then
        echo -e "${BOLD}${YELLOW}Running test suite: $test_script${NC}"
        
        if ./$test_script; then
            echo -e "${GREEN}✓ Test suite $test_script passed${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}✗ Test suite $test_script FAILED${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            FAILED_TEST_NAMES+=("$test_script")
        fi
        echo
    fi
done

# Print summary
echo -e "${BOLD}${BLUE}====== Test Summary ======${NC}"
echo "Total test suites: $((PASSED_TESTS + FAILED_TESTS))"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed test suites:${NC}"
    for failed in "${FAILED_TEST_NAMES[@]}"; do
        echo -e "  - $failed"
    done
    echo
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo
    echo -e "${GREEN}All tests passed successfully!${NC}"
    exit 0
fi