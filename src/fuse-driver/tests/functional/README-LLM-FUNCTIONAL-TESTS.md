# FUSE Driver Functional Tests - LLM Context Document

> **Note**: This is a private context document to maintain knowledge continuity in AI assistant conversations about the functional test suite.

## Overview

The functional test suite for the NAS Emulator FUSE driver consists of two distinct testing frameworks:

1. **Basic Test Framework** - Simple, fast tests for core functionality
2. **Advanced Test Framework** - Full integration tests with SMB networking

## Test Architecture

### Important: Circular Mount Dependency Issue

**Problem**: When the entire project directory is mounted to the container (`.:/app`) AND SMB shares are mounted on the host in subdirectories of the project (like `./smb-mount`), it creates a circular mount loop:
1. Host creates `nas-storage/` and `smb-mount/` directories in project root
2. Container exposes SMB share from internal storage
3. Host mounts SMB share to `./smb-mount/` 
4. Container sees the mounted SMB share through the `.:/app` volume mount
5. This creates a circular dependency causing SMB operation hangs

**Root Cause**: Mounting the entire project directory (`.:/app`) in runtime exposes host-mounted SMB shares back to the container, creating the circular dependency.

**Solution**: Avoid mounting the entire project directory to the container in runtime. Only mount specific directories needed (configs, storage, etc.).

### Basic Test Framework (`test_helpers.sh`)

**Purpose**: Fast, direct filesystem testing
**Approach**: Tests assume FUSE is already mounted with `no_faults.conf`
**Execution**: Multiple tests run in same container session
**Access Method**: Direct filesystem operations on `/mnt/nas-mount`

**Key Components**:
- `test_helpers.sh` - Common utilities and assertions
- `verify_fuse_driver()` - Sanity check for FUSE mount
- `run_test()` - Test execution wrapper with temp directories
- Color-coded output (`RED`, `GREEN`, `YELLOW`)

**Tests Using This Framework**:
- `test_basic_ops.sh` - File creation, read/write, permissions, rename, delete
- `test_large_file_ops.sh` - Large file handling, multiple files, append operations

### Advanced Test Framework (`test_framework.sh`)

**Purpose**: Full integration testing with realistic network scenarios
**Approach**: Complete container lifecycle management for each test
**Execution**: Fresh container per test with specific configuration
**Access Method**: SMB network share mounted on host system

**Key Features**:
1. **Container Management**: Builds, starts fresh container with specific config
2. **SMB Integration**: Mounts actual SMB share on host (realistic testing)
3. **Config-Specific**: Takes specific config files (e.g., `corruption_high.conf`)
4. **Auto Cleanup**: Automatic resource cleanup on exit/failure
5. **Cross-Platform**: Supports both macOS and Linux SMB mounting

**Workflow**:
```bash
run_test_with_config "config_name.conf" "test_name" test_function
```

**Steps**:
1. Build FUSE driver
2. Start container with specified config
3. Mount SMB share on host
4. Execute test function with mount points
5. Clean up everything

**Tests Using This Framework**:

*Corruption Fault Tests:*
- `test_corruption_none.sh` - No corruption verification (0% probability)
- `test_corruption_medium.sh` - Medium corruption testing (50% probability, 30% data)
- `test_corruption_high.sh` - High corruption testing (100% probability, 70% data)
- `test_corruption_corner_prob.sh` - Corner case: 0% probability, 50% data
- `test_corruption_corner_data.sh` - Corner case: 100% probability, 0% data

*Error Fault Tests (NEW):*
- `test_error_io_write_medium.sh` - Medium I/O errors on write operations (50% -EIO)
- `test_error_io_read_medium.sh` - Medium I/O errors on read operations (50% -EIO)
- `test_error_io_all_high.sh` - High I/O errors on all operations (100% -EIO)
- `test_error_access_create_medium.sh` - Medium access errors on create operations (50% -EACCES)
- `test_error_nospace_write_high.sh` - High no space errors on write operations (100% -ENOSPC)

## Test Categories

### 1. Core Functionality Tests (Basic Framework)
- **File Operations**: Create, read, write, delete
- **Directory Operations**: Create, list, delete
- **Permissions**: chmod, access control (Note: currently failing)
- **Large Files**: Multi-MB file handling
- **Multiple Files**: Concurrent file operations

### 2. Fault Injection Tests (Advanced Framework) - NEW PRIORITY-BASED DESIGN

