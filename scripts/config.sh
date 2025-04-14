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