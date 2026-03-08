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
├── Dockerfile                       # Multi-stage Docker build (builder + runtime)
├── .gitattributes                   # CRLF handling for cross-platform development
├── CLAUDE.md                        # Claude Code assistant instructions
├── README-LLM.md                    # This context document
├── README-LLM-CONF.md               # Configuration system documentation
├── VERSION                          # Version string (0.5.0)
├── pyproject.toml                   # Python project metadata (anchors project root)
├── Dockerfile.test                  # Test-runner container
├── /nas_sim/                       # Python orchestration package
│   ├── cli.py                       # CLI entry point (build, run, test, stop, clean)
│   ├── config.py                    # Configuration loader
│   ├── build.py                     # Docker image build
│   ├── run.py                       # Run FUSE+Samba container
│   ├── test.py                      # Two-container test orchestration
│   ├── containers.py                # Container lifecycle helpers
│   ├── docker_utils.py              # Docker SDK helpers
│   ├── port_utils.py                # Free port finder
│   └── console.py                   # Console output helpers
├── /tests/                         # pytest tests (run inside test-runner container)
│   ├── conftest.py                  # Fixtures: smb_mount, raw_storage
│   ├── smb_helpers.py               # SMB mount/unmount
│   ├── validation.py                # Statistical validation
│   ├── test_basic_ops.py            # Basic file/dir operations via SMB
│   ├── test_large_file.py           # Large file handling
│   ├── test_corruption.py           # Corruption tests (5 scenarios)
│   └── test_errors.py               # Error injection tests (7 scenarios)
├── /.github/workflows/             # CI/CD
│   ├── ci.yml                       # Build + test on push
│   └── release.yml                  # Tag-triggered publish to ghcr.io
├── /src/fuse-driver/                # FUSE filesystem implementation
│   ├── README-LLM-FUSE.md           # Detailed FUSE driver documentation  
│   ├── nas-emu-fuse.conf            # Default FUSE driver configuration
│   ├── /src/                        # Source code for FUSE driver
│   │   ├── fs_fault_injector.c      # Main FUSE driver with fault wrappers
│   │   ├── fs_operations.c          # Core filesystem operations
│   │   ├── fs_operations.h          # Filesystem operations interface
│   │   ├── fs_common.c              # Common filesystem utilities
│   │   ├── fs_common.h              # Common filesystem headers
│   │   ├── fault_injector.c         # Fault injection logic and timing
│   │   ├── fault_injector.h         # Fault injection interface
│   │   ├── config.c                 # Configuration parser (CRITICAL: timing fault defaults)
│   │   ├── config.h                 # Configuration system interface
│   │   ├── log.c                    # Logging system implementation
│   │   └── log.h                    # Logging system interface
│   ├── /docker/                     # Docker configurations
│   │   ├── smb.conf                 # Samba configuration
│   │   └── entrypoint.sh            # Container startup script
│   └── /tests/                      # Test suites
│       ├── /configs/                # Test configuration files (organized test-driven structure)
│       │   ├── no_faults.conf       # Clean testing (no fault injection) - basic tests
│       │   ├── corruption_none.conf # No corruption verification (fault injection disabled)
│       │   ├── corruption_medium.conf # Medium corruption (50% probability, 30% data)
│       │   ├── corruption_high.conf # High corruption (100% probability, 70% data)
│       │   ├── corruption_corner_prob.conf # Corner case: 0% probability, 50% data
│       │   └── corruption_corner_data.conf # Corner case: 100% probability, 0% data
│       └── /functional/             # Functional test framework
│           ├── README-LLM-FUNCTIONAL-TESTS.md  # Test architecture docs
│           ├── run_all_tests.sh     # Basic framework test runner
│           ├── test_helpers.sh      # Basic test framework utilities
│           ├── test_framework.sh    # Advanced test framework (SMB)
│           ├── test_basic_ops.sh    # Basic filesystem operations tests
│           ├── test_large_file_ops.sh # Large file handling tests
│           ├── test_corruption_none.sh # No corruption verification test
│           ├── test_corruption_medium.sh # Medium corruption test (50% prob, 30% data)
│           ├── test_corruption_high.sh # High corruption test (100% prob, 70% data)
│           ├── test_corruption_corner_prob.sh # Corner case: 0% prob, 50% data
│           ├── test_corruption_corner_data.sh # Corner case: 100% prob, 0% data
│           ├── test_error_io_read_medium.sh # Error fault test: 50% read error probability  
│           ├── test_error_io_write_medium.sh # Error fault test: 50% write error probability
│           ├── test_error_io_create_medium.sh # Error fault test: 50% create error probability
│           ├── test_error_io_create_high.sh # Error fault test: 100% create error probability
│           ├── test_error_io_all_high.sh # Error fault test: 100% all operations
│           ├── test_error_access_create_medium.sh # Access error test: 50% create errors
│           └── test_error_nospace_write_high.sh # No space error test: 100% write errors
│           └── test_production_skeleton.sh # Production test template
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
- [x] Fault injection testing (Python pytest, two-container model)
  - [x] Corruption fault tests (5 scenarios)
  - [x] Error injection tests (7 scenarios)
  - [ ] Delay and timing-based fault tests
  - [ ] Partial operation fault tests
  - [ ] Operation count fault tests
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