#### Fault Priority Order (Each Independent)
1. **ERROR FAULTS** (Highest Priority) - Operation fails immediately with error code
2. **TIMING FAULTS** - Operation fails after time threshold
3. **OPERATION COUNT FAULTS** - Operation fails based on count/bytes processed  
4. **PERMISSION CHECK** - Always validate permissions
5. **DELAY FAULTS** - Operation continues but with added latency
6. **PARTIAL FAULTS** - Operation succeeds but with reduced data size
7. **CORRUPTION FAULTS** (Lowest Priority) - Operation succeeds but data is corrupted

#### Test Categories by Fault Type
- **Corruption Testing**: Data corruption probability verification (50% data, various probabilities)
- **Error Injection**: Return specific error codes (configurable per operation)
- **Timing-based Faults**: Trigger failures after X minutes of operation
- **Count-based Faults**: Trigger failures every N operations or after X bytes
- **Delay Injection**: Add configurable latency to operations
- **Partial Operations**: Process only portion of requested data
- **Network Protocol**: All fault types tested through SMB share
- **Configuration Scenarios**: Independent fault type configurations
- **Consistency Checks**: SMB vs direct storage comparison

## Current Test Status

### ✅ Working Tests
- Basic file operations (create, read, write, delete)
- Directory operations (create, list)
- File rename operations  
- File permissions (chmod, access control) - **FIXED** in commit 73eda71
- Large file operations (10MB+ files)
- Multi-file operations
- File append operations
- **NEW**: Priority-based fault injection system
- **NEW**: Data corruption with configurable probability and percentage
- **NEW**: Independent fault types (error, timing, count, delay, partial, corruption)

### ❌ Known Issues
- ~~**File Permissions Test**: `chmod 400` (read-only) doesn't prevent writing~~ **FIXED**
  - ~~Root cause: Permission enforcement in FUSE driver~~
  - ~~Location: `fs_operations.c` permission checking logic~~
  - **Resolution**: Fixed in commit 73eda71 - problem was wrong execution path inside container

### ✅ Corruption Tests (NEW: Organized Test-Driven Structure)
- **Fully Organized**: 5 dedicated corruption tests with matching config files
- **Architecture**: Complete priority-based independent fault injection system
- **Design**: Test-driven configs eliminate dual source of truth
- **Status**: Working with new organized structure - each test has corresponding config

## Configuration Files

### Test Configurations (Organized Test-Driven Structure)

#### Basic & Baseline Configs
- `no_faults.conf` - Clean testing (fault injection disabled) - used by basic tests
- `corruption_none.conf` - No faults baseline (fault injection disabled) - used for "no errors" tests

#### Corruption Fault Configs  
- `corruption_medium.conf` - Medium corruption (50% probability, 30% data)
- `corruption_high.conf` - High corruption (100% probability, 70% data)
- `corruption_corner_prob.conf` - Corner case: 0% probability, 50% data (no corruption expected)
- `corruption_corner_data.conf` - Corner case: 100% probability, 0% data (no corruption expected)

#### Error Fault Configs (NEW)
- `error_io_write_medium.conf` - Medium I/O errors on write operations (50% probability, -EIO)
- `error_io_read_medium.conf` - Medium I/O errors on read operations (50% probability, -EIO)
- `error_io_all_high.conf` - High I/O errors on all operations (100% probability, -EIO)
- `error_access_create_medium.conf` - Medium access errors on create operations (50% probability, -EACCES)
- `error_nospace_write_high.conf` - High no space errors on write operations (100% probability, -ENOSPC)

## Test Runner Scripts

### `run_all_tests.sh`
**Current Scope**: Basic framework tests (prerequisite for advanced tests)
**Config Used**: `no_faults.conf` (clean testing)
**Tests Included**:
- Basic operations
- Large file operations

**Integration with Advanced Tests**:
- Advanced tests run automatically after basic tests pass
- Basic test failure skips advanced tests (proper dependency management)

### `scripts/run_tests.sh`
**Purpose**: Full test suite execution with proper dependency management
**Capabilities**:
- Docker container management (starts if needed)
- FUSE driver build (builds if needed)
- FUSE mount (mounts if needed)
- Calls `run_all_tests.sh` for basic tests
- **NEW**: Runs advanced corruption tests only if basic tests pass
- **NEW**: Integrated priority-based fault injection testing

## Organized Test-Driven Structure (NEW)

### Test Suite Organization (COMPLETED)
**Problem**: Original tests had dual sources of truth - config files with different parameters than test expectations.
**Solution**: Implemented **Option 2: Test-Driven Configs** with perfect alignment:

