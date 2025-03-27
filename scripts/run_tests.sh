#!/bin/bash
# /scripts/run_tests.sh
# This script assumes the FUSE driver is already built and running.
# It will build the driver if needed, but won't restart it.

set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Change to the project root directory
cd "$(dirname "$0")/.."

echo -e "${BOLD}${BLUE}====== Running NAS Emulator FUSE Tests ======${NC}"

# Start container if not running
echo -e "${YELLOW}Ensuring Docker container is running...${NC}"
docker-compose up -d fuse-dev

# Build the FUSE driver if needed
echo -e "${YELLOW}Building FUSE driver if needed...${NC}"
./scripts/build-fuse.sh

# Make sure all scripts are executable
echo -e "${YELLOW}Making test scripts executable...${NC}"
docker-compose exec -T fuse-dev bash -c "
    if [ -d /app/src/fuse-driver/tests/functional ]; then
        chmod +x /app/src/fuse-driver/tests/functional/*.sh
    else
        mkdir -p /app/src/fuse-driver/tests/functional
    fi
"

# Check if FUSE is mounted, if not, run it
echo -e "${YELLOW}Checking FUSE filesystem...${NC}"
docker-compose exec -T fuse-dev bash -c "
    if ! mountpoint -q /mnt/fs-fault; then
        echo 'FUSE filesystem is not mounted. Starting it...'
        mkdir -p /mnt/fs-fault
        mkdir -p /tmp/fs_fault_storage
        chmod 777 /tmp/fs_fault_storage
        
        /app/src/fuse-driver/nas-emu-fuse /mnt/fs-fault -o allow_other \
            --storage=/tmp/fs_fault_storage \
            --log=/tmp/fuse_test.log \
            --loglevel=3 > /dev/null 2>&1 &
        
        FUSE_PID=\$!
        echo \"FUSE driver started with PID: \$FUSE_PID\"
        sleep 3
        
        if ! mountpoint -q /mnt/fs-fault; then
            echo 'ERROR: Failed to mount FUSE filesystem!'
            cat /tmp/fuse_test.log
            exit 1
        fi
        
        echo 'FUSE filesystem mounted successfully!'
    else
        echo 'FUSE filesystem is already mounted.'
    fi
"

# Run the tests
echo -e "${YELLOW}Running functional tests...${NC}"
docker-compose exec -T fuse-dev bash -c "
    # Make sure we're starting with a clean state
    cd /app/src/fuse-driver/tests/functional
    
    # Make sure all test scripts are executable
    chmod +x *.sh
    
    # Run the test runner
    ./run_all_tests.sh
"

TEST_RESULT=$?

if [ $TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All tests completed successfully!${NC}"
else
    echo -e "${RED}${BOLD}Some tests failed!${NC}"
fi

exit $TEST_RESULT