"""Operation count fault injection tests.

Tests verify that the operation count fault triggers failures after
every N operations. The counter tracks ALL FUSE calls (getattr, open,
write, release, etc.), not just the targeted operation type.

NOTE: SMB retries mask many failures, so tests use generous tolerances.
The key assertion is that some operations fail -- proving the count-based
trigger fires.
"""

import os
import time

import pytest

NUM_OPS = 20


def _write_file(path: str, data: str) -> bool:
    """Try to write a file. Return True on success, False on error."""
    try:
        with open(path, "w") as f:
            f.write(data)
        return True
    except OSError:
        return False


def _read_file(path: str) -> bool:
    """Try to read a file. Return True on success, False on error."""
    try:
        with open(path, "r") as f:
            f.read()
        return True
    except OSError:
        return False


class TestOpcountEvery5Write:
    """opcount_every5_write.conf -- fail every 5th write operation."""

    def test_opcount_every5_write(self, smb_path):
        results = []
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"opcount_5w_{i}.txt")
            results.append(_write_file(p, "opcount test data"))
            time.sleep(0.05)

        failures = sum(1 for r in results if not r)
        # Every 5th FUSE operation fails. A single file write triggers
        # multiple FUSE calls (getattr, open, write, release), so the
        # fault fires more often than 1-in-5 files. SMB retries mask
        # some. Expect at least some failures.
        assert failures > 0, (
            f"No write failures with every-5th-op fault "
            f"({failures}/{NUM_OPS})"
        )

    def test_opcount_every5_write_reads_unaffected(self, smb_path):
        """Read operations should not be affected by write-only config."""
        # Create files (some may fail, retry)
        fpath = os.path.join(smb_path, "opcount_5w_read_test.txt")
        for _ in range(10):
            if _write_file(fpath, "read test"):
                break
        else:
            pytest.skip("Could not create test file")

        for _ in range(10):
            assert _read_file(fpath), "Read failed unexpectedly"


class TestOpcountEvery3All:
    """opcount_every3_all.conf -- fail every 3rd operation on all ops."""

    def test_opcount_every3_all(self, smb_path):
        results = []
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"opcount_3a_{i}.txt")
            results.append(_write_file(p, "opcount all test"))
            time.sleep(0.05)

        failures = sum(1 for r in results if not r)
        # Every 3rd FUSE call fails across all op types.
        # Very aggressive -- expect significant failures.
        assert failures > 0, (
            f"No failures with every-3rd-op fault on all ops "
            f"({failures}/{NUM_OPS})"
        )
