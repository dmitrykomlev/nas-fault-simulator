# FUSE Driver - LLM Context

## Overview

The FUSE driver is the core component that intercepts filesystem operations and selectively injects faults to simulate failure scenarios. It passthrough-mounts the backing storage while applying fault injection logic before delegating to the actual filesystem. The fault injection system is configurable, probability-based, and supports multiple independent fault types with a clear priority ordering system.

## Architecture

The driver separates concerns across six main modules:

1. **fs_fault_injector.c** - Main entry point and FUSE operation wrappers. Contains the FUSE operations structure, wraps each filesystem operation with priority-based fault injection checks, and emits events after each operation.

2. **fs_operations.c** - Passthrough filesystem operations. Performs actual file operations (read, write, open, etc.) against the backing storage after fault injection logic completes.

3. **fault_injector.c** - Fault injection logic. Implements probability checks, timing conditions, operation counting, and fault trigger conditions. `apply_corruption_fault()` outputs a `corruption_detail_t` struct with byte-level positions/values.

4. **event_emitter.c** - Event emission to external consumers via non-blocking Unix DGRAM socket. Emits JSON events for every read/write operation and fault trigger. See "Event Emission" section below.

5. **config.c** - Configuration parser. Reads ini-style config files with CRLF defense-in-depth. Parses `[management]` section for event emission settings.

6. **log.c** - Thread-safe logging system. Supports four log levels (ERROR=0, WARN=1, INFO=2, DEBUG=3).

## Fault Priority System

Each operation wrapper checks faults in strict priority order. The first fault that triggers determines the outcome. All fault types are independent with no cross-dependencies:

1. **Error Faults** - Operation fails with error code (e.g., -EIO). Highest priority, aborts operation immediately.
2. **Timing Faults** - Operation fails if system runtime exceeds after_minutes threshold. Aborts operation.
3. **Operation Count Faults** - Operation fails after specified operation count or bytes processed. Aborts operation.
4. **Permission Check** - Always validated (not a fault, built-in check).
5. **Delay Faults** - Adds latency in milliseconds. Operation continues after delay.
6. **Partial Faults** - Reduces operation size (read/write only). Operation continues with adjusted size.
7. **Corruption Faults** - Corrupts data silently (write only). Operation succeeds but data is corrupted. Lowest priority.

Example priority flow (from fs_fault_write):
```c
if (timing_count_fault || apply_error_fault(...)) {
    event_emit_fault(FS_OP_WRITE, path, offset, size, "error", error_code);
    return error_code;
}
if (apply_delay_fault(...)) {
    event_emit_fault(FS_OP_WRITE, path, offset, size, "delay", 0);
}
size_t adjusted = apply_partial_fault(FS_OP_WRITE, size);
corruption_detail_t detail;
if (apply_corruption_fault(FS_OP_WRITE, buf, adjusted, &detail)) {
    event_emit_corruption(FS_OP_WRITE, path, offset, adjusted, &detail);
} else {
    event_emit_op(FS_OP_WRITE, path, offset, size, result);
}
```

## Event Emission

### Overview
The event emitter (`event_emitter.c`) sends structured JSON events to a Unix DGRAM socket at `/var/run/nas-emu/events.sock`. A management service (or test script) binds this socket to receive events in real time.

### Design
- **Non-blocking**: `sendto()` with `O_NONBLOCK` — if no listener, events silently drop
- **DGRAM socket**: No connection management needed. Each event is one datagram.
- **Thread-safe**: `sendto()` on DGRAM is inherently thread-safe
- **Gated emission**: Metadata ops (getattr/readdir/access) only emitted when `emit_metadata_ops = true`
- **Performance impact**: Negligible when no listener (single failed syscall per op)

### Event JSON Format

**Normal operation** (no fault):
```json
{"ts":1711648000123,"op":"write","path":"/file.txt","off":0,"sz":4096,"res":4096,"fault":null}
```

**Fault event** (error/delay/partial):
```json
{"ts":1711648000456,"op":"write","path":"/file.txt","off":0,"sz":4096,"res":-5,"fault":"error"}
```

**Corruption event** (with byte-level detail):
```json
{"ts":1711648000789,"op":"write","path":"/file.zip","off":1024,"sz":200,"res":200,
 "fault":"corruption","corr":{"n":14,"pos":[3,17,42],"orig":[65,66,67],"new":[254,0,128],"truncated":false}}
```

