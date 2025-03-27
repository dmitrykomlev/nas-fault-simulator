# NAS Emulator FUSE Driver - Detailed Documentation

> **Note**: This is a private context document to maintain knowledge continuity in AI assistant conversations about the FUSE driver component.

## Overview

The FUSE driver is the core component of the NAS Emulator project. It intercepts filesystem operations and can selectively inject faults to simulate various failure scenarios. This document provides detailed information about its design, implementation, and testing.

## Architecture

The FUSE driver follows a clear separation of concerns between normal filesystem operations and fault injection logic:

1. **Main Driver** (`fs_fault_injector.c`): Orchestrates everything, contains the FUSE operation structure, and wraps each filesystem operation with fault injection checks.

2. **Filesystem Operations** (`fs_operations.c`): Implements the normal passthrough filesystem functionality, passing operations to the underlying filesystem.

3. **Fault Injector** (`fault_injector.c`): Contains the logic for determining when to inject faults and what type of fault to inject.

4. **Logging System** (`log.c`): Provides a flexible, thread-safe logging facility with multiple log levels.

This separation allows the normal operations to be tested and stabilized independently of the fault injection logic.

## Directory Structure

```
/src/fuse-driver/
├── Makefile                # Build configuration
├── /src
│   ├── fs_fault_injector.c # Main entry point and FUSE wrappers
│   ├── fs_operations.c     # Normal filesystem operations
│   ├── fs_operations.h     # Interface for filesystem operations
│   ├── fault_injector.c    # Fault injection logic 
│   ├── fault_injector.h    # Interface for fault injection
│   ├── log.c               # Logging implementation
│   └── log.h               # Logging interface
├── /tests
│   ├── /functional         # Functional tests
│   │   ├── run_all_tests.sh   # Test runner
│   │   ├── test_helpers.sh    # Test helper functions
│   │   ├── test_basic_ops.sh  # Basic operations test
│   │   └── test_large_file_ops.sh  # Large file tests
│   └── /unit               # Unit tests (to be implemented)
└── /docker
    └── Dockerfile.dev      # Development environment
```

## Key Files

### Main Driver

**fs_fault_injector.c**

This is the main entry point for the FUSE driver. It:
- Initializes the filesystem operations and fault injector
- Contains the FUSE operation structure that maps filesystem requests to handlers
- Wraps each filesystem operation with fault injection checks
- Manages command line arguments and configuration

Key sections:
```c
// Wrapper functions that can inject faults
static int fs_fault_getattr(const char *path, struct stat *stbuf) {
    if (should_trigger_fault("getattr")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for getattr: %s", path);
    }
    return fs_op_getattr(path, stbuf);
}

// FUSE operations structure
static struct fuse_operations fs_fault_oper = {
    .getattr  = fs_fault_getattr,
    .readdir  = fs_fault_readdir,
    // ... other operations
};

// Main function
int main(int argc, char *argv[]) {
    // Initialize logging, filesystem operations, and fault injector
    // Parse command line options
    // Run FUSE main loop
}
```

### Filesystem Operations

**fs_operations.c**

Implements the normal passthrough filesystem operations. Each function:
- Logs the operation details
- Converts the path to a full path in the backing storage
- Calls the corresponding system function
- Handles errors and returns appropriate FUSE error codes

Example function:
```c
int fs_op_read(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    LOG_DEBUG("read: %s, size: %zu, offset: %ld", path, size, offset);
    
    int fd;
    int res;
    
    if (fi == NULL) {
        char *fullpath = get_full_path(path);
        if (!fullpath) return -ENOMEM;
        
        fd = open(fullpath, O_RDONLY);
        free(fullpath);
        
        if (fd == -1) {
            int err = -errno;
            LOG_DEBUG("read failed to open: %s, error: %s", path, strerror(errno));
            return err;
        }
    } else {
        fd = fi->fh;
    }
    
    res = pread(fd, buf, size, offset);
    if (res == -1) {
        res = -errno;
        LOG_DEBUG("read failed: %s, error: %s", path, strerror(errno));
    }
    
    if (fi == NULL) {
        close(fd);
    }
    
    return res;
}
```

**fs_operations.h**

