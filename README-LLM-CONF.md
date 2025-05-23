# NAS Emulator Configuration System - Context Document

> **Note**: This is a private context document to maintain knowledge continuity in AI assistant conversations about the NAS Emulator configuration system.

## Overview

The NAS Emulator project uses a centralized configuration system to eliminate hardcoded paths and create a single source of truth for all configurable parameters. This document details the configuration architecture, implementation details, and usage patterns.

## Core Configuration Principles

1. **Single Source of Truth**: All configuration parameters are defined in a central `.env` file
2. **Environment Variable Driven**: Configuration is primarily controlled through environment variables
3. **Sensible Defaults**: When environment variables are not specified, sensible defaults are used
4. **Propagation to Components**: Configuration is consistently propagated to all components (shell scripts, C code, Docker)
5. **Flexibility**: Configuration can be overridden at multiple levels (env vars, command line, config files)

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
├── .env                        # Primary configuration file
├── .env.local                  # Optional local overrides (not tracked in git)
├── /scripts
│   ├── config.sh               # Shell configuration loader
│   ├── build-fuse.sh           # Build script using config
│   ├── run-fuse.sh             # Run script using config
│   └── run_tests.sh            # Test script using config
├── /src
│   ├── /fuse-driver
│   │   ├── nas-emu-fuse.conf   # FUSE driver configuration file
│   │   ├── /src
│   │   │   ├── config.h        # C configuration header
│   │   │   └── config.c        # C configuration implementation
│   │   └── /tests
│   │       └── /functional
│   │           └── test_helpers.sh  # Test helpers using config
└── docker-compose.yml          # Docker composition using config
```

## Configuration Components

### 1. Environment File (`.env`)

This is the primary configuration file containing all environment variables:

```ini
# NAS Emulator Core Configuration
NAS_MOUNT_POINT=/mnt/nas-mount
NAS_STORAGE_PATH=/var/nas-storage
NAS_LOG_FILE=/var/log/nas-emu.log
NAS_LOG_LEVEL=2
NAS_SMB_PORT=1445
DEV_HOST_STORAGE_PATH=./nas-storage
```

### 2. Shell Configuration Loader (`config.sh`)

This script loads configuration from the environment file and makes it available to shell scripts:

```bash
#!/bin/bash
# config.sh - Central configuration loader for shell scripts

# Find the project root directory (where .env lives)
find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.env" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "Error: Could not find project root with .env file" >&2
  return 1
}

PROJECT_ROOT="$(find_project_root)"
if [[ $? -ne 0 ]]; then
  echo "Failed to locate project root directory" >&2
  exit 1
fi

# Load default configuration
set -a  # Automatically export all variables
source "$PROJECT_ROOT/.env"
set +a

# Override with environment variables if present
if [[ -f "$PROJECT_ROOT/.env.local" ]]; then
  set -a
  source "$PROJECT_ROOT/.env.local"
  set +a
fi

# Make paths available as shell variables without prefix if needed
MOUNT_POINT="${NAS_MOUNT_POINT}"
STORAGE_PATH="${NAS_STORAGE_PATH}"
LOG_FILE="${NAS_LOG_FILE}"
LOG_LEVEL="${NAS_LOG_LEVEL}"
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

The Docker Compose file uses environment variables for consistent configuration:

```yaml
version: '3'

services:
  fuse-dev:
    build:
      context: .
      dockerfile: src/fuse-driver/docker/Dockerfile.dev
    privileged: true  # Needed for FUSE
    cap_add:
      - SYS_ADMIN
    devices:
      - /dev/fuse:/dev/fuse
    security_opt:
      - apparmor:unconfined
    volumes:
      - .:/app
      # Don't pre-mount anything at the FUSE mount point
      - ${DEV_HOST_STORAGE_PATH:-./nas-storage}:${NAS_STORAGE_PATH:-/var/nas-storage}
    env_file:
      - .env
    environment:
      - NAS_MOUNT_POINT=${NAS_MOUNT_POINT:-/mnt/nas-mount}
      - NAS_STORAGE_PATH=${NAS_STORAGE_PATH:-/var/nas-storage}
      - NAS_LOG_FILE=${NAS_LOG_FILE:-/var/log/nas-emu.log}
      - NAS_LOG_LEVEL=${NAS_LOG_LEVEL:-2}
    ports:
      - "${NAS_SMB_PORT:-1445}:445"   # SMB port (for future SMB server)
```