Fields:
- `ts` — epoch milliseconds (uint64, from `clock_gettime(CLOCK_REALTIME)`)
- `op` — operation name: "read", "write", "create", "truncate", etc.
- `path` — FUSE-relative path (e.g., "/myfile.txt")
- `off` — file offset (0 for non-data ops)
- `sz` — requested size in bytes
- `res` — actual result (bytes transferred, or negative errno)
- `fault` — null, "error", "delay", "partial", or "corruption"
- `corr` — corruption detail object (only present for corruption events):
  - `n` — number of corrupted bytes
  - `pos` — array of byte positions within the buffer
  - `orig` — array of original byte values (0-255)
  - `new` — array of corrupted byte values (0-255)
  - `truncated` — true if detail was capped at MAX_CORRUPTION_TRACK (256)

### API (event_emitter.h)

```c
void event_emitter_init(const char *socket_path);
void event_emitter_cleanup(void);
void event_emit_op(fs_op_type_t op, const char *path, off_t offset, size_t size, int result);
void event_emit_fault(fs_op_type_t op, const char *path, off_t offset, size_t size,
                      const char *fault_type, int fault_result);
void event_emit_corruption(fs_op_type_t op, const char *path, off_t offset, size_t size,
                           const corruption_detail_t *detail);
```

### Corruption Detail Tracking (fault_injector.h)

```c
typedef struct {
    size_t count;
    size_t positions[MAX_CORRUPTION_TRACK];  // MAX_CORRUPTION_TRACK = 256
    unsigned char original[MAX_CORRUPTION_TRACK];
    unsigned char corrupted[MAX_CORRUPTION_TRACK];
} corruption_detail_t;
```

`apply_corruption_fault()` populates this struct during the corruption loop. The caller (`fs_fault_write`) passes it to `event_emit_corruption()`.

### Which Operations Emit Events

Currently only **read** and **write** wrappers emit events (these are the data-path operations relevant to corruption tracking). Other operations (getattr, create, open, etc.) do not emit events unless `emit_metadata_ops` is enabled. This can be extended later.

### Testing

Event emission tests run **inside the target container** via `docker exec` (not the external runner container). The test script `src/fuse-driver/tests/test_event_emission.py` binds the socket, performs local FUSE operations, and validates received events. Two scenarios:
- `event_emission_nofault` — no_faults.conf: validates event format, fields, path, size
- `event_emission_corruption` — corruption_high.conf: validates corruption detail (n, pos, orig, new, positions in range)

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

[management]
event_emission_enabled = true
event_socket_path = /var/run/nas-emu/events.sock
emit_metadata_ops = false
```

## Operation Bitmask

Operations are selected via comma-separated strings: `read,write,open,create,unlink,rmdir,mkdir,rename,truncate,chmod,chown,utimens` or `all` to apply to all operations. Internally converted to bitmask for efficient checking.

## Debugging

1. **Set log_level=3** (DEBUG) in config for maximum logging output, including event emission debug messages.
2. **Check logs**: Review /var/log/nas-emu-fuse.log for operation details, fault triggers, and "Event emitted:" messages.
3. **Verify mount**: Use `mount | grep fuse` or `findmnt -t fuse`.
4. **Check process**: `ps aux | grep nas-emu-fuse`.
5. **Test events manually**: Inside the container, run a Python script that binds `/var/run/nas-emu/events.sock` as a DGRAM socket and `recv()` datagrams while performing file operations on the mount.
6. **Verify fault injection**: Enable high probability fault (0.9+), then test expected failures via logs.

Note: Container entrypoint.sh can override log_level via environment variable NAS_LOG_LEVEL.

## Directory Structure

```
src/fuse-driver/
  Makefile
  nas-emu-fuse.conf
  README-LLM-FUSE.md
  src/
    fs_fault_injector.c   # Main wrapper with priority logic + event emission
    fs_fault_injector.h
    fs_operations.c       # Passthrough operations
    fs_operations.h
    fault_injector.c      # Fault trigger logic + corruption_detail_t
    fault_injector.h
    event_emitter.c       # Unix DGRAM socket event sender
    event_emitter.h       # Event API + corruption_detail_t definition
    config.c              # INI parser + [management] section
    config.h
    log.c                 # Thread-safe logging
    log.h
    fs_common.c           # Operation names, shared types
    fs_common.h
  docker/
    smb.conf              # Samba config template
    entrypoint.sh         # Container startup (SMB + FUSE + mkdir /var/run/nas-emu)
  tests/
    configs/              # 22 fault injection config files
    test_event_emission.py  # Runs inside target container, validates events
    functional/           # Historical bash test scripts (reference only)
```