Defines the interface for filesystem operations:
```c
// Initialize the filesystem operations
void fs_ops_init(const char *storage_dir);

// Clean up filesystem operations
void fs_ops_cleanup(void);

// Filesystem operations
int fs_op_getattr(const char *path, struct stat *stbuf);
int fs_op_readdir(const char *path, void *buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info *fi);
// ... other operations

// Helper functions
char* get_full_path(const char *path);
```

### Fault Injector

**fault_injector.c**

Currently contains stub implementations for fault injection. This will be expanded to include:
- Fault type configuration
- Fault trigger conditions
- Fault behavior implementation

Current implementation:
```c
// Initialize the fault injector
void fault_injector_init(void) {
    LOG_INFO("Fault injector initialized");
}

// Check if a fault should be triggered for an operation
bool should_trigger_fault(const char *operation) {
    // Stub implementation - no faults for now
    LOG_DEBUG("Checking fault for operation: %s (none configured)", operation);
    return false;
}

// Update operation statistics (e.g., bytes processed)
void update_operation_stats(const char *operation, size_t bytes) {
    // Stub implementation - just log for now
    LOG_DEBUG("Operation stats: %s processed %zu bytes", operation, bytes);
}
```

**fault_injector.h**

Defines the interface for fault injection:
```c
// Initialize the fault injector
void fault_injector_init(void);

// Clean up fault injector resources
void fault_injector_cleanup(void);

// Check if a fault should be triggered for an operation
bool should_trigger_fault(const char *operation);

// Update operation statistics (e.g., bytes processed)
void update_operation_stats(const char *operation, size_t bytes);
```

### Logging System

**log.c**

Implements a thread-safe logging system with multiple log levels:
```c
// Initialize logging system
void log_init(const char *log_file, log_level_t level) {
    pthread_mutex_lock(&log_mutex);
    
    // Set log level
    current_log_level = level;
    
    // Open log file
    // ...
    
    pthread_mutex_unlock(&log_mutex);
}

// Log a message with specific level
void log_message(log_level_t level, const char *format, ...) {
    // Skip if level is higher than current level
    if (level > current_log_level || log_file_handle == NULL) {
        return;
    }
    
    pthread_mutex_lock(&log_mutex);
    
    // Format and print log message
    // ...
    
    pthread_mutex_unlock(&log_mutex);
}
```

**log.h**

Defines the logging interface:
```c
// Log levels
typedef enum {
    LOG_ERROR,  // Critical errors
    LOG_WARN,   // Warnings
    LOG_INFO,   // Informational messages
    LOG_DEBUG   // Detailed debug information
} log_level_t;

// Initialize logging system
void log_init(const char *log_file, log_level_t level);

// Close logging system
void log_close(void);

// Log a message with specific level
void log_message(log_level_t level, const char *format, ...);

// Helper macros for easier usage
#define LOG_ERROR(fmt, ...) log_message(LOG_ERROR, fmt, ##__VA_ARGS__)
#define LOG_WARN(fmt, ...)  log_message(LOG_WARN, fmt, ##__VA_ARGS__)
#define LOG_INFO(fmt, ...)  log_message(LOG_INFO, fmt, ##__VA_ARGS__)
#define LOG_DEBUG(fmt, ...) log_message(LOG_DEBUG, fmt, ##__VA_ARGS__)
```

## Testing Framework

The FUSE driver includes a comprehensive functional testing framework to ensure that the basic filesystem operations work correctly.

### Test Structure

The testing framework consists of:

1. **Test Helper Functions** (`test_helpers.sh`): Common utilities for test setup, assertions, and cleanup.

2. **Test Suites**:
   - `test_basic_ops.sh`: Tests basic file and directory operations
   - `test_large_file_ops.sh`: Tests operations with larger files and performance

3. **Test Runner** (`run_all_tests.sh`): Script to run all test suites and report results.

4. **Docker Test Script** (`run_tests.sh`): Script to run tests inside the Docker container.

### Key Testing Patterns

