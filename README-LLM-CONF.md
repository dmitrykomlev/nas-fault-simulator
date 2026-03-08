# NAS Emulator Configuration System - Context Document

> **Note**: This is a private context document to maintain knowledge continuity in AI assistant conversations about the NAS Emulator configuration system.

## Overview

The NAS Emulator project uses a centralized configuration system to eliminate hardcoded paths and create a single source of truth for all configurable parameters. This document details the configuration architecture, implementation details, and usage patterns.

## Core Configuration Principles

1. **Python Config Dataclass Driven**: Configuration parameters are defined in `nas_sim/config.py` with sensible defaults
2. **Sensible Defaults**: All required parameters have built-in defaults; most users need no configuration
3. **Optional Local Overrides**: Users can create `.env.local` for local-specific overrides (not tracked in git)
4. **Project Root Anchoring**: Configuration loader finds project root by locating `pyproject.toml` file
5. **Flexibility**: Configuration can be overridden at multiple levels (defaults -> `.env.local` -> environment variables -> command-line args)

## Key Configuration Parameters

These core parameters control the system's operation:

| Environment Variable   | Default Value       | Description                             |
|------------------------|---------------------|-----------------------------------------|
| NAS_MOUNT_POINT        | /mnt/nas-mount      | FUSE mount point inside container       |
| NAS_STORAGE_PATH       | /var/nas-storage    | Backing storage path inside container   |
| DEV_HOST_STORAGE_PATH  | ./nas-storage       | Host path for persistent storage        |
| NAS_LOG_FILE           | /var/log/nas-emu.log| Log file path inside container          |
| NAS_LOG_LEVEL          | 2                   | Log level (0=ERROR to 3=DEBUG)          |
| NAS_SMB_PORT           | 1445                | SMB port to expose on host              |

## Directory Structure

The configuration system is organized as follows:

```
/nas-fault-simulator/
├── .env.local                  # Optional local overrides (not tracked in git)
├── pyproject.toml              # Project metadata (marks project root)
├── Dockerfile                  # Multi-stage build using config
├── nas_sim/                    # Python orchestration package
│   ├── __main__.py             # CLI entry point (python -m nas_sim)
│   ├── config.py               # Configuration dataclass and loader
│   ├── build.py                # Build logic
│   ├── run.py                  # Run logic
│   ├── test.py                 # Test orchestration
│   └── ...                     # Other Python modules
├── /src
│   ├── /fuse-driver
│   │   ├── nas-emu-fuse.conf   # FUSE driver configuration file
│   │   ├── /src
│   │   │   ├── config.h        # C configuration header
│   │   │   └── config.c        # C configuration implementation
│   │   └── /tests
│   │       └── /functional
│   │           └── README-LLM-FUNCTIONAL-TESTS.md
├── /tests                      # pytest test code
│   └── test_*.py               # Test modules
└── /nas-storage                # Local storage directory (created at runtime)
```

## Configuration Components

### 1. Python Configuration Loader (`nas_sim/config.py`)

This module defines the configuration dataclass with sensible defaults and provides the `Config.load()` method:

```python
# nas_sim/config.py - Central configuration with defaults

from dataclasses import dataclass
from pathlib import Path
import os

@dataclass
class Config:
    """NAS Emulator configuration with sensible defaults"""
    nas_mount_point: str = "/mnt/nas-mount"
    nas_storage_path: str = "/var/nas-storage"
    nas_log_file: str = "/var/log/nas-emu.log"
    nas_log_level: int = 2
    nas_smb_port: int = 1445
    dev_host_storage_path: str = "./nas-storage"
    config_file: str = None

    @staticmethod
    def find_project_root() -> Path:
        """Find project root by locating pyproject.toml"""
        current = Path.cwd()
        while current != current.parent:
            if (current / "pyproject.toml").exists():
                return current
            current = current.parent
        raise RuntimeError("Could not find project root (pyproject.toml)")

    @classmethod
    def load(cls) -> "Config":
        """Load configuration from defaults, .env.local, and environment"""
        config = cls()
        project_root = cls.find_project_root()

        # Load from .env.local if it exists
        env_local = project_root / ".env.local"
        if env_local.exists():
            # Load environment variables from .env.local
            with open(env_local) as f:
                for line in f:
                    if "=" in line:
                        key, value = line.split("=", 1)
                        os.environ[key.strip()] = value.strip()

        # Override with environment variables if present
        for field in dataclass_fields(config):
            env_var = field.name.upper()
            if env_var in os.environ:
                setattr(config, field.name, os.environ[env_var])

        return config
```

