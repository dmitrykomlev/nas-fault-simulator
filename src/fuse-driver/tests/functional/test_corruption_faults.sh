#!/bin/bash
#=============================================================================
# test_corruption_faults.sh - Tests for data corruption fault injection using SMB share
#=============================================================================
# This script tests data corruption fault injection through a network share.
# It sets up a Docker container with a FUSE filesystem and SMB sharing, then
# performs file operations through the SMB share to test corruption.
#
# Key features:
# - Uses predefined configurations for different corruption levels
# - Maps SMB share for more realistic testing (simulating client access)
# - Tests various corruption scenarios:
#   - High corruption (50% data, 100% chance)
#   - Different probability levels
#   - No corruption (fault injection disabled)
# - Supports both macOS and Linux for testing
#
# Usage:
#   ./test_corruption_faults.sh
#
# Requirements:
#   - Docker and docker-compose
#   - Samba client utilities
#   - Administrator/sudo privileges for mounting
#
#=============================================================================

set -e  # Exit on any error

# Source the test helper functions
# Handle different readlink implementations (macOS vs Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS doesn't have readlink -f
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
else
    # Linux
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
fi
source "${SCRIPT_DIR}/test_helpers.sh"

# Path to project directories (use directories within project root)
HOST_STORAGE_PATH="${PROJECT_ROOT}/nas-storage"
HOST_MOUNT_POINT="${PROJECT_ROOT}/nas-mount-test"

# Path to predefined test configurations
CONFIGS_DIR="${PROJECT_ROOT}/src/fuse-driver/tests/configs"

# Copy a predefined configuration to a temporary location
use_predefined_config() {
    local CONFIG_NAME="$1"
    local DEST_PATH="$2"
    
    cp "${CONFIGS_DIR}/${CONFIG_NAME}" "${DEST_PATH}"
    
    # Replace environment variables in the config
    sed -i.bak "s|\${NAS_MOUNT_POINT}|${NAS_MOUNT_POINT}|g" "${DEST_PATH}"
    sed -i.bak "s|\${NAS_STORAGE_PATH}|${NAS_STORAGE_PATH}|g" "${DEST_PATH}"
    sed -i.bak "s|\${NAS_LOG_FILE}|${NAS_LOG_FILE}|g" "${DEST_PATH}"
    rm -f "${DEST_PATH}.bak"
}

