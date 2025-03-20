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
├── .gitignore                    # Git ignore file
├── README.md                     # Public documentation
├── README-LLM.md                 # This context document
├── /src
│   ├── /fuse-driver              # FUSE filesystem implementation
│   │   ├── /src
│   │   │   └── fs_fault_injector.c  # Main FUSE driver implementation
│   │   ├── /include              # Header files (to be added)
│   │   ├── /tests                # Unit tests (to be added)
│   │   ├── /docker
│   │   │   └── Dockerfile.dev    # Development environment for FUSE driver
│   │   └── Makefile              # Build configuration for FUSE driver
│   ├── /backend                  # Future Go backend service
│   └── /dashboard                # Future web dashboard
└── /scripts
    ├── build-fuse.sh             # Script to build the FUSE driver
    └── run-fuse.sh               # Script to run the FUSE driver
```

## Key Files Description

### FUSE Driver

- **src/fuse-driver/src/fs_fault_injector.c**: Main FUSE driver file that intercepts filesystem operations. Currently implements basic functionality including `getattr` and `readdir` operations. Uses `/tmp/fs_fault_storage` as the backing storage location.

- **src/fuse-driver/Makefile**: Build configuration for the FUSE driver.

### Docker Configuration

- **src/fuse-driver/docker/Dockerfile.dev**: Development environment for the FUSE driver, based on Ubuntu 22.04 with all necessary dependencies.

- **docker-compose.yml**: Main Docker Compose file at the root level that defines services. Currently only includes the FUSE driver container, but will be expanded for other services.

### Scripts

- **scripts/build-fuse.sh**: Script that builds the FUSE driver inside the Docker container.

- **scripts/run-fuse.sh**: Script that runs the FUSE driver inside the Docker container, mounting it at `/mnt/fs-fault`.

## Development Workflow

The project uses Docker containers for consistent development environments:

1. **Local Development**: Edit code on host machine using any editor
2. **Build Process**: Use `./scripts/build-fuse.sh` to build inside Docker
3. **Running**: Use `./scripts/run-fuse.sh` to run the FUSE driver
4. **Testing**: Run unit tests and functional tests inside containers (to be implemented)

## How FUSE Works in This Project

The FUSE driver creates a virtual filesystem that intercepts operations and can selectively inject faults:

1. **Mount Point**: When run, the FUSE driver mounts at `/mnt/fs-fault` in the container.

2. **Storage Backend**: The actual data is stored at `/tmp/fs_fault_storage`.

3. **Operation Interception**: All filesystem operations to the mount point are intercepted and processed by our implementation.

4. **Passthrough Behavior**: Currently, operations are passed through to the real filesystem at the storage backend.

5. **Unimplemented Operations**: If an operation is not implemented in our FUSE driver, FUSE will return a `-ENOSYS` error (Function not implemented) to the calling application.

## Current Implementation Status

- [x] Project structure setup
- [x] Basic FUSE driver skeleton with minimal implementation
- [x] Docker development environment
- [x] Build and run scripts
- [ ] Complete passthrough filesystem functionality
- [ ] Fault injection framework
- [ ] SMB server integration
- [ ] Backend service
- [ ] Web dashboard

## Next Steps

1. Implement remaining passthrough filesystem operations:
   - `open`, `read`, `write`, `release` (close)
   - `mkdir`, `rmdir`
   - `create`, `unlink` (delete), `rename`
   - `chmod`, `chown`, `truncate`

2. Add configuration mechanism for fault injection
3. Implement fault injection logic within filesystem operations
4. Add logging to track operations and injected faults
5. Create initial unit tests for filesystem operations