## Configuration Flow

1. **Environment Variables** are defined in `.env` and loaded by Docker Compose
2. **Docker Container** receives these variables and shares them with all processes
3. **Shell Scripts** source `config.sh` to obtain configuration values
4. **C Code** accesses environment variables via `getenv()` calls in `config.c`
5. **Command-line Arguments** can override environment variables when specified
6. **Local Environment Overrides** in `.env.local` (if present) take precedence over `.env`

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

## Script Configuration Usage

The project provides several scripts that leverage the configuration system:

### build-fuse.sh
Builds the FUSE driver inside the Docker container, using the configured paths.

### run-fuse.sh
Mounts the FUSE filesystem, using the configured mount point and storage path. It includes logic to:
- Check if the FUSE filesystem is already mounted
- Detect and handle stale mounts
- Create the mount point directory if needed
- Pass the configuration parameters to the FUSE driver

### run_tests.sh
Runs the functional tests, ensuring the FUSE driver is built and mounted correctly first.

## Troubleshooting Configuration Issues

Common configuration issues and solutions:

### 1. Missing Environment Variables

**Symptoms**: Default values being used instead of expected custom values.

**Solution**:
- Check the `.env` file exists in the project root
- Ensure all required variables are defined
- Verify `docker-compose.yml` is loading the env file with `env_file: - .env`

### 2. Path Access Issues

**Symptoms**: "Permission denied" or "No such file or directory" errors.

**Solution**:
- Check that the directories exist: `mkdir -p ${NAS_STORAGE_PATH}`
- Verify permissions: `chmod -R 755 ${NAS_STORAGE_PATH}`
- Check the paths are correctly mounted in Docker: `docker-compose exec fuse-dev mount`

### 3. Docker Volume Mounting Problems

**Symptoms**: Container has correct environment variables but volume mounts are wrong.

**Solution**:
- Use absolute paths instead of relative paths in `.env`
- Recreate the container: `docker-compose down && docker-compose up -d`
- Check Docker volume mounts: `docker inspect container_name | grep Mounts -A 10`

### 4. FUSE Mount Issues

**Symptoms**: FUSE mount point exists but files are not visible.

**Solution**:
- Verify FUSE is running: `docker-compose exec fuse-dev ps aux | grep nas-emu-fuse`
- Check FUSE logs: `docker-compose exec fuse-dev cat ${NAS_LOG_FILE}`
- Manually mount FUSE: `docker-compose exec fuse-dev /app/src/fuse-driver/nas-emu-fuse "${NAS_MOUNT_POINT}" -f -d`
- Look for error messages: `docker-compose exec fuse-dev dmesg | tail`

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
2. This is configured via the `NAS_SMB_PORT` environment variable
3. The mapping is defined in `docker-compose.yml` as `"${NAS_SMB_PORT:-1445}:445"`

When connecting to the SMB service, use the host port specified in `NAS_SMB_PORT`.

## Command-Line Overrides

The FUSE driver accepts command-line arguments to override configuration:

```bash
nas-emu-fuse /mnt/nas-mount \
  --storage=/var/custom-storage \
  --log=/var/log/custom.log \
  --loglevel=3 \
  --config=/etc/nas-emu/custom.conf
```

The priority order is:
1. Command-line arguments (highest)
2. Environment variables from `.env.local`
3. Environment variables from `.env`
4. Configuration file values
5. Hardcoded defaults (lowest)

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