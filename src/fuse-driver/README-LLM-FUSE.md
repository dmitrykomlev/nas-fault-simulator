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
   - Verify it appears in storage: `docker-compose exec fuse-dev ls -la ${NAS_STORAGE_PATH}`# NAS Emulator FUSE Driver - Detailed Documentation

> **Note**: This is a private context document to maintain knowledge continuity in AI assistant conversations about the FUSE driver component.

## Overview

The FUSE driver is the core component of the NAS Emulator project. It intercepts filesystem operations and can selectively inject faults to simulate various failure scenarios. This document provides detailed information about its design, implementation, and testing.

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
    // Load configuration
    // Run FUSE main loop
}
```

### Permission Validation

For operations that modify the filesystem, permission checks are implemented:

```c
static int fs_fault_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    if (should_trigger_fault("write")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for write: %s", path);
    }

    // Always check write permission, regardless of whether we have a file handle
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("Write denied due to permission check: %s", path);
        return res;
    }

    // Update operation statistics
    update_operation_stats("write", size);

    return fs_op_write(path, buf, size, offset, fi);
}
```

### Configuration System

**config.h** / **config.c**

The configuration system provides a flexible way to manage settings from multiple sources:

```c
// Configuration structure
typedef struct {
    // Basic filesystem options
    char *mount_point;       // Path to FUSE mount point
    char *storage_path;      // Path to backing storage
    char *log_file;          // Path to log file
    int log_level;           // Log level (0-3)
    
    // Fault injection options (to be expanded later)
    bool enable_fault_injection;  // Master switch for fault injection
    
    // Config file path (if used)
    char *config_file;       // Path to configuration file
} fs_config_t;

// Initialize configuration with defaults
void config_init(fs_config_t *config);

// Load configuration from file
bool config_load_from_file(fs_config_t *config, const char *filename);

// Free configuration resources
void config_cleanup(fs_config_t *config);
```

The configuration system follows a hierarchical priority:
1. Command-line arguments (highest priority)
2. Configuration file settings
3. Environment variables
4. Default values (lowest priority)

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