The configuration follows this priority order:
1. Built-in defaults (in Config dataclass fields)
2. Values from `.env.local` (if it exists)
3. Environment variables
4. Command-line arguments (parsed by orchestration scripts)

### 2. Optional Local Overrides (`.env.local`)

Users can create `.env.local` in the project root for local-specific overrides. This file is NOT tracked in git:

```ini
# .env.local - Optional local overrides (not tracked in git)
NAS_SMB_PORT=1446
NAS_LOG_LEVEL=3
```

### 3. C Configuration Module (`config.h`, `config.c`)

These files define the configuration structure and functions for C code:

```c
// config.h
typedef struct {
    char *mount_point;       // Path to FUSE mount point
    char *storage_path;      // Path to backing storage
    char *log_file;          // Path to log file
    int log_level;           // Log level (0-3)

    // Fault injection options (to be expanded later)
    bool enable_fault_injection;  // Master switch for fault injection

    // Config file path (if used)
    char *config_file;       // Path to configuration file
} fs_config_t;

// Initialize configuration with defaults from environment
void config_init(fs_config_t *config);
```

```c
// config.c
void config_init(fs_config_t *config) {
    const char *env_mount_point = getenv("NAS_MOUNT_POINT");
    const char *env_storage_path = getenv("NAS_STORAGE_PATH");
    const char *env_log_file = getenv("NAS_LOG_FILE");
    const char *env_log_level = getenv("NAS_LOG_LEVEL");

    // Set defaults, overridden by environment variables if available
    config->mount_point = strdup(env_mount_point ? env_mount_point : "/mnt/nas-mount");
    config->storage_path = strdup(env_storage_path ? env_storage_path : "/var/nas-storage");
    config->log_file = strdup(env_log_file ? env_log_file : "/var/log/nas-emu.log");
    config->log_level = env_log_level ? atoi(env_log_level) : 2;
    config->enable_fault_injection = false;
    config->config_file = NULL;
}
```

### 4. Docker Configuration

Configuration is passed to Docker containers via environment variables using the Python Docker SDK:

```python
# nas_sim/run.py - Docker container execution with config
import docker
from nas_sim.config import Config

config = Config.load()

client = docker.from_env()
container = client.containers.run(
    "nas-fault-simulator-fuse",
    detach=True,
    privileged=True,
    cap_add=["SYS_ADMIN"],
    devices={"/dev/fuse": "/dev/fuse"},
    ports={"445/tcp": config.nas_smb_port},
    volumes={
        f"{project_root}/nas-storage": {"bind": "/var/nas-storage", "mode": "rw"},
    },
    environment={
        "NAS_MOUNT_POINT": config.nas_mount_point,
        "NAS_STORAGE_PATH": config.nas_storage_path,
        "NAS_LOG_FILE": config.nas_log_file,
        "NAS_LOG_LEVEL": str(config.nas_log_level),
    }
)
```

No docker-compose is used. All orchestration is handled by the Python Docker SDK in `nas_sim/` modules.

## Configuration Flow

1. **Python Config Dataclass** has built-in sensible defaults in `nas_sim/config.py`
2. **Local Overrides** from `.env.local` (if present) override defaults
3. **Environment Variables** can override local file values
4. **Command-line Arguments** override all previous sources when specified
5. **Docker Container** receives configuration values via `-e` environment flags passed by Python Docker SDK
6. **C Code** accesses environment variables via `getenv()` calls in `config.c`
7. **Dynamic Configuration**: Ports and container names allocated automatically by Python orchestration