1. **Test Setup/Teardown**:
```bash
setup() {
    # Create test directory
    TEST_DIR=$(setup_test_dir "$TEST_NAME")
    
    # Verify the directory was created
    if [ ! -d "$TEST_DIR" ]; then
        echo "Error: Failed to create test directory"
        exit 1
    fi
    
    # Change to the directory
    cd "$TEST_DIR" || {
        echo "Error: Failed to change to directory: $TEST_DIR"
        exit 1
    }
}

teardown() {
    cd /
    cleanup_test_dir "$TEST_DIR"
}
```

2. **Test Function Structure**:
```bash
# Test file creation and basic read/write
test_file_create_read_write() {
    local TEST_FILE="$TEST_DIR/test_file.txt"
    local TEST_CONTENT="Hello World from FUSE!"
    
    # Create a file with content
    echo "$TEST_CONTENT" > "$TEST_FILE"
    
    # Verify file exists
    assert_file_exists "$TEST_FILE"
    
    # Verify content
    assert_file_content "$TEST_FILE" "$TEST_CONTENT"
    
    return 0
}
```

3. **Test Assertions**:
```bash
# Assert file exists
assert_file_exists() {
    if [ ! -f "$1" ]; then
        echo -e "${RED}ERROR: File $1 does not exist${NC}"
        exit 1
    fi
}

# Assert file content matches expected
assert_file_content() {
    local FILE="$1"
    local EXPECTED="$2"
    local CONTENT=$(cat "$FILE")
    
    if [ "$CONTENT" != "$EXPECTED" ]; then
        echo -e "${RED}ERROR: Content mismatch in $FILE${NC}"
        echo "Expected: $EXPECTED"
        echo "Actual: $CONTENT"
        exit 1
    fi
}
```

## Fault Injection Design

The fault injector is designed with a clear interface that allows for flexible fault configuration.

### Planned Fault Types

1. **I/O Errors**: Return error codes for operations
2. **Silent Corruption**: Return success but modify or discard data
3. **Partial Operations**: Complete only part of a read/write
4. **Timeouts**: Introduce delays in operations
5. **Permission Errors**: Simulate permission denied scenarios

### Trigger Conditions

1. **Probability-based**: Trigger with a certain probability
2. **Operation Count**: Trigger after N operations
3. **Byte Count**: Trigger after X bytes transferred
4. **Time-based**: Trigger at specific times or after a duration
5. **Pattern-based**: Trigger based on operation patterns

### Fault Configuration

Planned configuration interface:
```c
// Fault configuration structure
typedef struct {
    fault_type_t type;            // Type of fault to inject
    fault_trigger_t trigger;      // When to trigger the fault
    
    // Trigger parameters (e.g., probability, operation count)
    // Fault parameters (e.g., error code, delay)
} fault_config_t;

// Configure a fault for a specific operation
void configure_fault(const char *operation, fault_config_t *config);
```

## Building and Running

### Building the FUSE Driver

```bash
./scripts/build-fuse.sh
```

This script:
- Starts the Docker container if not running
- Compiles the FUSE driver inside the container
- Produces the binary at `src/fuse-driver/nas-emu-fuse`

### Running the FUSE Driver

```bash
./scripts/run-fuse.sh
```

This script:
- Starts the Docker container if not running
- Mounts the FUSE filesystem at `/mnt/fs-fault` in the container
- Uses `/tmp/fs_fault_storage` as the backing storage

### Running Tests

```bash
./scripts/run_tests.sh
```

This script:
- Starts the Docker container if not running
- Builds the FUSE driver if needed
- Checks if FUSE is mounted, and mounts it if not
- Runs all functional tests
- Reports test results

## Future Enhancements

1. **Fault Configuration System**:
   - Configuration file format
   - Runtime configuration API
   - Dynamic fault adjustment

2. **Advanced Fault Types**:
   - Data corruption patterns
   - Selective operation failures
   - Cascading failures
   - Recovery testing

3. **Performance Monitoring**:
   - Operation latency tracking
   - Throughput measurement
   - Resource usage monitoring

4. **Integration with Network Layer**:
   - SMB protocol faults
   - Network-level disruptions
   - Protocol-specific failures

5. **Extended Testing**:
   - Unit tests for fault injection
   - Stress testing
   - Benchmarking
   - Recovery testing