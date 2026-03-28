# FUSE Driver - LLM Context

## Overview

The FUSE driver is the core component that intercepts filesystem operations and selectively injects faults to simulate failure scenarios. It passthrough-mounts the backing storage while applying fault injection logic before delegating to the actual filesystem. The fault injection system is configurable, probability-based, and supports multiple independent fault types with a clear priority ordering system.

## Architecture

The driver separates concerns across five main modules:

1. **fs_fault_injector.c** - Main entry point and FUSE operation wrappers. Contains the FUSE operations structure and wraps each filesystem operation with priority-based fault injection checks.

2. **fs_operations.c** - Passthrough filesystem operations. Performs actual file operations (read, write, open, etc.) against the backing storage after fault injection logic completes.

3. **fault_injector.c** - Fault injection logic. Implements probability checks, timing conditions, operation counting, and fault trigger conditions.

4. **config.c** - Configuration parser. Reads ini-style config files with CRLF defense-in-depth (strips \r\n after fgets() to handle both Unix/Windows line endings).

5. **log.c** - Thread-safe logging system. Supports four log levels (ERROR=0, WARN=1, INFO=2, DEBUG=3).

## Fault Priority System

Each operation wrapper checks faults in strict priority order. The first fault that triggers determines the outcome. All fault types are independent with no cross-dependencies:

1. **Error Faults** - Operation fails with error code (e.g., -EIO). Highest priority, aborts operation immediately.
2. **Timing Faults** - Operation fails if system runtime exceeds after_minutes threshold. Aborts operation.
3. **Operation Count Faults** - Operation fails after specified operation count or bytes processed. Aborts operation.
4. **Permission Check** - Always validated (not a fault, built-in check).
5. **Delay Faults** - Adds latency in milliseconds. Operation continues after delay.
6. **Partial Faults** - Reduces operation size (read/write only). Operation continues with adjusted size.
7. **Corruption Faults** - Corrupts data silently (write only). Operation succeeds but data is corrupted. Lowest priority.

Example priority flow:
```c
if (apply_error_fault(...)) return -EIO;           // 1. Error
if (check_timing_fault(...)) return -EIO;          // 2. Timing
if (check_operation_count_fault(...)) return -EIO; // 3. OpCount
apply_delay_fault(...);                            // 5. Delay
size_t actual_size = apply_partial_fault(...);     // 6. Partial
// Apply corruption logic (write only)             // 7. Corruption
return fs_op_operation(...);                       // Perform operation
```

## Configuration Format

Configuration uses ini-style sections. Each fault type has its own section:

```
[global]
enable_fault_injection = true
mount_point = /nas-mount
storage_path = /storage
log_file = /var/log/nas-emu-fuse.log
log_level = 2  # 0=ERROR, 1=WARN, 2=INFO, 3=DEBUG

[error_fault]
probability = 0.1
error_code = -5
operations = read,write,open

[corruption_fault]
probability = 0.05
percentage = 10.0
operations = write

[delay_fault]
probability = 0.2
delay_ms = 100
operations = all

[timing_fault]
enabled = true
after_minutes = 5
operations = all

[operation_count_fault]
enabled = true
every_n_operations = 100
operations = read,write

[partial_fault]
probability = 0.1
factor = 0.5
operations = read,write
```

## Operation Bitmask

Operations are selected via comma-separated strings: `read,write,open,create,unlink,rmdir,mkdir,rename,truncate,chmod,chown,utimens` or `all` to apply to all operations. Internally converted to bitmask for efficient checking.

## Debugging

1. **Set log_level=3** (DEBUG) in nas-emu-fuse.conf for maximum logging output.

2. **Check logs**: Review /var/log/nas-emu-fuse.log for operation details and fault trigger messages.

3. **Verify mount**: Use `mount | grep fuse` or `findmnt -t fuse` to check FUSE mount status.

4. **Check process**: Verify FUSE driver is running with `ps aux | grep nas-emu-fuse`.

5. **Test basic ops**: Create simple files to verify basic passthrough functionality: `touch /nas-mount/test.txt`.

6. **Verify fault injection**: Enable high probability fault (0.9+) with specific operations, then test expected failures via logs.

Note: Container entrypoint.sh can override log_level via environment variable NAS_LOG_LEVEL.

## Directory Structure

```
src/fuse-driver/
  Makefile
  nas-emu-fuse.conf
  README-LLM-FUSE.md
  src/
    fs_fault_injector.c   # Main wrapper with priority logic
    fs_fault_injector.h
    fs_operations.c       # Passthrough operations
    fs_operations.h
    fault_injector.c      # Fault trigger logic
    fault_injector.h
    config.c              # INI parser + CRLF stripping
    config.h
    log.c                 # Thread-safe logging
    log.h
  tests/
    configs/              # Fault injection config files
    functional/           # Historical bash test scripts
```
