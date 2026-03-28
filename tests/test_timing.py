"""Timing fault injection tests.

Timing faults trigger failures after a configured number of minutes
of runtime. Tests verify:
1. Operations succeed before the threshold
2. Operations fail after the threshold

NOTE: Uses after_minutes=1 (minimum supported value). The test waits
for the threshold to pass, making this the slowest test scenario (~70s).
"""

import os
import time

NUM_OPS = 10


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


class TestTiming1minWrite:
    """timing_1min_write.conf -- fail writes after 1 minute."""

    def test_timing_1min_write(self, smb_path):
        # Phase 1: operations should succeed (within first minute)
        early_results = []
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"timing_1m_{i}.txt")
            early_results.append(_write_file(p, "early write"))

        early_ok = sum(1 for r in early_results if r)
        assert early_ok > 0, "Writes failed before timing threshold"

        # Phase 2: wait well past 1-minute threshold from FUSE start.
        # FUSE driver starts when container launches (~5-10s before tests).
        # Use 65s to ensure we're past the 1-minute mark from driver init.
        time.sleep(65)

        # Phase 3: operations should now fail
        late_results = []
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"timing_1m_late_{i}.txt")
            late_results.append(_write_file(p, "late write"))
            time.sleep(0.05)

        late_failures = sum(1 for r in late_results if not r)
        # After threshold, every write FUSE call fails with EIO.
        # SMB retries also fail (timing fault is persistent after threshold).
        assert late_failures > 0, (
            f"No write failures after timing threshold "
            f"({late_failures}/{NUM_OPS})"
        )

        # Phase 4: verify reads still work (write-only config)
        fpath = os.path.join(smb_path, f"timing_1m_0.txt")
        assert _read_file(fpath), "Read failed after timing threshold"
