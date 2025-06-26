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