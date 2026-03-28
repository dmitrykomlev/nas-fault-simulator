# NAS Fault Simulator - LLM Context Document

This document provides AI assistants with a quick overview of the nas-fault-simulator project for efficient context continuity in development conversations.

## Project Overview

NAS Fault Simulator is a testing tool that simulates failure modes in Network Attached Storage systems. It enables QA and development teams to reproduce difficult-to-replicate failures: silent data corruption, network disruptions, timing-based failures, and permission-related issues. The simulator appears as a standard SMB network share with configurable fault injection at the FUSE filesystem layer.

## Architecture

Two-container Docker model:
- **Target container**: Runs FUSE driver + Samba SMB server
- **Runner container**: Executes pytest test suite against target via SMB mount

Data flow: Client -> SMB (1445) -> FUSE mount (/mnt/nas-mount) -> fault injection engine -> backing storage (/var/nas-storage).

Event flow (new): FUSE operation -> `event_emitter.c` -> Unix DGRAM socket `/var/run/nas-emu/events.sock` -> Management service (planned).

## Project Structure

```
nas-fault-simulator/
├── CLAUDE.md, README-LLM.md
├── Dockerfile, Dockerfile.test, VERSION, pyproject.toml
├── .gitattributes                          # CRLF handling
├── nas_sim/                                # Python orchestration package
│   ├── cli.py, config.py, build.py, run.py, test.py
│   ├── containers.py, docker_utils.py, port_utils.py, console.py
├── tests/                                  # pytest test suite (runs in runner container)
│   ├── conftest.py, smb_helpers.py, validation.py
│   ├── test_basic_ops.py, test_large_file.py
│   ├── test_corruption.py, test_errors.py
│   ├── test_delay.py, test_partial.py
│   ├── test_opcount.py, test_timing.py
├── src/fuse-driver/                        # C FUSE driver
│   ├── README-LLM-FUSE.md
│   ├── nas-emu-fuse.conf                   # Default configuration
│   ├── src/                                # C source code
│   │   ├── fs_fault_injector.c, fs_operations.c, fs_common.c
│   │   ├── fault_injector.c, config.c, log.c
│   │   ├── event_emitter.c                 # NEW: event emission to Unix socket
│   │   └── corresponding .h files
│   ├── docker/                             # Docker configs
│   │   ├── smb.conf, entrypoint.sh
│   └── tests/
│       ├── configs/                        # Test configuration files (22 configs)
│       ├── test_event_emission.py          # Runs inside target container via exec
│       └── functional/                     # Historical bash tests (reference only)
├── src/management/                         # PLANNED: Flask management service
└── .github/workflows/                      # CI/CD (ci.yml, release.yml)
```

## Configuration

Configuration defaults live in `nas_sim/config.py` (Config dataclass). Optional `.env.local` file overrides defaults (not tracked in git).

FUSE driver configuration files in `src/fuse-driver/tests/configs/` use INI format with sections for fault types. Example:
```ini
[corruption_fault]
probability = 0.7
percentage = 50
operations = write

[management]
event_emission_enabled = true
event_socket_path = /var/run/nas-emu/events.sock
emit_metadata_ops = false
```

**KNOWN GOTCHA: Timing fault defaults** -- Section existence alone (`[timing_fault]`) enables timing faults with dangerous defaults (triggers after 5 minutes, affects ALL operations). Requires `enabled = false` to disable.

**KNOWN GOTCHA: Config key naming inconsistency** -- Timing faults use `enabled` (boolean), other faults use `probability` (float 0.0-1.0).

## Test System

25 test scenarios organized across eight groups:

**Basic Operations** (2 scenarios): File/directory operations, large file handling
**Corruption** (5 scenarios): Probability + data percentage validation, corner cases
**Error Injection** (7 scenarios): EIO/EACCES/ENOSPC with configurable probability
**Delay** (3 scenarios): Write delay, read+write delay, probabilistic delay
**Partial** (3 scenarios): Partial write, partial read, probabilistic partial
**Operation Count** (2 scenarios): Every-N-ops on write, every-N-ops on all
**Timing** (1 scenario): 1-minute threshold on writes
**Event Emission** (2 scenarios): Event format/fields/corruption details (run inside target container)