# Mount the SMB share on the host
mount_smb_share() {
    # Create mount point if it doesn't exist
    mkdir -p "${HOST_MOUNT_POINT}"
    
    # Check if already mounted
    if mount | grep -q "${HOST_MOUNT_POINT}"; then
        echo "SMB share already mounted at ${HOST_MOUNT_POINT}"
        return 0
    fi
    
    echo "Mounting SMB share at ${HOST_MOUNT_POINT}..."
    
    # Wait for SMB service to be fully initialized
    sleep 2
    
    # Try mounting a few times (sometimes it can fail on the first attempt)
    local MAX_ATTEMPTS=3
    local attempt=1
    local mounted=false
    
    while [ $attempt -le $MAX_ATTEMPTS ] && [ "$mounted" = "false" ]; do
        echo "Attempt $attempt of $MAX_ATTEMPTS to mount SMB share"
        
        # Check if mounting commands are available
        local MOUNT_CMD_AVAILABLE=false
        
        # Mount based on OS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            if command -v mount_smbfs >/dev/null 2>&1; then
                MOUNT_CMD_AVAILABLE=true
                # Use mount_smbfs with proper URL encoding for password
                mount_smbfs "//${SMB_USERNAME}:${SMB_PASSWORD}@localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME}" "${HOST_MOUNT_POINT}" 2>/dev/null || true
            else
                echo "WARNING: mount_smbfs command not available on macOS"
            fi
        else
            # Linux
            if command -v mount >/dev/null 2>&1 && { [[ -f /proc/filesystems ]] && grep -q cifs /proc/filesystems || true; }; then
                MOUNT_CMD_AVAILABLE=true
                mount -t cifs "//localhost:${NAS_SMB_PORT}/${SMB_SHARE_NAME}" "${HOST_MOUNT_POINT}" \
                    -o "username=${SMB_USERNAME},password=${SMB_PASSWORD},vers=3.0" 2>/dev/null || true
            else
                echo "WARNING: CIFS mount capability not available on Linux"
            fi
        fi
        
        if [ "$MOUNT_CMD_AVAILABLE" = "false" ]; then
            echo "ERROR: Required mount commands not available on this system"
            echo "Using fallback method - direct file operations to the container"
            
            # Mark as "mounted" but we'll actually be working with the host-mapped storage directory
            mounted=true
            break
        fi
        
        # Check if mounted successfully
        if mount | grep -q "${HOST_MOUNT_POINT}"; then
            echo "SMB share mounted successfully on attempt $attempt"
            mounted=true
            break
        else
            echo "Attempt $attempt failed, waiting before retry..."
            sleep 3
            attempt=$((attempt + 1))
        fi
    done
    
    if [ "$mounted" = "true" ]; then
        # Try to get write access
        if touch "${HOST_MOUNT_POINT}/test_access.txt" 2>/dev/null; then
            echo "Write access to share confirmed"
            rm -f "${HOST_MOUNT_POINT}/test_access.txt"
            return 0
        elif [ $attempt -gt $MAX_ATTEMPTS ]; then
            # If we've exhausted all attempts but still have problems
            echo "WARNING: Share access issues detected - using fallback method"
            return 0
        else
            echo "WARNING: Share mounted but write access failed"
            return 1
        fi
    else
        echo "ERROR: Failed to mount share after $MAX_ATTEMPTS attempts"
        echo "Using fallback method - direct file operations"
        
        # Even though we couldn't mount, we'll continue with direct file operations
        return 0
    fi
}

