## Performance Considerations

The FUSE driver has been designed with performance in mind, but there are some inherent limitations to be aware of:

1. **FUSE Overhead**: 
   - The FUSE architecture introduces additional context switches
   - Each filesystem operation requires a user-space to kernel-space transition
   - This overhead is typically 5-15% depending on the operation

2. **Docker Container Impact**:
   - Running in a Docker container adds a small additional overhead
   - Volume mounts through Docker can have performance implications
   - Networking through Docker can add latency to SMB operations

3. **Performance Improvement Strategies**:
   - Enable kernel buffer caching where possible
   - Use direct_io only when necessary for fault scenarios
   - Allow multithreaded operation (default in FUSE 3.x)
   - Optimize path translation and string handling in hot paths

4. **Monitoring Performance**:
   - The logging system can track operation timing
   - Future versions will include more detailed performance metrics
   - Using external tools like `iotop`, `iostat`, and `fio` for benchmarking

## Using Fault Injection

The fault injection system is designed to be highly configurable and easy to use.

### Enabling Fault Injection

By default, fault injection is disabled. To enable it:

1. **Edit the configuration file**:
   ```bash
   nano src/fuse-driver/nas-emu-fuse.conf
   ```
   
2. **Enable the main switch**:
   ```
   enable_fault_injection = true
   ```
   
3. **Restart the FUSE driver**:
   ```bash
   ./scripts/run-fuse.sh
   ```

### Configuring Fault Types

The configuration file (`nas-emu-fuse.conf`) uses a section-based format for different fault types:

```
# Error Fault Configuration
[error_fault]
probability = 0.1  # 10% probability of triggering
error_code = -5    # -EIO error code
operations = read,write,open,create  # Operations to affect
```

Each fault type can be configured independently and multiple fault types can be active simultaneously.

### Testing Fault Injection

To verify fault injection is working:

1. **Enable fault injection with a high probability**:
   ```
   [error_fault]
   probability = 0.9  # 90% probability of triggering
   error_code = -5    # -EIO error code
   operations = write  # Only affect write operations
   ```

2. **Try operations that should be affected**:
   ```bash
   docker-compose exec fuse-dev touch ${NAS_MOUNT_POINT}/test.txt
   # This should fail with a high probability
   ```

3. **Check the logs**:
   ```bash
   docker-compose exec fuse-dev cat ${NAS_LOG_FILE}
   ```
   
   You should see messages like:
   ```
   2025-04-18 15:30:45 [INFO] Error fault active for write: /mnt/nas-mount/test.txt, returning error -5
   ```

### Common Fault Scenarios

1. **Silent Data Corruption**:
   ```
   [corruption_fault]
   probability = 1.0    # Always corrupt
   percentage = 10.0    # Corrupt 10% of bytes
   silent = true        # Don't report errors
   operations = write   # Only affect writes
   ```

2. **Intermittent Network Delays**:
   ```
   [delay_fault]
   probability = 0.3    # 30% chance of delay
   delay_ms = 500       # 500ms delay
   operations = all     # Affect all operations
   ```

3. **Timing-based Failures**:
   ```
   [timing_fault]
   enabled = true       # Enable timing faults
   after_minutes = 5    # Start failing after 5 minutes
   operations = all     # Affect all operations
   ```

4. **Operation Count Failures**:
   ```
   [operation_count_fault]
   enabled = true             # Enable count-based faults
   every_n_operations = 10    # Fail every 10th operation
   operations = read,write    # Only affect read/write
   ```

## Debugging Tips

When troubleshooting issues with the FUSE driver, these approaches can be helpful:

1. **Increase Log Level**:
   - Set `--loglevel=3` (DEBUG) for maximum logging
   - View logs with `docker-compose exec fuse-dev cat ${NAS_LOG_FILE}`