Two test models:
- **Two-container model**: Target (FUSE+Samba) serves requests; runner (pytest) mounts SMB and tests. Used for fault injection tests.
- **Exec-inside-target model**: Python test script runs inside target container via `docker exec`. Used for internal IPC tests (event emission).

Run tests: `python -m nas_sim test [--filter=X] [--verbose] [--preserve]`

**Important**: SMB error masking -- SMB layer retries failed FUSE operations, masking approximately 95% of FUSE-level errors from clients. This shows "user experience" rather than raw fault injection rates.

## Event Emission System (Phase 1 Complete)

The FUSE driver emits structured JSON events for every read/write operation and fault trigger via a non-blocking Unix DGRAM socket at `/var/run/nas-emu/events.sock`.

**Event format** (one JSON object per datagram):
```json
{"ts":1711648000123,"op":"write","path":"/file.txt","off":0,"sz":4096,"res":4096,"fault":null}
```

Corruption events include byte-level detail:
```json
{"ts":...,"op":"write","path":"/file.zip","off":1024,"sz":200,"res":200,"fault":"corruption",
 "corr":{"n":40,"pos":[3,17,42,...],"orig":[65,66,67,...],"new":[254,0,128,...],"truncated":false}}
```

**Key design**: Non-blocking `sendto()` on DGRAM socket — if no listener, events are silently dropped (no impact on FUSE performance). Metadata ops (getattr/readdir) gated behind `emit_metadata_ops` config flag.

See `src/fuse-driver/README-LLM-FUSE.md` for implementation details.

## Management Layer (In Progress)

A Flask-based management service is being built to consume FUSE events and provide:
- REST API for metrics, file tracking, corruption maps
- Web UI with dashboard, file list, per-file corruption visualization
- FUSE process management (stop/restart/health)

See `.claude/plans/ticklish-snuggling-turing.md` for the full implementation plan with phases 2-5.

## Known Issues / Gotchas

1. **SMB error masking** -- SMB layer retries failed operations; 50% FUSE error rate becomes ~5-7% at test level
2. **Timing fault defaults** -- Section existence enables timing faults with dangerous 5-minute trigger; use `enabled = false` explicitly
3. **Config key naming** -- Timing uses `enabled`, others use `probability`; mixing them silently fails
4. **CRLF handling** -- .gitattributes handles cross-platform line endings; C config parser defends against both
5. **Log level override** -- entrypoint.sh `--loglevel` flag overrides config file setting; use `NAS_LOG_LEVEL` env var for debugging
6. **Docker SDK exec_run hangs** -- Docker Python SDK `exec_run`/`exec_start` can hang with some Docker daemon configs. Orchestrator uses `subprocess.run(["docker", "exec", ...])` instead for exec-based tests.
7. **Corruption medium test flaky** -- `corruption_medium` scenario can fail due to statistical variance with only 30 samples (observed 33% vs 35% threshold). Pre-existing, not a regression.

## Implementation Status

**Completed:**
- FUSE driver core with all filesystem operations (17 ops)
- Fault injection: error, corruption, timing, operation count, delay, partial
- Event emission system: Unix DGRAM socket, JSON events, corruption byte-level detail
- Python orchestration package (build, run, test, stop, clean)
- pytest test suite with 25 scenarios covering all fault types + event emission
- Docker multi-stage build and two-container test model
- Exec-inside-target test model for internal IPC tests
- Configuration system with defaults, .env.local overrides, and [management] section

**In Progress (Phase 2 next):**
- Management service backend (Flask + SQLite + EventReceiver)
- REST API endpoints for stats, files, corruption maps, FUSE control
- Unit tests (no Docker required, prepopulated SQLite)

**TODO (Phases 3-5):**
- Web UI: Dashboard, file list, FUSE control page
- File corruption map: Canvas-based visualization, hex dump, event timeline
- Docker integration: Management service in container, port 8080 exposure
- End-to-end integration tests