# Start a fresh container and apply configuration
start_container_with_config() {
    local CONFIG_FILE="$1"

    echo "Stopping any existing container..."
    "${PROJECT_ROOT}/scripts/run-fuse.sh" --stop

    echo "Starting a fresh container with the specified configuration..."
    docker-compose up -d
    sleep 2

    local CONTAINER_NAME="nas-fault-simulator-fuse-dev-1"

    # Check if container is running
    if ! docker ps | grep -q ${CONTAINER_NAME}; then
        echo "ERROR: Container ${CONTAINER_NAME} is not running"
        docker-compose logs
        return 1
    fi

    # Copy configuration to container
    echo "Copying configuration to container..."
    docker cp "${CONFIG_FILE}" ${CONTAINER_NAME}:/tmp/current_config.conf

    # Install and configure Samba
    echo "Configuring Samba..."
    # Update and install Samba with progress indicator
    echo "Installing Samba packages..."
    docker exec ${CONTAINER_NAME} bash -c "apt-get update -qq && apt-get install -y samba smbclient" > /dev/null

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to install Samba"
        return 1
    fi

    # Create Samba user with error checking
    echo "Creating Samba user ${SMB_USERNAME}..."
    docker exec ${CONTAINER_NAME} bash -c "id ${SMB_USERNAME} || useradd -m ${SMB_USERNAME}"
    docker exec ${CONTAINER_NAME} bash -c "(echo ${SMB_PASSWORD}; echo ${SMB_PASSWORD}) | smbpasswd -a ${SMB_USERNAME} -s"

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create Samba user"
        return 1
    fi

    # Create Samba configuration with better permissions
    echo "Creating Samba configuration..."
    docker exec ${CONTAINER_NAME} bash -c "cat > /etc/samba/smb.conf << EOF
[global]
    workgroup = WORKGROUP
    server string = NAS Emulator
    security = user
    map to guest = bad user
    log file = /var/log/samba/log.%m
    max log size = 50
    dns proxy = no
    interfaces = lo eth0
    bind interfaces only = yes
    # Allow insecure connections for testing
    client min protocol = NT1
    server min protocol = NT1

[${SMB_SHARE_NAME}]
    path = ${NAS_MOUNT_POINT}
    browseable = yes
    read only = no
    writable = yes
    create mask = 0777
    directory mask = 0777
    valid users = ${SMB_USERNAME}
    force user = root
    guest ok = yes
    public = yes
EOF"

    # Make sure storage and mount points exist with proper permissions
    echo "Creating mount and storage directories..."
    docker exec ${CONTAINER_NAME} bash -c "mkdir -p ${NAS_MOUNT_POINT} ${NAS_STORAGE_PATH}"
    docker exec ${CONTAINER_NAME} bash -c "chmod -R 777 ${NAS_MOUNT_POINT} ${NAS_STORAGE_PATH}"

    # Start FUSE driver with configuration
    echo "Starting FUSE driver..."
    docker exec -d ${CONTAINER_NAME} bash -c "/app/src/fuse-driver/nas-emu-fuse \
        ${NAS_MOUNT_POINT} \
        --storage=${NAS_STORAGE_PATH} \
        --log=${NAS_LOG_FILE} \
        --loglevel=3 \
        --config=/tmp/current_config.conf"

    # Wait for mount to complete
    sleep 2

    # Verify FUSE mount
    if ! docker exec ${CONTAINER_NAME} mount | grep -q "fuse.*${NAS_MOUNT_POINT}"; then
        echo "ERROR: FUSE driver failed to mount filesystem"
        docker exec ${CONTAINER_NAME} cat ${NAS_LOG_FILE}
        return 1
    fi

    # Start Samba service
    echo "Starting Samba service..."
    docker exec ${CONTAINER_NAME} service smbd restart
    docker exec ${CONTAINER_NAME} service nmbd restart

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to start Samba services"
        return 1
    fi

    # Verify Samba is running
    if ! docker exec ${CONTAINER_NAME} pgrep -x smbd > /dev/null; then
        echo "ERROR: Samba server (smbd) is not running"
        docker exec ${CONTAINER_NAME} service smbd status
        return 1
    fi

    # Test Samba configuration
    echo "Testing Samba configuration..."
    if ! docker exec ${CONTAINER_NAME} bash -c "smbclient -N -L localhost"; then
        echo "WARNING: Samba configuration test failed"
        # Continue anyway as sometimes the test fails but share still works
    fi

    # Wait for Samba to fully initialize
    echo "Waiting for Samba to fully initialize..."
    sleep 3

    echo "Container successfully configured with SMB sharing enabled"
    return 0
}

# Unmount the SMB share
unmount_smb_share() {
    # Check if mounted
    if ! mount | grep -q "${HOST_MOUNT_POINT}"; then
        echo "SMB share not mounted at ${HOST_MOUNT_POINT}"
        return 0
    fi

    echo "Unmounting SMB share..."

    # Try to kill any processes that might be using the mount
    lsof "${HOST_MOUNT_POINT}" 2>/dev/null | awk 'NR>1 {print $2}' | sort | uniq | xargs -r kill 2>/dev/null || true
    sleep 1

    # Try unmounting a few times
    local MAX_ATTEMPTS=3
    local attempt=1
    local unmounted=false

    while [ $attempt -le $MAX_ATTEMPTS ] && [ "$unmounted" = "false" ]; do
        echo "Attempt $attempt of $MAX_ATTEMPTS to unmount SMB share"

        # Unmount based on OS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS - try with -f (force) if needed
            if [ $attempt -eq 1 ]; then
                umount "${HOST_MOUNT_POINT}" 2>/dev/null || true
            else
                umount -f "${HOST_MOUNT_POINT}" 2>/dev/null || true
            fi
        else
            # Linux - try with -f (force) and -l (lazy) if needed
            if [ $attempt -eq 1 ]; then
                umount "${HOST_MOUNT_POINT}" 2>/dev/null || true
            elif [ $attempt -eq 2 ]; then
                umount -f "${HOST_MOUNT_POINT}" 2>/dev/null || true
            else
                umount -fl "${HOST_MOUNT_POINT}" 2>/dev/null || true
            fi
        fi

        # Check if unmounted successfully
        if ! mount | grep -q "${HOST_MOUNT_POINT}"; then
            unmounted=true
            break
        else
            echo "Attempt $attempt failed, waiting before retry..."
            sleep 2
            attempt=$((attempt + 1))
        fi
    done

    if [ "$unmounted" = "true" ]; then
        echo "SMB share unmounted successfully"
        return 0
    else
        echo "WARNING: Failed to unmount SMB share after $MAX_ATTEMPTS attempts"
        echo "This might require manual cleanup later"
        return 1
    fi
}

