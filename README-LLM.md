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
├── .gitignore                    # Git ignore file
├── README.md                     # Public documentation
├── README-LLM.md                 # This context document
├── README-LLM-FUSE.md            # Detailed FUSE driver documentation
├── /src
│   ├── /fuse-driver              # FUSE filesystem implementation
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
├── /nas-storage                  # Persistent storage for NAS data
└── /scripts
    ├── build-fuse.sh             # Script to build the FUSE driver
    ├── run-fuse.sh               # Script to run the FUSE driver
    └── run_tests.sh              # Script to run all tests in Docker
```

## Implementation Status

### FUSE Driver Component

- [x] FUSE driver core structure and separation of concerns
- [x] Basic passthrough filesystem operations
  - [x] File operations (read, write, create, open, release)
  - [x] Directory operations (mkdir, rmdir, readdir)
  - [x] File attribute operations (getattr)
  - [x] Advanced operations (chmod, chown, truncate, utimens)
- [x] Logging system with multiple levels
- [x] Configuration system with file and command-line options
- [x] Functional testing framework
  - [x] Basic operations tests
  - [x] Large file operations tests
- [x] Docker development environment
- [x] Persistent storage with host volume mapping
- [ ] Unit testing for fault conditions
- [ ] Fault injection logic implementation
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

### Configuration File
The NAS Emulator uses a configuration file (`nas-emu-fuse.conf`) located in the FUSE driver directory. The file follows an INI-style format:

```ini
# Basic Settings
storage_path = /var/nas-storage
log_file = /var/log/nas-emu-fuse.log
log_level = 2  # 0=ERROR, 1=WARN, 2=INFO, 3=DEBUG

# Fault Injection Settings
enable_fault_injection = false
```

### Docker Environment Variables
- `NAS_STORAGE_PATH`: Path on the host for backing storage (default: ./nas-storage)

### Command-Line Options
- `--storage=PATH`: Path to the backing storage
- `--log=PATH`: Path to the log file 
- `--loglevel=LEVEL`: Log level (0-3)
- `--config=PATH`: Path to the configuration file

## Storage Configuration

The FUSE driver now uses a persistent storage location for its backing storage instead of the previous temporary location. This change ensures that:

1. Files are accessible from the host machine
2. Data persists across container restarts and reboots
3. Multiple containers can share the same backing storage

### Storage Paths
- Inside container: `/var/nas-storage` (configurable)
- On host: `./nas-storage` (configurable via `NAS_STORAGE_PATH` environment variable)

### Docker Volume Behavior
- If the host storage directory doesn't exist, Docker will create it automatically
- The directory permissions will be those of the Docker daemon (usually root)
- You may need to adjust permissions if accessing from a regular user account

## Networking Configuration

The NAS Emulator is designed to expose SMB services for network access. When configuring ports:

- The standard SMB port (445) may conflict with existing services on the host
- For development, use an alternative port like 1445 to avoid conflicts
- Configure your docker-compose.yml accordingly:
  ```yaml
  ports:
    - "1445:445"  # Map container port 445 to host port 1445
  ```

## Development Workflow

The project uses Docker containers for consistent development environments:

1. **Local Development**: Edit code on host machine using any editor
2. **Build Process**: Use `./scripts/build-fuse.sh` to build inside Docker
3. **Running**: Use `./scripts/run-fuse.sh` to run the FUSE driver
4. **Testing**: Use `./scripts/run_tests.sh` to run functional tests inside Docker

## Next Steps

1. Implement fault injection logic:
   - Fault configuration mechanism
   - Specific fault implementations
   - Triggering conditions

2. Create unit tests for fault scenarios:
   - Silent data corruption
   - Timing-based failures
   - Operation-count failures

3. Develop SMB layer:
   - Integrate SMB server with FUSE
   - Protocol-level fault injection

4. Build backend service:
   - RESTful API for configuration
   - Metrics collection

5. Develop web dashboard:
   - Configuration UI
   - Monitoring interface

## Documentation Plan

The project documentation is being maintained in several README files:
- README.md - Public-facing documentation
- README-LLM.md - This context document for AI assistant conversations
- README-LLM-FUSE.md - Detailed documentation on the FUSE driver component

Additional documentation will be added for:
- Backend service
- Network layer
- Web dashboard
- Deployment and usage instructions