2. **Run in Foreground with Debug**:
   - Stop the background FUSE process
   - Run manually with `./nas-emu-fuse ${NAS_MOUNT_POINT} -f -d`
   - The `-f` option keeps it in foreground
   - The `-d` option enables debug output

3. **Check Mount Status**:
   - `docker-compose exec fuse-dev mount | grep fuse`
   - `docker-compose exec fuse-dev findmnt -t fuse`

4. **Verify Processes**:
   - `docker-compose exec fuse-dev ps aux | grep nas-emu-fuse`
   - `docker-compose exec fuse-dev lsof | grep ${NAS_MOUNT_POINT}`

5. **Examine System Logs**:
   - `docker-compose exec fuse-dev dmesg | tail`
   - Check for FUSE-related kernel messages

6. **Test Basic Functionality**:
   - Create a simple file: `docker-compose exec fuse-dev touch ${NAS_MOUNT_POINT}/test.txt`
   - Verify it appears in storage: `docker-compose exec fuse-dev ls -la ${NAS_STORAGE_PATH}`
   
7. **Verify Fault Injection**:
   - Enable fault injection with a high probability
   - Test operations that should be affected
   - Check the logs for fault injection messages# NAS Emulator FUSE Driver - Detailed Documentation

> **Note**: This is a private context document to maintain knowledge continuity in AI assistant conversations about the FUSE driver component.

## Overview

The FUSE driver is the core component of the NAS Emulator project. It intercepts filesystem operations and can selectively inject faults to simulate various failure scenarios. This document provides detailed information about its design, implementation, and testing.

### Fault Injection Capabilities

The system now implements a comprehensive fault injection framework with the following capabilities:

1. **Error Injection** - Return error codes for specific operations
   - Configurable error codes
   - Probability-based triggering
   - Selective application to specific operations

2. **Data Corruption** - Silently corrupt data during write operations
   - Configurable corruption percentage
   - Byte-level random corruption
   - Only affects write operations

3. **Operation Delays** - Add latency to operations
   - Configurable delay duration
   - Can be applied to any operation type

4. **Partial Operations** - Process only a portion of requested data
   - Configurable size reduction factor
   - Applies to read and write operations

5. **Timing-based Faults** - Trigger faults after running for a certain time
   - Start faults after specified minutes of operation
   - Can trigger any other fault type

6. **Operation Count Faults** - Trigger faults based on operation count
   - Trigger after specified number of operations
   - Trigger after specified number of bytes processed
   - Can trigger any other fault type

## Architecture

The FUSE driver follows a clear separation of concerns between normal filesystem operations and fault injection logic:

1. **Main Driver** (`fs_fault_injector.c`): Orchestrates everything, contains the FUSE operation structure, and wraps each filesystem operation with fault injection checks.

2. **Filesystem Operations** (`fs_operations.c`): Implements the normal passthrough filesystem functionality, passing operations to the underlying filesystem.

3. **Fault Injector** (`fault_injector.c`): Contains the logic for determining when to inject faults and what type of fault to inject.

4. **Logging System** (`log.c`): Provides a flexible, thread-safe logging facility with multiple log levels.

5. **Configuration System** (`config.c`): Manages configuration from files, command-line arguments, and default values.

This separation allows the normal operations to be tested and stabilized independently of the fault injection logic.

## Directory Structure