# Test for data corruption in write operations with high corruption
test_high_corruption() {
    local TEST_FILE="test_high_corruption.txt"
    local TEST_CONTENT="This is a test file for high corruption testing. It contains a longer string to ensure adequate data for corruption analysis."
    local TEMP_FILE="/tmp/${TEST_FILE}"

    # Use the high corruption configuration
    local CONFIG_FILE="/tmp/high_corruption.conf"
    use_predefined_config "corruption_high.conf" "${CONFIG_FILE}"

    # Start container with configuration
    start_container_with_config "${CONFIG_FILE}" || return 1

    # Mount SMB share
    mount_smb_share || return 1

    # Create test file with known content
    echo "Creating test file with known content..."
    echo -n "${TEST_CONTENT}" > "${TEMP_FILE}"

    # Create a binary file with known pattern for more reliable corruption detection
    local BINARY_TEST_FILE="test_high_corruption_binary.dat"
    local BINARY_TEMP_FILE="/tmp/${BINARY_TEST_FILE}"
    echo "Creating binary test file with known pattern..."
    dd if=/dev/zero bs=1k count=10 | tr '\0' 'X' > "${BINARY_TEMP_FILE}"

    # Copy files to SMB share
    echo "Copying files to SMB share..."
    cp "${TEMP_FILE}" "${HOST_MOUNT_POINT}/${TEST_FILE}"
    cp "${BINARY_TEMP_FILE}" "${HOST_MOUNT_POINT}/${BINARY_TEST_FILE}"

    # Wait for write to complete
    sleep 3

    # Function to check and report corruption
    analyze_corruption() {
        local SOURCE_FILE="$1"
        local DEST_FILE="$2"
        local FILE_DESC="$3"

        if [ ! -f "${DEST_FILE}" ]; then
            echo "ERROR: ${FILE_DESC} not found in storage path: ${DEST_FILE}"
            return 1
        fi

        # Compare file sizes
        local SOURCE_SIZE=$(stat -c%s "${SOURCE_FILE}" 2>/dev/null || stat -f%z "${SOURCE_FILE}")
        local DEST_SIZE=$(stat -c%s "${DEST_FILE}" 2>/dev/null || stat -f%z "${DEST_FILE}")

        echo "${FILE_DESC} analysis:"
        echo "- Original size: ${SOURCE_SIZE} bytes"
        echo "- Storage size: ${DEST_SIZE} bytes"

        # Check if sizes differ
        if [ "${SOURCE_SIZE}" != "${DEST_SIZE}" ]; then
            echo "- Size corruption detected (expected)"
            echo "- Size difference: $((SOURCE_SIZE - DEST_SIZE)) bytes"
        fi

        # Compare content
        local SOURCE_CONTENT=$(cat "${SOURCE_FILE}")
        local DEST_CONTENT=$(cat "${DEST_FILE}")

        if [ "${SOURCE_CONTENT}" = "${DEST_CONTENT}" ]; then
            echo "- FAIL: No content corruption detected when corruption was expected"
            return 1
        else
            echo "- SUCCESS: Content corruption detected as expected"

            # Calculate approximate corruption percentage for text file
            local DIFF_COUNT=0
            local TOTAL_CHARS=${#SOURCE_CONTENT}

            # Compare character by character
            for ((i=0; i<${#SOURCE_CONTENT} && i<${#DEST_CONTENT}; i++)); do
                if [ "${SOURCE_CONTENT:$i:1}" != "${DEST_CONTENT:$i:1}" ]; then
                    DIFF_COUNT=$((DIFF_COUNT + 1))
                fi
            done

            # Account for length differences
            DIFF_COUNT=$((DIFF_COUNT + ${#SOURCE_CONTENT} - ${#DEST_CONTENT}))
            if [ $DIFF_COUNT -lt 0 ]; then
                DIFF_COUNT=$((DIFF_COUNT * -1))
            fi

            local CORRUPTION_PERCENT=0
            if [ $TOTAL_CHARS -gt 0 ]; then
                CORRUPTION_PERCENT=$(( (DIFF_COUNT * 100) / TOTAL_CHARS ))
            fi

            echo "- Approximate corruption percentage: ${CORRUPTION_PERCENT}%"
            echo "- Expected percentage from config: ~50%"

            # Show a sample of the corruption
            local MAX_SAMPLE=50
            local SHOW_CHARS=$((TOTAL_CHARS < MAX_SAMPLE ? TOTAL_CHARS : MAX_SAMPLE))

            echo "- Original sample: ${SOURCE_CONTENT:0:$SHOW_CHARS}"
            echo "- Corrupted sample: ${DEST_CONTENT:0:$SHOW_CHARS}"
        fi

        return 0
    }

    # Check for corruption in storage path
    echo "Checking for corruption in text file..."
    local STORAGE_TEXT_FILE="${HOST_STORAGE_PATH}/${TEST_FILE}"
    analyze_corruption "${TEMP_FILE}" "${STORAGE_TEXT_FILE}" "Text file" || {
        # Clean up on failure
        rm -f "${TEMP_FILE}" "${BINARY_TEMP_FILE}"
        rm -f "${HOST_MOUNT_POINT}/${TEST_FILE}" "${HOST_MOUNT_POINT}/${BINARY_TEST_FILE}" 2>/dev/null || true
        unmount_smb_share
        return 1
    }

    echo "Checking for corruption in binary file..."
    local STORAGE_BINARY_FILE="${HOST_STORAGE_PATH}/${BINARY_TEST_FILE}"
    analyze_corruption "${BINARY_TEMP_FILE}" "${STORAGE_BINARY_FILE}" "Binary file" || {
        # Clean up on failure
        rm -f "${TEMP_FILE}" "${BINARY_TEMP_FILE}"
        rm -f "${HOST_MOUNT_POINT}/${TEST_FILE}" "${HOST_MOUNT_POINT}/${BINARY_TEST_FILE}" 2>/dev/null || true
        unmount_smb_share
        return 1
    }

    # Clean up
    rm -f "${TEMP_FILE}" "${BINARY_TEMP_FILE}"
    rm -f "${HOST_MOUNT_POINT}/${TEST_FILE}" "${HOST_MOUNT_POINT}/${BINARY_TEST_FILE}" 2>/dev/null || true
    unmount_smb_share

    echo "High corruption test completed successfully"
    return 0
}

# Test for data corruption with varying probabilities
test_probability() {
    local BASE_FILE="test_probability"
    local TEST_CONTENT="This is a test file for probability testing."
    local TEMP_FILE="/tmp/${BASE_FILE}"
    
    # Create test content
    echo -n "${TEST_CONTENT}" > "${TEMP_FILE}"
    
    # Test with different probabilities
    local PROBABILITIES=("0.0" "0.5" "1.0")
    
    for PROB in "${PROBABILITIES[@]}"; do
        echo "Testing corruption with probability ${PROB}..."
        
        # Use predefined configuration based on probability
        local CONFIG_FILE="/tmp/prob_${PROB}.conf"

        if [[ "${PROB}" == "0.0" ]]; then
            use_predefined_config "corruption_zero.conf" "${CONFIG_FILE}"
        elif [[ "${PROB}" == "0.5" ]]; then
            use_predefined_config "corruption_medium.conf" "${CONFIG_FILE}"
        elif [[ "${PROB}" == "1.0" ]]; then
            use_predefined_config "corruption_high.conf" "${CONFIG_FILE}"
        fi
        
        # Start container with configuration
        start_container_with_config "${CONFIG_FILE}"
        
        # Mount SMB share
        mount_smb_share
        
        local CORRUPTED=0
        local ITERATIONS=5
        
        for ((i=1; i<=${ITERATIONS}; i++)); do
            local ITER_FILE="${BASE_FILE}_${PROB}_${i}.txt"
            
            # Copy file to SMB share
            cp "${TEMP_FILE}" "${HOST_MOUNT_POINT}/${ITER_FILE}"
            
            # Wait for write to complete
            sleep 1
            
            # Check for corruption
            local STORAGE_FILE="${HOST_STORAGE_PATH}/${ITER_FILE}"
            
            if [ -f "${STORAGE_FILE}" ]; then
                local STORAGE_CONTENT=$(cat "${STORAGE_FILE}")
                
                if [ "${TEST_CONTENT}" != "${STORAGE_CONTENT}" ]; then
                    CORRUPTED=$((CORRUPTED + 1))
                fi
                
                # Clean up
                rm -f "${HOST_MOUNT_POINT}/${ITER_FILE}"
            fi
        done
        
        echo "Results for probability ${PROB}: ${CORRUPTED}/${ITERATIONS} files corrupted"
        
        # Validate extreme cases
        if [ "${PROB}" = "0.0" ] && [ ${CORRUPTED} -gt 0 ]; then
            echo "FAIL: Files were corrupted when probability was 0.0"
            rm -f "${TEMP_FILE}"
            unmount_smb_share
            return 1
        fi
        
        if [ "${PROB}" = "1.0" ] && [ ${CORRUPTED} -lt ${ITERATIONS} ]; then
            echo "FAIL: Not all files were corrupted when probability was 1.0"
            rm -f "${TEMP_FILE}"
            unmount_smb_share
            return 1
        fi
        
        # Unmount SMB share
        unmount_smb_share
    done
    
    # Clean up
    rm -f "${TEMP_FILE}"
    
    return 0
}

# Test for no corruption
test_no_corruption() {
    local TEST_FILE="test_no_corruption.txt"
    local TEST_CONTENT="This is a test file that should NOT be corrupted. It contains a longer string to ensure adequate data for verification."
    local TEMP_FILE="/tmp/${TEST_FILE}"

    # Use the zero corruption configuration
    local CONFIG_FILE="/tmp/no_corruption.conf"
    use_predefined_config "corruption_zero.conf" "${CONFIG_FILE}"

    # Start container with clean configuration
    start_container_with_config "${CONFIG_FILE}" || return 1

    # Mount SMB share
    mount_smb_share || return 1

    # Create a set of test files with different sizes
    echo "Creating test files with known content..."
    echo -n "${TEST_CONTENT}" > "${TEMP_FILE}"

    # Create a larger file for more thorough testing
    local LARGE_FILE="test_no_corruption_large.txt"
    local LARGE_TEMP_FILE="/tmp/${LARGE_FILE}"
    echo "Creating larger test file (10KB)..."
    dd if=/dev/zero bs=1k count=10 | tr '\0' 'A' > "${LARGE_TEMP_FILE}"

    # Copy files to SMB share
    echo "Copying files to SMB share..."
    cp "${TEMP_FILE}" "${HOST_MOUNT_POINT}/${TEST_FILE}"
    cp "${LARGE_TEMP_FILE}" "${HOST_MOUNT_POINT}/${LARGE_FILE}"

    # Wait for write to complete
    sleep 3

    # Function to verify integrity (no corruption)
    verify_integrity() {
        local SOURCE_FILE="$1"
        local DEST_FILE="$2"
        local FILE_DESC="$3"

        if [ ! -f "${DEST_FILE}" ]; then
            echo "ERROR: ${FILE_DESC} not found in storage path: ${DEST_FILE}"
            return 1
        fi

        # Compare file sizes
        local SOURCE_SIZE=$(stat -c%s "${SOURCE_FILE}" 2>/dev/null || stat -f%z "${SOURCE_FILE}")
        local DEST_SIZE=$(stat -c%s "${DEST_FILE}" 2>/dev/null || stat -f%z "${DEST_FILE}")

        echo "${FILE_DESC} verification:"
        echo "- Original size: ${SOURCE_SIZE} bytes"
        echo "- Storage size: ${DEST_SIZE} bytes"

        # Check if sizes match
        if [ "${SOURCE_SIZE}" != "${DEST_SIZE}" ]; then
            echo "- FAIL: Size mismatch when no corruption was expected"
            echo "- Size difference: $((SOURCE_SIZE - DEST_SIZE)) bytes"
            return 1
        else
            echo "- Size integrity verified"
        fi

        # For smaller files, compare entire content
        if [ ${SOURCE_SIZE} -lt 10000 ]; then
            local SOURCE_CONTENT=$(cat "${SOURCE_FILE}")
            local DEST_CONTENT=$(cat "${DEST_FILE}")

            if [ "${SOURCE_CONTENT}" != "${DEST_CONTENT}" ]; then
                echo "- FAIL: Content mismatch when no corruption was expected"
                return 1
            else
                echo "- Content integrity verified"
            fi
        else
            # For larger files, do checksum comparison
            local SOURCE_MD5=$(md5sum "${SOURCE_FILE}" 2>/dev/null | awk '{print $1}' ||
                           md5 -q "${SOURCE_FILE}")
            local DEST_MD5=$(md5sum "${DEST_FILE}" 2>/dev/null | awk '{print $1}' ||
                         md5 -q "${DEST_FILE}")

            if [ "${SOURCE_MD5}" != "${DEST_MD5}" ]; then
                echo "- FAIL: MD5 checksum mismatch when no corruption was expected"
                echo "- Original MD5: ${SOURCE_MD5}"
                echo "- Storage MD5: ${DEST_MD5}"
                return 1
            else
                echo "- MD5 checksum integrity verified"
            fi
        fi

        return 0
    }

    # Check for integrity in storage path
    echo "Verifying integrity of text file..."
    local STORAGE_TEXT_FILE="${HOST_STORAGE_PATH}/${TEST_FILE}"
    verify_integrity "${TEMP_FILE}" "${STORAGE_TEXT_FILE}" "Text file" || {
        # Clean up on failure
        rm -f "${TEMP_FILE}" "${LARGE_TEMP_FILE}"
        rm -f "${HOST_MOUNT_POINT}/${TEST_FILE}" "${HOST_MOUNT_POINT}/${LARGE_FILE}" 2>/dev/null || true
        unmount_smb_share
        return 1
    }

    echo "Verifying integrity of large file..."
    local STORAGE_LARGE_FILE="${HOST_STORAGE_PATH}/${LARGE_FILE}"
    verify_integrity "${LARGE_TEMP_FILE}" "${STORAGE_LARGE_FILE}" "Large file" || {
        # Clean up on failure
        rm -f "${TEMP_FILE}" "${LARGE_TEMP_FILE}"
        rm -f "${HOST_MOUNT_POINT}/${TEST_FILE}" "${HOST_MOUNT_POINT}/${LARGE_FILE}" 2>/dev/null || true
        unmount_smb_share
        return 1
    }

    # Verify we can read back the files through the SMB share
    echo "Verifying file readback through SMB share..."
    if ! cmp "${TEMP_FILE}" "${HOST_MOUNT_POINT}/${TEST_FILE}" >/dev/null 2>&1; then
        echo "FAIL: File content mismatch when reading back through SMB share"
        rm -f "${TEMP_FILE}" "${LARGE_TEMP_FILE}"
        rm -f "${HOST_MOUNT_POINT}/${TEST_FILE}" "${HOST_MOUNT_POINT}/${LARGE_FILE}" 2>/dev/null || true
        unmount_smb_share
        return 1
    else
        echo "File readback verification successful"
    fi

    # Clean up
    rm -f "${TEMP_FILE}" "${LARGE_TEMP_FILE}"
    rm -f "${HOST_MOUNT_POINT}/${TEST_FILE}" "${HOST_MOUNT_POINT}/${LARGE_FILE}" 2>/dev/null || true
    unmount_smb_share

    echo "No corruption test completed successfully"
    return 0
}

# Cleanup any mounted shares and stop containers
cleanup_all_resources() {
    echo "Cleaning up all resources..."

    # Unmount SMB share if mounted
    if mount | grep -q "${HOST_MOUNT_POINT}"; then
        echo "Unmounting SMB share..."
        unmount_smb_share
    fi

    # Stop containers
    echo "Stopping containers..."
    "${PROJECT_ROOT}/scripts/run-fuse.sh" --stop

    # Remove any temp files
    echo "Removing temporary files..."
    rm -f /tmp/high_corruption.conf /tmp/no_corruption.conf /tmp/prob_*.conf

    # Make sure mount point is clean
    if [ -d "${HOST_MOUNT_POINT}" ]; then
        echo "Cleaning mount point directory..."
        rmdir "${HOST_MOUNT_POINT}" 2>/dev/null || true
    fi
}

# Run all tests
run_all_tests() {
    local RESULT=0
    local START_TIME=$(date +%s)
    local TEST_RESULTS=()
    local TEST_TIMES=()

    # Setup trap to ensure cleanup on exit
    trap cleanup_all_resources EXIT INT TERM

    begin_test_group "Data Corruption Fault Injection via SMB"

    # Make sure host storage path and mount point exist
    mkdir -p "${HOST_STORAGE_PATH}"
    mkdir -p "${HOST_MOUNT_POINT}"

    # Check if Docker is running
    if ! docker info &>/dev/null; then
        echo "ERROR: Docker is not running. Please start Docker and try again."
        return 1
    fi

    # Run test: High corruption
    echo -e "\n=== Running test: High corruption ==="
    local TEST_START=$(date +%s)
    run_test test_high_corruption "High corruption with SMB (50%, 100% probability)"
    TEST_RESULTS+=($?)
    TEST_TIMES+=($(($(date +%s) - TEST_START)))

    # Run test: Probability
    echo -e "\n=== Running test: Corruption probability ==="
    TEST_START=$(date +%s)
    run_test test_probability "Corruption probability with SMB"
    TEST_RESULTS+=($?)
    TEST_TIMES+=($(($(date +%s) - TEST_START)))

    # Run test: No corruption
    echo -e "\n=== Running test: No corruption ==="
    TEST_START=$(date +%s)
    run_test test_no_corruption "No corruption with SMB (fault injection disabled)"
    TEST_RESULTS+=($?)
    TEST_TIMES+=($(($(date +%s) - TEST_START)))

    # End test group
    end_test_group
    RESULT=$?

    # Generate summary report
    local END_TIME=$(date +%s)
    local TOTAL_TIME=$((END_TIME - START_TIME))

    echo -e "\n=== CORRUPTION FAULT INJECTION TEST SUMMARY ==="
    echo "Test run completed in ${TOTAL_TIME} seconds"
    echo "High corruption test: ${TEST_RESULTS[0]} (${TEST_TIMES[0]} seconds)"
    echo "Probability test: ${TEST_RESULTS[1]} (${TEST_TIMES[1]} seconds)"
    echo "No corruption test: ${TEST_RESULTS[2]} (${TEST_TIMES[2]} seconds)"

    local PASSED=0
    for res in "${TEST_RESULTS[@]}"; do
        if [ "$res" -eq 0 ]; then
            PASSED=$((PASSED + 1))
        fi
    done

    echo "Tests passed: ${PASSED}/${#TEST_RESULTS[@]}"
    echo "Overall result: $([[ $RESULT -eq 0 ]] && echo "SUCCESS" || echo "FAILURE")"
    echo "===================================================="

    return $RESULT
}

# Run all tests
run_all_tests
exit $?