## Storage Paths Explained

The system uses several important paths:

1. **NAS_MOUNT_POINT** (`/mnt/nas-mount`): 
   - This is the FUSE mount point inside the container
   - All client operations go through this path
   - The FUSE driver intercepts operations at this path

2. **NAS_STORAGE_PATH** (`/var/nas-storage`):
   - This is the actual storage location inside the container
   - The FUSE driver redirects operations to this path
   - This is where data is actually stored

3. **DEV_HOST_STORAGE_PATH** (`./nas-storage`):
   - This is the host path mapped to NAS_STORAGE_PATH
   - Provides persistent storage across container restarts
   - Allows inspection of files from the host system

The data flow follows this path:
```
Client → /mnt/nas-mount (FUSE) → FUSE driver → /var/nas-storage (container) → ./nas-storage (host)
```

## Python Orchestration Commands

The project uses Python modules (invoked via `python -m nas_sim`) to orchestrate all operations:

### python -m nas_sim build
Builds the multi-stage Docker image with FUSE driver compiled inside.
- `--test-image`: Also build the test-runner image
- `--no-cache`: Force rebuild without Docker layer cache

### python -m nas_sim run
Starts a Docker container with FUSE filesystem. Includes logic to:
- Auto-build image if missing
- Stop any existing containers with same name
- Allocate free SMB ports automatically
- Pass configuration parameters via environment variables
- Options:
  - `--config=FILE`: Use specified fault injection config file
  - `--port=PORT`: Use specific SMB port instead of auto-allocation

### python -m nas_sim test
Runs the complete test suite using pytest inside a test-runner container.
- `--filter=PATTERN`: Run only tests matching pattern
- `--verbose`: Show detailed test output
- `--preserve`: Keep container after test failure

### python -m nas_sim stop
Stops the running NAS simulator container.

### python -m nas_sim clean
Cleanup containers, volumes, and networks.
- `--all`: Remove all traces including images

## Troubleshooting Configuration Issues

Common configuration issues and solutions:

### 1. Configuration Not Taking Effect

**Symptoms**: Default values being used instead of expected custom values.

**Solution**:
- Verify `.env.local` file exists in project root (optional, not required)
- Check environment variables: `echo $NAS_SMB_PORT`
- Verify project root was found: `python -c "from nas_sim.config import Config; print(Config.find_project_root())"`
- Check command-line arguments were passed correctly

### 2. Path Access Issues

**Symptoms**: "Permission denied" or "No such file or directory" errors.

**Solution**:
- Check that the storage directory exists: `ls -la ./nas-storage`
- Verify permissions: `chmod -R 755 ./nas-storage`
- Check the paths are correctly mounted in Docker: `docker exec nas-fault-simulator mount`

### 3. Container Volume Mounting Problems

**Symptoms**: Container has correct environment variables but volume mounts are wrong.

**Solution**:
- Check Docker container mounts: `docker inspect CONTAINER_NAME | grep Mounts -A 10`
- Verify storage path is absolute or properly resolved relative to project root
- Stop container and rebuild: `python -m nas_sim stop && python -m nas_sim clean`

### 4. FUSE Mount Issues

**Symptoms**: FUSE mount point exists but files are not visible.

**Solution**:
- Verify FUSE is running: `docker exec nas-fault-simulator ps aux | grep nas-emu-fuse`
- Check FUSE logs: `docker exec nas-fault-simulator cat /var/log/nas-emu.log`
- Check container logs: `docker logs nas-fault-simulator`
- Look for error messages: `docker exec nas-fault-simulator dmesg | tail`
- Verify log level is high enough: `python -m nas_sim run --help` for options

## Future Enhancements

1. **Web UI Configuration**:
   - Web UI will read/write the `.env` file
   - Changes trigger configuration reload via API
   - Real-time validation of configuration values

