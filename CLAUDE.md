# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Required Reading
When starting work on this project, always read these files first to understand the project context:
- README-LLM.md - Overall project architecture, goals, and current implementation status
- README-LLM-CONF.md - Configuration system details, environment variables, and known configuration issues
- src/fuse-driver/README-LLM-FUSE.md - FUSE driver implementation, fault injection capabilities, and debugging
- src/fuse-driver/tests/functional/README-LLM-FUNCTIONAL-TESTS.md - Test architecture, frameworks, and current test status

## Auto-read Command
Run this command to quickly read all project documentation:
```bash
find . -name "README-LLM*.md" -exec echo "=== {} ===" \; -exec cat {} \;
```

## Build & Test Commands
- Build Docker image: `./scripts/build.sh`
- Run FUSE filesystem: `./scripts/run-fuse.sh --config=CONFIG_FILE`
- Run all tests: `./scripts/run_tests.sh`
- Run tests with debugging: `PRESERVE_ON_FAILURE=true ./scripts/run_tests.sh`
- Run single test: `bash ./src/fuse-driver/tests/functional/test_name.sh`
- Simple end-user runner: `./run-nas-simulator.sh --config=CONFIG_FILE`
- Stop container: `docker stop CONTAINER_NAME`

## Build System
- **Pure Docker approach**: No docker-compose, uses `docker run` for all operations
- **Multi-stage Docker build**: FUSE driver compiled in builder stage, runtime image with no build tools
- **Automatic rebuild detection**: Tests check source modification times vs image timestamp
- **Clean host**: No build artifacts remain on host filesystem
- **Dynamic ports**: SMB ports allocated automatically to avoid conflicts
- **Container isolation**: Each test uses unique container name (`nas-fault-simulator-${test_name}`)
- **Resource cleanup**: Failed containers cleaned up by default to prevent cascade failures

## Code Style Guidelines
- Language: C for FUSE driver implementation
- Naming: snake_case for functions/variables, UPPER_CASE for constants
- Function prefixes: fs_op_* (filesystem ops), log_* (logging), config_* (configuration)
- Error handling: Return negative errno values, log errors, check permissions
- Memory management: Free resources in error paths
- Indentation: 4 spaces
- Comments: Function-level documentation describing purpose and parameters
- Modularity: Separate core logic (filesystem ops, fault injection, logging, config)
- Logging: Use LOG_DEBUG/INFO/WARN/ERROR macros with appropriate level

## Environment
- Development in Docker container
- Configuration via environment variables and config files

## Recent Improvements (2025-07-03)
- **Docker Architecture Migration**: Migrated from docker-compose to pure Docker approach
- **Container Cleanup Fixes**: Fixed cascade test failures by ensuring proper cleanup on all failure scenarios
- **Test Framework Reliability**: Added early cleanup in test framework for SMB mount failures, container startup failures
- **Resource Conflict Prevention**: Changed default behavior to cleanup failed containers, use PRESERVE_ON_FAILURE=true for debugging
- **Legacy File Cleanup**: Removed obsolete docker-compose files and unused mount/unmount scripts
- **End-User Experience**: Added simple run-nas-simulator.sh script for future web interface integration