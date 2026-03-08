# NAS Fault Simulator - LLM Context Document

This document provides AI assistants with a quick overview of the nas-fault-simulator project for efficient context continuity in development conversations.

## Project Overview

NAS Fault Simulator is a testing tool that simulates failure modes in Network Attached Storage systems. It enables QA and development teams to reproduce difficult-to-replicate failures: silent data corruption, network disruptions, timing-based failures, and permission-related issues. The simulator appears as a standard SMB network share with configurable fault injection at the FUSE filesystem layer.

## Architecture

Two-container Docker model:
- **Target container**: Runs FUSE driver + Samba SMB server
- **Runner container**: Executes pytest test suite against target via SMB mount

Data flow: Client -> SMB (1445) -> FUSE mount (/mnt/nas-mount) -> fault injection engine -> backing storage (/var/nas-storage).

## Project Structure

```
nas-fault-simulator/
├── CLAUDE.md, README-LLM.md
├── Dockerfile, Dockerfile.test, VERSION, pyproject.toml
├── .gitattributes                          # CRLF handling
├── nas_sim/                                # Python orchestration package
│   ├── cli.py, config.py, build.py, run.py, test.py
│   ├── containers.py, docker_utils.py, port_utils.py, console.py
├── tests/                                  # pytest test suite
│   ├── conftest.py, smb_helpers.py, validation.py
│   ├── test_basic_ops.py, test_large_file.py
│   ├── test_corruption.py, test_errors.py
├── src/fuse-driver/                        # C FUSE driver
│   ├── README-LLM-FUSE.md
│   ├── nas-emu-fuse.conf                   # Default configuration
│   ├── src/                                # C source code
│   │   ├── fs_fault_injector.c, fs_operations.c, fs_common.c
│   │   ├── fault_injector.c, config.c, log.c
│   │   └── corresponding .h files
│   ├── docker/                             # Docker configs
│   │   ├── smb.conf, entrypoint.sh
│   └── tests/
│       ├── configs/                        # Test configuration files
│       │   ├── no_faults.conf, corruption_*.conf, error_*.conf
│       └── functional/                     # Historical bash tests (reference only)
└── .github/workflows/                      # CI/CD (ci.yml, release.yml)
```

## Configuration

Configuration defaults live in `nas_sim/config.py` (Config dataclass). Optional `.env.local` file overrides defaults (not tracked in git).

FUSE driver configuration files in `src/fuse-driver/tests/configs/` use INI format with sections for fault types. Example:
```ini
[corruption_fault]
probability = 0.7
data_percent = 50
operations = write
```

**KNOWN GOTCHA: Timing fault defaults** -- Section existence alone (`[timing_fault]`) enables timing faults with dangerous defaults (triggers after 5 minutes, affects ALL operations). Requires `enabled = false` to disable.

**KNOWN GOTCHA: Config key naming inconsistency** -- Timing faults use `enabled` (boolean), other faults use `probability` (float 0.0-1.0).

## Test System

14 test scenarios organized across two categories:

**Basic Operations** (2 scenarios):
- File/directory operations via SMB
- Large file handling and integrity

**Fault Injection** (12 scenarios):
- Corruption tests (5): probability + data corruption percentage validation
- Error injection tests (7): read/write/create/access/nospace errors with configurable probability

Two-container model: target container (FUSE+Samba) serves requests; runner container (pytest) mounts SMB and executes tests.

Run tests: `python -m nas_sim test [--filter=X] [--verbose] [--preserve]`

**Important**: SMB error masking -- SMB layer retries failed FUSE operations, masking approximately 95% of FUSE-level errors from clients. This shows "user experience" rather than raw fault injection rates.

Historical bash tests in `src/fuse-driver/tests/functional/` are reference only (not maintained).

## Known Issues / Gotchas

1. **SMB error masking** -- SMB layer retries failed operations; 50% FUSE error rate becomes ~5-7% at test level
2. **Timing fault defaults** -- Section existence enables timing faults with dangerous 5-minute trigger; use `enabled = false` explicitly
3. **Config key naming** -- Timing uses `enabled`, others use `probability`; mixing them silently fails
4. **CRLF handling** -- .gitattributes handles cross-platform line endings; C config parser defends against both
5. **Log level override** -- entrypoint.sh `--loglevel` flag overrides config file setting; use `NAS_LOG_LEVEL` env var for debugging

## Implementation Status

**Completed:**
- FUSE driver core with all filesystem operations
- Fault injection: error, corruption, timing, operation count, delay, partial operations
- Python orchestration package (build, run, test, stop, clean)
- pytest test suite with 14 scenarios covering corruption and error faults
- Docker multi-stage build and two-container test model
- Configuration system with defaults and .env.local overrides

**TODO:**
- Delay and timing-based fault test scenarios
- Partial operation fault test scenarios
- Operation count fault test scenarios
- Performance monitoring and metrics
- REST API for configuration and monitoring
- Web dashboard