| Test File | Config File | Probability | Data % | Purpose |
|-----------|-------------|-------------|---------|---------|
| `test_corruption_none.sh` | `corruption_none.conf` | 0% (disabled) | N/A | Verify no corruption |
| `test_corruption_medium.sh` | `corruption_medium.conf` | 50% | 30% | Medium corruption testing |
| `test_corruption_high.sh` | `corruption_high.conf` | 100% | 70% | High corruption testing |
| `test_corruption_corner_prob.sh` | `corruption_corner_prob.conf` | 0% | 50% | Corner case: probability trumps percentage |
| `test_corruption_corner_data.sh` | `corruption_corner_data.conf` | 100% | 0% | Corner case: zero data corruption |

**Key Improvements**:
- **Single source of truth**: Test name matches config parameters exactly
- **200-byte test data**: Sufficient for reliable corruption percentage testing  
- **Sequential writes**: Append operations testing
- **Automatic cleanup**: Fixed framework to cleanup on normal completion
- **Statistical validation**: Tolerance ranges for probability testing
- **Corner cases**: Verify edge case behaviors

**Evidence of Success**:
- No parameter mismatches between tests and configs ✅
- Clear naming convention eliminates confusion ✅
- Comprehensive coverage of corruption scenarios ✅

## Recent Debugging History

### Priority-Based Fault System Redesign (COMPLETED)
**Problem**: Original system had confusing trigger dependencies between fault types
**Root Cause**: Timing/count faults could trigger corruption faults through OR logic
- User feedback: "unnecessary complication" and "confusing"
- Design made it unclear what would fail in each configuration

**Solution**: Complete architectural refactor to priority-based independent system:
```c
// NEW: Each fault checked independently in strict priority order
// 1. ERROR FAULTS (Highest Priority) - Operation fails immediately
if (apply_error_fault(FS_OP_WRITE, &error_code)) {
    return error_code;
}

// 2. TIMING FAULTS - Operation fails due to time conditions
if (check_timing_fault(FS_OP_WRITE)) {
    return -EIO;
}

// 3. OPERATION COUNT FAULTS - Operation fails due to count conditions
if (check_operation_count_fault(FS_OP_WRITE)) {
    return -EIO;
}

// 4. PERMISSION CHECK - Always validate permissions
// 5. DELAY FAULTS - Add latency but operation continues
// 6. PARTIAL FAULTS - Adjust operation size
// 7. CORRUPTION FAULTS (Lowest Priority) - Operation succeeds but data corrupted
```

**Key Design Principles**:
- **Independent Fault Types**: Each fault configured and triggered separately
- **No Cross-Dependencies**: Timing faults don't trigger corruption faults
- **Predictable Behavior**: Users know exactly which fault takes precedence
- **Single Probability Check**: Each fault type checks probability only once
- **Clear Documentation**: Priority order is explicit and documented

**Evidence of Success**:
- Corruption working: 50% of data corrupted with 100% probability ✅
- Independent fault checking: No confusing trigger dependencies ✅
- Priority-based: Clear precedence order documented ✅

## Integration Requirements

### Advanced Tests Integration (COMPLETED):
1. **Solution Implemented**: Advanced tests (corruption + error faults) run after basic tests pass
2. **Integration Method**: Modified `scripts/run_tests.sh` to:
   - Run basic tests first (prerequisite)
   - Only run advanced tests if basic tests succeed
   - Skip advanced tests if basic functionality is broken
   - Run both corruption and error fault test suites
3. **Framework Coexistence**: Both frameworks work together seamlessly
4. **Test Coverage**: Now includes comprehensive error fault testing alongside corruption testing

### SMB Testing Requirements:
- **macOS**: Requires `mount_smbfs` command
- **Linux**: Requires CIFS kernel support and `mount` command
- **Docker**: SMB service must be running and accessible
- **Network**: Port 1445 must be accessible for SMB

## Future Improvements

### Test Coverage Gaps
1. **Error Injection Tests**: Framework exists, need specific test scenarios
2. **Delay Injection Tests**: Framework exists, need specific test scenarios  
3. **Partial Operation Tests**: Framework exists, need specific test scenarios
4. **Timing-based Fault Tests**: Framework exists, need specific test scenarios
5. **Operation Count Fault Tests**: Framework exists, need specific test scenarios

**NOTE**: All fault injection types are now implemented in the priority-based system. Test scenarios need to be written to exercise each fault type independently.

