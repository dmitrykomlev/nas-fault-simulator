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

## Build & Test Commands (Python orchestration)

Prerequisites: Python 3.9+, Docker, `pip install docker`

- Build production image: `python -m nas_sim build`
- Build test-runner image too: `python -m nas_sim build --test-image`
- Build without cache: `python -m nas_sim build --no-cache`
- Run FUSE+Samba container: `python -m nas_sim run --config=CONFIG_FILE`
- Run on specific port: `python -m nas_sim run --config=CONFIG_FILE --port=1446`
- Stop container: `python -m nas_sim stop`
- Run full test suite: `python -m nas_sim test`
- Run filtered tests: `python -m nas_sim test --filter=corruption`
- Run tests verbose: `python -m nas_sim test --verbose`
- Preserve on failure: `python -m nas_sim test --preserve`
- Cleanup everything: `python -m nas_sim clean --all`
- Show version: `python -m nas_sim version`

## Build System
- **Python + Docker SDK**: Cross-platform orchestration (replaces bash scripts)
- **Two-container test model**: Target (FUSE+Samba) + Runner (pytest) on Docker network
- **Pure Docker approach**: No docker-compose, uses Docker SDK for all operations
- **Multi-stage Docker build**: FUSE driver compiled in builder stage, runtime image with no build tools
- **Clean host**: No build artifacts, no host SMB mounts required
- **Dynamic ports**: SMB ports allocated automatically to avoid conflicts
- **Container isolation**: Each test scenario gets unique container names and volumes
- **Resource cleanup**: Containers/volumes/networks cleaned up after each scenario

## Code Style Guidelines
- Language: C for FUSE driver implementation, Python for orchestration/tests
- C naming: snake_case for functions/variables, UPPER_CASE for constants
- C function prefixes: fs_op_* (filesystem ops), log_* (logging), config_* (configuration)
- Python: standard PEP 8, type hints where helpful
- Error handling: Return negative errno values (C), exceptions (Python)
- Indentation: 4 spaces (both C and Python)

## Project Structure
- `nas_sim/` - Python orchestration package (build, run, test commands)
- `tests/` - pytest test code that runs inside test-runner container
- `src/fuse-driver/` - C FUSE driver source code
- `src/fuse-driver/tests/configs/` - Fault injection config files
- `src/fuse-driver/tests/functional/` - Historical bash test scripts (reference)
- `.github/workflows/` - CI/CD pipelines

## Environment
- Development on any OS with Docker + Python 3.9+
- Configuration via .env file and config files
- Docker containers handle all FUSE/SMB operations