2. **Dynamic Reconfiguration**:
   - Allow changing some parameters without restart
   - Signal handling for reload operations
   - Configuration versioning and history

3. **Configuration Profiles**:
   - Save/load different configuration sets
   - Predefined profiles for different use cases (high latency, corruption, etc.)
   - Import/export configuration settings

## Port Configuration

The NAS Emulator exposes the SMB port (445) for network access, but this often conflicts with the system's native SMB service. To avoid conflicts:

1. The default host port is set to 1445 instead of 445
2. This is configured via the `NAS_SMB_PORT` configuration parameter (defaults to 1445)
3. Can be overridden via:
   - `.env.local` file: `NAS_SMB_PORT=1446`
   - Environment variable: `export NAS_SMB_PORT=1446`
   - Command-line argument: `python -m nas_sim run --port=1446`

When connecting to the SMB service, use the host port specified by `NAS_SMB_PORT`.

## Configuration Priority Order

When multiple configuration sources are available, this priority order applies:

1. **Command-line arguments** (highest) - Arguments passed to Python orchestration commands
2. **Environment variables** - Set in shell before running Python commands
3. **`.env.local` file** - Optional file in project root
4. **Config dataclass defaults** (lowest) - Built-in defaults in `nas_sim/config.py`

Example:
```bash
# Uses default port 1445
python -m nas_sim run --config=my-config.conf

# Overrides with environment variable
NAS_SMB_PORT=1446 python -m nas_sim run --config=my-config.conf

# Command-line argument takes precedence (if supported)
python -m nas_sim run --config=my-config.conf --port=1447
```

For the FUSE driver itself (C code), configuration comes from:
1. Command-line arguments to `nas-emu-fuse` binary
2. Environment variables passed via Docker
3. Hardcoded defaults in C code

## Critical Configuration Parsing Issues

### Timing Fault Default Behavior (IMPORTANT)

**WARNING**: The timing fault has dangerous default behavior that can cause test failures and system hangs.

**Problem**: When a config file contains a `[timing_fault]` section, the parser automatically enables timing faults with these defaults:
- `enabled = true` (ALWAYS enabled when section exists)
- `after_minutes = 5` (triggers after 5 minutes)
- `operations_mask = 0xFFFFFFFF` (affects ALL filesystem operations)

**Effect**: After 5 minutes of operation, ALL filesystem operations start failing with I/O errors (-5), making the filesystem completely inaccessible.

**Root Cause**: In `config.c` lines 152-158, the parser sets `enabled = true` as the default when creating the timing fault structure, regardless of what the config file specifies.

**Correct Configuration**:
```ini
[timing_fault]
enabled = false       # Must use 'enabled', not 'probability'
after_minutes = 5
operations = all
```

**Wrong Configuration** (will cause hangs):
```ini
[timing_fault] 
probability = 0.0     # IGNORED! Parser doesn't recognize 'probability' for timing faults
```

### Configuration Key Mismatch Issues

Different fault types use different configuration keys:

**Timing Faults** use:
- `enabled` (boolean) - NOT `probability`
- `after_minutes` (integer)
- `operations` (string)

**Other Faults** (corruption, error, delay) use:
- `probability` (float 0.0-1.0)
- Various type-specific parameters
- `operations` (string)

**Debugging Tips**:
1. Check logs for "Timing fault: [operation] triggered after X.X minutes" 
2. If filesystem becomes unresponsive after ~5 minutes, timing faults are likely enabled
3. Verify config uses correct key names for each fault type
4. Remember: section existence alone can enable timing faults with defaults

### Config Parser Behavior

The parser creates fault structures when it encounters section headers `[fault_type]`, and sets potentially dangerous defaults before parsing the section contents. This means:

1. **Empty sections enable faults**: Just having `[timing_fault]` enables timing faults
2. **Wrong keys are ignored**: Using `probability` instead of `enabled` leaves defaults active
3. **Silent failures**: No warnings when config keys are unrecognized

This behavior affects production testing and can cause unexpected test failures or system hangs.