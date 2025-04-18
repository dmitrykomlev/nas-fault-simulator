# NAS Emulator Project - LLM Context Document

> **Note**: This is a private context document to maintain knowledge continuity in AI assistant conversations about this project. Not intended for public documentation.

## Project Overview

The NAS Emulator is a testing tool designed to simulate fault scenarios in Network Attached Storage systems. Its primary purpose is to enable QA and development teams to test backup software against various failure modes that are difficult to reproduce with real hardware.

### Key Problem Statement

When backing up large datasets (terabytes) to NAS devices, various failure modes can occur:
- Silent data corruption (NAS confirms write but doesn't actually persist data)
- Network disruptions during long operations
- Intermittent failures based on timing or operation count
- Data integrity issues during checkpoint operations
- Permission-related failures that appear inconsistently

These failures are difficult to reproduce reliably with real hardware, making systematic testing nearly impossible.

## Target Functionality

The NAS Emulator will simulate a real NAS device with configurable fault injection capabilities:
- Appear as a standard network share (SMB)
- Allow configuration of various failure modes
- Support large data transfers (hundreds of GBs)
- Provide monitoring and logging of system behavior
- Enable precise control over when and how failures occur

## Architecture Components

### 1. FUSE Filesystem Layer
- Core component that intercepts filesystem operations
- Implements configurable fault injection at the I/O level
- Provides hooks for silent corruption, partial writes, timing-based failures
- Exposes API for configuration and monitoring
- Performs permission validation for all operations

### 2. Network Layer
- SMB server implementation
- Network disruption simulation capabilities
- Authentication and share configuration
- Protocol-level fault injection

### 3. Backend Service
- RESTful API for configuration and control
- Metrics collection and aggregation
- State management for fault scenarios
- Coordination between components

### 4. Web Dashboard
- Real-time activity monitoring
- Graphical metrics display
- Fault configuration interface
- Storage analytics
- Share configuration

### 5. Storage Backend
- Support for large volume management
- Performance optimization for backup workloads
- Data persistence across container restarts

## Fault Injection Capabilities

1. **Silent Data Corruption**
   - Report success but don't write data
   - Write corrupted/modified data
   - Partial writes

2. **Network Disruptions**
   - Complete disconnections
   - Intermittent connectivity
   - Bandwidth throttling
   - Latency introduction
   - Packet loss

3. **Timing-based Failures**
   - Fail after X minutes of operation
   - Fail at specific times of day
   - Periodic failures

4. **Operation-based Failures**
   - Fail every Nth operation
   - Fail after X GB transferred
   - Fail during specific operation types (writes vs. reads)

5. **Protocol-specific Issues**
   - SMB session termination
   - Authentication failures
   - Share permission changes

## Project Structure and Files

The project is organized with the following structure:

```
/nas-fault-simulator/
├── docker-compose.yml            # Main Docker Compose file for all services
├── .env                          # Environment variables for Docker Compose
├── .env.local                    # Optional local environment overrides (git-ignored)
├── .gitignore                    # Git ignore file
├── README.md                     # Public documentation
├── README-LLM.md                 # This context document
├── README-LLM-CONF.md            # Configuration system documentation
├── /scripts
│   ├── config.sh                 # Configuration loader for scripts
│   ├── build-fuse.sh             # Script to build the FUSE driver
│   ├── run-fuse.sh               # Script to run the FUSE driver
│   └── run_tests.sh              # Script to run all tests in Docker
├── /src
│   ├── /fuse-driver              # FUSE filesystem implementation
│   │   ├── README-LLM-FUSE.md    # Detailed FUSE driver documentation
│   │   ├── /src                  # Source code for FUSE driver
│   │   │   ├── fs_fault_injector.c  # Main FUSE driver with fault wrappers
│   │   │   ├── fs_operations.c   # Normal filesystem operations
│   │   │   ├── fs_operations.h   # Headers for filesystem operations
│   │   │   ├── fault_injector.c  # Fault injection logic
│   │   │   ├── fault_injector.h  # Headers for fault injection
│   │   │   ├── config.c          # Configuration system implementation
│   │   │   ├── config.h          # Configuration system interface
│   │   │   ├── log.c             # Logging system implementation
│   │   │   └── log.h             # Logging system interface
│   │   ├── /tests                # Tests for the FUSE driver
│   │   │   ├── /functional       # Functional tests
│   │   │   │   ├── run_all_tests.sh   # Script to run all tests
│   │   │   │   ├── test_helpers.sh    # Common test helper functions
│   │   │   │   ├── test_basic_ops.sh  # Basic operations tests
│   │   │   │   └── test_large_file_ops.sh  # Large file operations tests
│   │   │   └── /unit             # Unit tests (to be implemented)
│   │   ├── /docker               # Docker configuration for FUSE driver
│   │   │   └── Dockerfile.dev    # Development environment for FUSE driver
│   │   ├── Makefile              # Build configuration for FUSE driver
│   │   └── nas-emu-fuse.conf     # Configuration file for FUSE driver
│   ├── /backend                  # Future Go backend service
│   └── /dashboard                # Future web dashboard
└── /nas-storage                  # Persistent storage for NAS data (created by Docker)
```

## Implementation Status

### FUSE Driver Component

- [x] FUSE driver core structure and separation of concerns
- [x] Basic passthrough filesystem operations
  - [x] File operations (read, write, create, open, release)
  - [x] Directory operations (mkdir, rmdir, readdir)
  - [x] File attribute operations (getattr)
  - [x] Advanced operations (chmod, chown, truncate, utimens)
- [x] Permission checking for all filesystem operations 
- [x] Logging system with multiple levels
- [x] Configuration system with file and command-line options
- [x] Functional testing framework
  - [x] Basic operations tests
  - [x] Large file operations tests
- [x] Docker development environment
- [x] Persistent storage with host volume mapping
- [x] Fault injection logic implementation
  - [x] Error injection (return error codes)
  - [x] Data corruption (corrupt write operations)
  - [x] Operation delays (add latency)
  - [x] Partial operations (incomplete read/write)
  - [x] Timing-based faults
  - [x] Operation count faults
- [x] Config-based fault configuration with section format
- [ ] Unit testing for fault conditions
- [ ] Performance monitoring 
- [ ] API for external control

### Network Layer (SMB)

- [ ] Basic SMB server integration
- [ ] Protocol-level fault injection
- [ ] Authentication and share configuration

### Backend Service

- [ ] API server implementation
- [ ] Metrics collection
- [ ] Fault configuration management

### Web Dashboard

- [ ] Basic monitoring interface
- [ ] Fault configuration UI
- [ ] Metrics visualization

## Configuration System

The NAS Emulator uses a flexible configuration system with multiple layers:

1. **Command-line parameters** - Essential startup options and overrides
2. **Configuration file** - Detailed settings including fault injection scenarios
3. **Environment variables** - Docker runtime configuration

See README-LLM-CONF.md for detailed information about the configuration system.

## Docker Environment

The project uses Docker for consistent development environments and deployment:

### Docker Components

- **Docker Compose**: Defines the main services and their dependencies
- **Docker Container**: Provides a consistent environment with all necessary dependencies
- **FUSE Driver Container**: Runs with privileged mode to enable FUSE filesystem mounting

### Docker Requirements

- Docker Engine 19.03+ with Docker Compose
- Linux host with FUSE support or Docker Desktop for Mac/Windows
- Privileged container mode (`--privileged`)
- SYS_ADMIN capability and device access (`/dev/fuse`)

### Development Workflow with Docker

1. **Local Development**: Edit code on host machine using any editor
2. **Build Process**: Use `./scripts/build-fuse.sh` to build inside Docker
3. **Running**: Use `./scripts/run-fuse.sh` to run the FUSE driver
4. **Testing**: Use `./scripts/run_tests.sh` to run functional tests inside Docker

## Current Implementation Details

### FUSE Driver

The FUSE driver implementation includes:

1. **Wrapper Functions**: Each filesystem operation is wrapped with a fault injection check:
   ```c
   static int fs_fault_read(const char *path, char *buf, size_t size, off_t offset,
                           struct fuse_file_info *fi) {
       if (should_trigger_fault("read")) {
           // Will implement fault behavior later
           LOG_DEBUG("Fault would be triggered for read: %s", path);
       }
       return fs_op_read(path, buf, size, offset, fi);
   }
   ```

2. **Permission Validation**: All operations validate appropriate permissions:
   ```c
   static int fs_fault_write(const char *path, const char *buf, size_t size, 
                            off_t offset, struct fuse_file_info *fi) {
       if (should_trigger_fault("write")) {
           LOG_DEBUG("Fault would be triggered for write: %s", path);
       }

       // Always check write permission
       int res = fs_op_access(path, W_OK);
       if (res != 0) {
           LOG_DEBUG("Write denied due to permission check: %s", path);
           return res;
       }

       return fs_op_write(path, buf, size, offset, fi);
   }
   ```

3. **Fault Injection Hooks**: The system includes hooks for fault injection:
   ```c
   // Check if a fault should be triggered for an operation
   bool should_trigger_fault(const char *operation) {
       // Stub implementation - no faults for now
       LOG_DEBUG("Checking fault for operation: %s (none configured)", operation);
       return false;
   }
   ```

4. **Operation Statistics**: The system tracks operation statistics:
   ```c
   // Update operation statistics (e.g., bytes processed)
   void update_operation_stats(const char *operation, size_t bytes) {
       // Stub implementation - just log for now
       LOG_DEBUG("Operation stats: %s processed %zu bytes", operation, bytes);
   }
   ```

### Testing Framework

The testing framework includes:

1. **Functional Tests**: Basic filesystem operation tests
2. **Large File Tests**: Performance and reliability tests with larger files
3. **Test Helpers**: Common utilities for test setup, assertions, and cleanup
4. **Test Runner**: Script to run all test suites and report results

## Next Steps

1. Create unit tests for fault injection:
   - Silent data corruption tests
   - Timing-based failure tests
   - Operation-count failure tests
   - Partial operation tests
   - Delay tests

2. Enhance fault configuration mechanism:
   - Add runtime API to configure faults
   - Allow dynamic fault probability adjustment
   - Add more complex fault trigger conditions
   - Create fault profile presets

3. Develop SMB layer:
   - Integrate Samba server with FUSE
   - Implement protocol-level fault injection
   - Configure share permissions

4. Build backend service:
   - Create RESTful API for configuration
   - Implement metrics collection
   - Develop fault scenario management

5. Develop web dashboard:
   - Create configuration UI
   - Build monitoring interface
   - Add visualization of metrics

## Documentation Plan

The project documentation is being maintained in several README files:
- README.md - Public-facing documentation
- README-LLM.md - This context document for AI assistant conversations
- README-LLM-CONF.md - Configuration system documentation
- README-LLM-FUSE.md - Detailed documentation on the FUSE driver component

Additional documentation will be added for:
- Backend service
- Network layer
- Web dashboard
- Deployment and usage instructions