### Framework Enhancements
1. **Unified Test Runner**: Combine both frameworks seamlessly
2. **Parallel Test Execution**: Run tests concurrently where possible
3. **Test Result Reporting**: JSON/XML output for CI/CD integration
4. **Performance Benchmarking**: Add timing and throughput metrics

## Command Quick Reference

```bash
# Run all basic tests (no fault injection)
./scripts/run_tests.sh

# Run basic tests directly in container (after copying scripts)
docker compose exec fuse-dev mkdir -p /tests
docker cp src/fuse-driver/tests/functional/*.sh $(docker compose ps -q fuse-dev):/tests/
docker compose exec fuse-dev bash -c "cd /tests && ./run_all_tests.sh"

# Run corruption tests manually
./src/fuse-driver/tests/functional/test_corruption_none.sh
./src/fuse-driver/tests/functional/test_corruption_medium.sh
./src/fuse-driver/tests/functional/test_corruption_high.sh
./src/fuse-driver/tests/functional/test_corruption_corner_prob.sh
./src/fuse-driver/tests/functional/test_corruption_corner_data.sh

# Run error fault tests manually (NEW)
./src/fuse-driver/tests/functional/test_error_io_write_medium.sh
./src/fuse-driver/tests/functional/test_error_io_read_medium.sh
./src/fuse-driver/tests/functional/test_error_io_all_high.sh
./src/fuse-driver/tests/functional/test_error_access_create_medium.sh
./src/fuse-driver/tests/functional/test_error_nospace_write_high.sh

# Test specific fault types with organized configs
./scripts/run-fuse.sh --config=corruption_medium.conf
./scripts/run-fuse.sh --config=error_io_write_medium.conf
./scripts/run-fuse.sh --config=error_io_all_high.conf
./scripts/run-fuse.sh --config=error_access_create_medium.conf
./scripts/run-fuse.sh --config=error_nospace_write_high.conf

# Debug FUSE mount
docker compose exec fuse-dev mount | grep fuse
docker compose exec fuse-dev ps aux | grep nas-emu
```

## Recent Major Improvements

### Critical Bug Fixes (COMPLETED) ✅
1. **Double Corruption Bug**: Fixed `fs_fault_injector.c` calling `apply_corruption_fault()` twice per operation
   - **Issue**: 70% config resulted in ~91% actual corruption (0.7 + 0.7 - 0.7×0.7 = 91%)
   - **Fix**: Single corruption call with proper temp buffer management
   - **Result**: Corruption now matches configuration (70% → ~77% with normal variance)

2. **Path Resolution Bug**: Fixed `.env` overriding test framework absolute paths
   - **Issue**: Tests failed finding files due to relative vs absolute path conflicts
   - **Fix**: Source `.env` before setting test-specific paths
   - **Result**: All tests now find files correctly

3. **Test Validation**: Changed warnings to hard failures for probability threshold violations
   - **Issue**: Tests passed with warnings when outside acceptable ranges
   - **Fix**: Fail tests when probability outside ±15% of expected (was ±30%)
   - **Result**: More reliable statistical validation

### SMB Layer Limitations Discovered ⚠️
**CRITICAL FINDING**: SMB server masks FUSE errors through automatic retry mechanisms:
- **SMB Retry Logic**: Performs exactly one retry per failed FUSE operation
- **Error Masking**: All SMB operations show NT_STATUS_OK even when FUSE returns errors
- **Statistical Impact**: 50% FUSE error rate becomes ~5-7% test-level error rate
- **Root Cause**: Only consecutive FUSE failures (0.5 × 0.5 = 25%) propagate to clients
- **Implication**: Error fault testing shows "user experience" rather than raw fault rates

### Test Architecture Status
- **FUSE-level testing**: ✅ Accurate fault injection with proper validation
- **SMB-level testing**: ⚠️ Limited by SMB resilience mechanisms
- **End-to-end testing**: ⚠️ Shows real-world behavior but not fault injection accuracy

## Development vs Production Testing

### Current Setup (Development)
- **Build**: Runtime compilation in Docker
- **Config**: Volume-mounted source code  
- **Purpose**: Development and debugging
- **Known Issue**: FUSE rebuilds don't trigger container rebuilds (manual cleanup required)

### Production Testing Needs
- **Pre-built Images**: Compiled binaries in container
- **CI/CD Integration**: Automated test execution
- **Performance Testing**: Load and stress testing
- **Security Testing**: Vulnerability scanning