```
/src/fuse-driver/
├── Makefile                # Build configuration
├── nas-emu-fuse.conf       # Configuration file
├── README-LLM-FUSE.md      # This documentation file
├── /src
│   ├── fs_fault_injector.c # Main entry point and FUSE wrappers
│   ├── fs_operations.c     # Normal filesystem operations
│   ├── fs_operations.h     # Interface for filesystem operations
│   ├── fault_injector.c    # Fault injection logic 
│   ├── fault_injector.h    # Interface for fault injection
│   ├── config.c            # Configuration system
│   ├── config.h            # Configuration interface
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
- Validates permissions for each operation

Key sections:
```c
// Wrapper functions that can inject faults
static int fs_fault_getattr(const char *path, struct stat *stbuf) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_GETATTR);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_GETATTR, &error_code))) {
        LOG_INFO("Error fault active for getattr: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_GETATTR);
    
    // Perform the actual operation
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
    // Load configuration
    // Run FUSE main loop
}
```

### Fault Injection Implementation

The fault injection implementation applies different types of faults with a clear order of precedence:

1. Error faults (return error codes)
2. Delay faults (add latency to operations)
3. Partial operation faults (for read/write operations - process only a portion of data)
4. Data corruption faults (for write operations - silently corrupt data before writing)

Each operation decides which faults can be applied to it. For example, write operations have the most comprehensive fault model:

```c
static int fs_fault_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_WRITE);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_WRITE, &error_code))) {
        LOG_INFO("Error fault active for write: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_WRITE);
    
    // Always check write permission, regardless of whether we have a file handle
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("Write denied due to permission check: %s", path);
        return res;
    }
    
    // 3. Apply partial operation fault if applicable
    size_t adjusted_size = apply_partial_fault(FS_OP_WRITE, size);
    
    // 4. Handle corruption (create a local copy of the buffer and corrupt it)
    char *corrupted_buf = NULL;
    fs_config_t *config = config_get_global();
    
    if (should_fault || (config->corruption_fault && 
                        config_should_affect_operation(config->corruption_fault->operations_mask, FS_OP_WRITE) && 
                        check_probability(config->corruption_fault->probability))) {
            
        // Create a copy of the buffer that we can corrupt
        corrupted_buf = malloc(adjusted_size);
        if (corrupted_buf) {
            memcpy(corrupted_buf, buf, adjusted_size);
            
            // Apply corruption to the buffer
            size_t corrupt_bytes = (size_t)(adjusted_size * config->corruption_fault->percentage / 100.0);
            if (corrupt_bytes == 0 && config->corruption_fault->percentage > 0) {
                corrupt_bytes = 1;
            }
            
            LOG_INFO("Corruption fault injected for write: corrupting %zu of %zu bytes (%.1f%%)",
                    corrupt_bytes, adjusted_size, config->corruption_fault->percentage);
            
            // Corrupt random bytes in the buffer
            for (size_t i = 0; i < corrupt_bytes; i++) {
                size_t pos = rand() % adjusted_size;
                corrupted_buf[pos] = (char)(rand() % 256);  // Replace with random byte
            }
        }
    }
    
    // 5. Perform the actual operation with either the original or corrupted buffer
    res = fs_op_write(path, corrupted_buf ? corrupted_buf : buf, adjusted_size, offset, fi);
    
    // Free our corrupted buffer if we created one
    if (corrupted_buf) {
        free(corrupted_buf);
    }
    
    // Update stats and return
    if (res > 0) {
        update_operation_stats(FS_OP_WRITE, res);
    }
    return res;
}
```

### Fault Triggering Conditions

Faults can be triggered by multiple conditions:

1. **Probability-based triggering** - Each fault type has its own probability
2. **Timing-based triggering** - Faults can be triggered after the system has been running for a certain time
3. **Operation count triggering** - Faults can be triggered based on operation count or bytes processed
4. **Operation selection** - Each fault can be applied to specific operations using a bitmask

The `should_trigger_fault` function checks timing and operation count conditions:

```c
bool should_trigger_fault(fs_op_type_t operation) {
    fs_config_t *config = config_get_global();
    
    if (!config->enable_fault_injection) {
        return false;
    }
    
    // Count this operation
    stats.operation_count++;
    stats.op_counts[operation]++;
    
    // Check if any timing condition is met
    if (check_timing_fault(operation)) {
        LOG_INFO("Fault triggered for %s due to timing condition", fs_op_names[operation]);
        return true;
    }
    
    // Check if any operation count condition is met
    if (check_operation_count_fault(operation)) {
        LOG_INFO("Fault triggered for %s due to operation count condition", fs_op_names[operation]);
        return true;
    }
    
    // For all other fault types, we'll check them at the point of use
    return false;
}
```

### Configuration System

**config.h** / **config.c**

The configuration system now supports modular fault injection settings:

```c
// Error fault - returns error codes for operations
typedef struct {
    float probability;        // Probability of triggering (0.0-1.0)
    int error_code;           // Specific error code to return (e.g., -EIO)
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_error_t;

// Corruption fault - corrupts data in read/write operations
typedef struct {
    float probability;        // Probability of corrupting data
    float percentage;         // Percentage of data to corrupt (0-100)
    bool silent;              // Report success but corrupt data
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_corruption_t;

// Delay fault - adds latency to operations
typedef struct {
    float probability;        // Probability of adding delay
    int delay_ms;             // Delay in milliseconds
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_delay_t;

// Timing fault - triggers based on time patterns
typedef struct {
    bool enabled;             // Whether timing-based triggering is enabled
    int after_minutes;        // Start triggering after X minutes of operation
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_timing_t;

// Operation count fault - triggers based on operation counts
typedef struct {
    bool enabled;             // Whether count-based triggering is enabled
    int every_n_operations;   // Trigger on every Nth operation
    size_t after_bytes;       // Trigger after X bytes processed
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_operation_count_t;

// Partial operation fault - only completes part of read/write operations
typedef struct {
    float probability;        // Probability of partial operation
    float factor;             // Factor to multiply size by (0.0-1.0)
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_partial_t;

// Main configuration structure
typedef struct {
    // Basic filesystem options
    char *mount_point;       // Path to FUSE mount point
    char *storage_path;      // Path to backing storage
    char *log_file;          // Path to log file
    int log_level;           // Log level (0-3)
    
    // Fault injection master switch
    bool enable_fault_injection;  // Master switch for fault injection
    
    // Pointers to specific fault types (NULL if not enabled)
    fault_error_t *error_fault;
    fault_corruption_t *corruption_fault;
    fault_delay_t *delay_fault;
    fault_timing_t *timing_fault;
    fault_operation_count_t *operation_count_fault;
    fault_partial_t *partial_fault;
    
    // Config file path (if used)
    char *config_file;       // Path to configuration file
} fs_config_t;
```

The configuration system follows a hierarchical priority:
1. Command-line arguments (highest priority)
2. Configuration file settings
3. Environment variables
4. Default values (lowest priority)

Configuration file sections provide a clean way to configure each fault type:

```
# NAS Emulator FUSE Configuration

# Basic Settings
mount_point = ${NAS_MOUNT_POINT}
storage_path = ${NAS_STORAGE_PATH}
log_file = ${NAS_LOG_FILE}
log_level = ${NAS_LOG_LEVEL}  # 0=ERROR, 1=WARN, 2=INFO, 3=DEBUG

# Fault Injection Master Switch
enable_fault_injection = false

# Error Fault Configuration
[error_fault]
probability = 0.1  # 10% probability of triggering
error_code = -5  # -EIO error code
operations = read,write,open,create  # Operations to affect

# Other fault type sections follow...
```

### Filesystem Operations

**fs_operations.c**

Implements the normal passthrough filesystem operations. Each function:
- Logs the operation details
- Converts the path to a full path in the backing storage
- Performs permission checks when appropriate
- Calls the corresponding system function
- Handles errors and returns appropriate FUSE error codes

Example function:
```c
int fs_op_read(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    LOG_DEBUG("read: %s, size: %zu, offset: %ld", path, size, offset);
    
    int fd;
    int res;
    
    if (fi == NULL) {
        // No file handle provided, check read permission
        int perms = check_file_perms(path, R_OK);
        if (perms != 0) {
            LOG_DEBUG("read denied: no read permission for %s", path);
            return perms;
        }
        
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