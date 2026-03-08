"""Pytest fixtures for NAS Fault Simulator two-container tests.

These fixtures run INSIDE the test-runner container (container 2).
SMB_HOST points to the target container on the shared Docker network.
"""

import os

import pytest

from tests.smb_helpers import mount_smb, unmount_smb, wait_for_smb


# Read environment variables (set by orchestrator)
SMB_HOST = os.environ.get("SMB_HOST", "target")
SMB_PORT = int(os.environ.get("SMB_PORT", "445"))
SMB_SHARE = os.environ.get("SMB_SHARE", "nasshare")
SMB_USERNAME = os.environ.get("SMB_USERNAME", "nasusr")
SMB_PASSWORD = os.environ.get("SMB_PASSWORD", "naspass")
SMB_MOUNT_PATH = os.environ.get("SMB_MOUNT", "/mnt/smb")
RAW_STORAGE_PATH = os.environ.get("RAW_STORAGE", "/var/nas-storage")
TEST_CONFIG = os.environ.get("TEST_CONFIG", "")

# Track whether mount succeeded
_mount_ok = False


@pytest.fixture(scope="session")
def smb_mount():
    """Mount the SMB share once per session, unmount at teardown."""
    global _mount_ok

    # Wait for target container's SMB to be ready
    if not wait_for_smb(SMB_HOST, SMB_PORT, SMB_USERNAME, SMB_PASSWORD, timeout=30):
        pytest.skip(
            f"SMB service at {SMB_HOST}:{SMB_PORT} did not become ready in 30s"
        )

    try:
        mount_smb(SMB_HOST, SMB_PORT, SMB_SHARE, SMB_USERNAME, SMB_PASSWORD, SMB_MOUNT_PATH)
        _mount_ok = True
    except RuntimeError as exc:
        pytest.skip(f"SMB mount failed (expected for 100%% error configs): {exc}")

    yield SMB_MOUNT_PATH

    if _mount_ok:
        unmount_smb(SMB_MOUNT_PATH)


@pytest.fixture
def smb_path(smb_mount):
    """Convenience fixture returning the SMB mount path."""
    return smb_mount


@pytest.fixture
def raw_storage():
    """Path to the shared Docker volume (raw storage backdoor)."""
    return RAW_STORAGE_PATH


@pytest.fixture
def test_config():
    """The config file name for the current test scenario."""
    return TEST_CONFIG
