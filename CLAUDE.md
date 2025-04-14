# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands
- Build FUSE driver: `./scripts/build-fuse.sh` 
- Run FUSE filesystem: `./scripts/run-fuse.sh`
- Run all tests: `./scripts/run_tests.sh`
- Run single test: `docker-compose exec fuse-dev bash -c "cd /app/src/fuse-driver/tests/functional && ./test_basic_ops.sh"`

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