## Technical Debt / Future Improvements

### Docker Architecture (RESOLVED)

**Previous Issue**: Docker-compose complexity and circular mount problems.

**Solution Implemented**:
- ✅ **Pure Docker approach**: Removed docker-compose entirely
- ✅ **Multi-stage builds**: Builder stage compiles, runtime stage executes
- ✅ **Selective mounting**: Only essential directories mounted at runtime
- ✅ **Dynamic configuration**: Automatic port allocation and container naming
- ✅ **Clean separation**: No circular mount dependencies
- ✅ **End-user simplification**: Single command for operation

## Configuration System

The NAS Emulator uses a flexible configuration system with multiple layers:

1. **Command-line parameters** - Essential startup options and overrides
2. **Configuration file** - Detailed settings including fault injection scenarios
3. **Environment variables** - Docker runtime configuration

See README-LLM-CONF.md for detailed information about the configuration system.

### ⚠️ KNOWN CONFIGURATION ISSUE

**Problem**: The current implementation has a configuration precedence conflict that causes debugging issues.

**Root Cause**: The Docker entrypoint script passes `--loglevel="$NAS_LOG_LEVEL"` to the FUSE driver, which overrides the `log_level` setting from the configuration file. This creates a confusing situation where:
- Config file says: `log_level = 3` (DEBUG)
- But runtime gets: `--loglevel=2` (INFO) from environment variable
- Result: DEBUG logs don't appear even when explicitly configured

**Current Workaround**: Manually set `NAS_LOG_LEVEL=3` in the environment when debugging.

**Architectural Issue**: Mixing configuration sources (command line + config file + environment variables) creates precedence conflicts and makes the system unpredictable. 

**Recommendation**: Choose ONE configuration source:
- **Option A**: Config file only (recommended for complex scenarios)
- **Option B**: Command line only (recommended for simple deployments)  
- **Option C**: Environment variables only (recommended for containerized deployments)
- **Option D**: Web interface (planned for end-user experience)

**Future Fix**: Web interface will provide the primary configuration method for end users, with config files retained for development/testing.

## Docker Environment

The project uses Docker for consistent development environments and deployment:

### Docker Components

- **Multi-stage Dockerfile**: Builder stage compiles FUSE driver, runtime stage runs services
- **Pure Docker approach**: Uses `docker run` commands instead of docker-compose
- **Dynamic port allocation**: Automatically finds free ports to avoid conflicts
- **FUSE Driver Container**: Runs with privileged mode to enable FUSE filesystem mounting

### Docker Requirements

- Docker Engine 19.03+ with Docker Compose
- Linux host with FUSE support or Docker Desktop for Mac/Windows
- Privileged container mode (`--privileged`)
- SYS_ADMIN capability and device access (`/dev/fuse`)

### Development Workflow with Docker

1. **Local Development**: Edit code on host machine using any editor (any OS)
2. **Build Process**: `python -m nas_sim build` for multi-stage Docker build
3. **Running**: `python -m nas_sim run --config=CONFIG` to run FUSE+Samba
4. **Testing**: `python -m nas_sim test` runs two-container pytest suite
5. **Cleanup**: `python -m nas_sim clean --all` removes all containers/images
6. **CI/CD**: Push to GitHub triggers build+test; tag with `v*` publishes to ghcr.io

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

**Primary Test System**: Python pytest with two-container model
- Target container runs FUSE+Samba service
- Runner container executes pytest tests against target via SMB mount
- Comprehensive test suites:
  1. **Basic Operations**: File and directory operations via SMB
  2. **Large File Handling**: Multi-GB file transfers and integrity verification
  3. **Corruption Tests**: 5 scenarios with configurable probability and data corruption
  4. **Error Injection Tests**: 7 scenarios for read/write/create/access/nospace errors

**Historical Reference**: Bash functional tests in src/fuse-driver/tests/functional/ for reference only

## Next Steps (TODO Items)

- [x] Fault injection testing suite (corruption and error tests complete)
- [ ] Delay and timing-based fault tests
- [ ] Partial operation fault tests
- [ ] Operation count fault tests
- [ ] Performance monitoring and metrics
- [ ] Backend service (REST API for configuration and monitoring)
- [ ] Web dashboard (configuration UI, monitoring interface, metrics visualization)

## Recent Developments (Major Progress)

### Python Orchestration Migration (2025-Q1) - COMPLETED ✅
1. **Bash to Python Migration**: Replaced bash shell scripts with `nas_sim/` Python package for all operations (build, run, test, stop, clean)
2. **Configuration System Simplification**:
   - Deleted `.env` file (defaults now in Config dataclass)
   - Optional `.env.local` file for overrides in development
   - Defaults in code, overridable via environment or file
3. **Build System Removal**:
   - Deleted `/scripts/` directory entirely (config.sh, build.sh, run-fuse.sh, run_tests.sh)
   - All functionality now in Python via Docker SDK
   - Deleted `run-nas-simulator.sh` (functionality in `python -m nas_sim`)
4. **Cross-Platform Support**:
   - Added `.gitattributes` for CRLF handling in Windows development
   - C config parser hardened for CRLF robustness
   - `find_project_root()` anchors on pyproject.toml for reliable project detection
5. **Test Framework**:
   - Python pytest replaces bash test scripts as primary test system
   - Two-container model: target (FUSE+Samba) + runner (pytest)
   - Bash functional tests in src/fuse-driver/tests/functional/ retained as historical reference

### Docker Architecture Migration (2025-07-03) - COMPLETED ✅
1. **Pure Docker Approach**: Migrated from docker-compose to pure `docker run` commands for all operations
2. **Container Isolation**: Each test uses unique container names (`nas-fault-simulator-${test_name}`) preventing conflicts
3. **Resource Cleanup**: Fixed cascade test failures by ensuring cleanup on all failure scenarios (SMB mount, container startup, test logic)
4. **Legacy Removal**: Removed docker-compose.yml, build-fuse.sh, mount-smb.sh, umount-smb.sh, and Dockerfile variants
5. **End-User Simplification**: Added run-nas-simulator.sh for simple operation, preparing for web interface

### Test Framework Reliability Fixes (2025-07-03) - COMPLETED ✅
1. **Cascade Failure Prevention**: Fixed issue where failed tests left containers running, causing all subsequent tests to fail
2. **Early Cleanup Logic**: Added cleanup on early returns from SMB mount failures, container startup failures, and test logic failures  
3. **Default Cleanup Behavior**: Changed default to cleanup failed containers; use `PRESERVE_ON_FAILURE=true` for debugging
4. **Container Naming**: Standardized unique container names to prevent port conflicts during parallel or sequential testing

### Advanced Fault Injection Testing Suite (Completed)
1. **Error Fault Tests**: Implemented comprehensive error fault injection tests for READ, WRITE, CREATE operations with configurable probability thresholds
2. **Improved Test Validation**: Made tests fail properly when probability thresholds are not met (changed from warnings to hard failures)
3. **Tightened Probability Thresholds**: Reduced acceptable variance from ±30% to ±15% for more reliable statistical validation

### Critical Bug Fixes
1. **Double Corruption Bug Fix**: Fixed critical bug in `fs_fault_injector.c` where `apply_corruption_fault()` was called twice per write operation, causing ~91% corruption instead of configured 70%
2. **Path Resolution Bug**: Fixed `.env` file overriding test framework's absolute path variables, causing tests to fail finding files
3. **Test Framework Improvements**: Enhanced cleanup-on-failure logic to preserve debug environments for individual test runs while cleaning up during automated test runs

### SMB Configuration Optimization
1. **Cache Disabling**: Modified `smb.conf` to disable oplocks, caching, and buffering to improve fault injection visibility:
   ```
   oplocks = no
   level2 oplocks = no
   kernel oplocks = no
   strict locking = yes
   posix locking = yes
   sync always = yes
   ```

### Test Runner Enhancements
1. **Integrated Error Tests**: Added error fault tests to main test runner (`run_tests.sh`)
2. **Container Lifecycle Management**: Fixed basic test container cleanup before advanced tests to prevent resource conflicts

### SMB Layer Limitations Discovered
**CRITICAL FINDING**: SMB server layer performs automatic error recovery that interferes with fault injection testing:
- **Error Masking**: SMB retries failed FUSE operations and reports NT_STATUS_OK even when FUSE returns errors
- **Retry Logic**: SMB performs exactly one retry per failed operation
- **Statistical Impact**: With 50% FUSE error probability, test-level error rate drops to ~5-7% due to retry success (0.5 × 0.5 = 25% chance of double failure, but caching reduces actual operations)
- **Implication**: Fault injection works correctly at FUSE level but SMB layer provides resilience that masks errors from clients

### Test Architecture Status
- **FUSE-level testing**: ✅ Fully functional with accurate fault injection
- **SMB-level testing**: ⚠️ Limited reliability due to SMB error recovery mechanisms  
- **End-to-end testing**: ⚠️ Shows "user experience" rather than raw fault injection rates
- **Container Management**: ✅ Reliable isolation and cleanup preventing cascade failures

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