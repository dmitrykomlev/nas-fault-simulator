"""Delay fault injection tests.

Each test class corresponds to one delay config scenario.
Tests measure operation timing to verify that delay faults add observable
latency. SMB overhead adds some baseline latency, so thresholds account
for that.

NOTE: Delay on 'all' operations is impractical -- every FUSE call (getattr,
open, write, release) gets delayed, making a single file write take 4x the
delay. Tests target specific operations (read, write) instead.
"""

import os
import time

NUM_OPS = 5


def _timed_write(path: str, data: str) -> float:
    """Write a file and return elapsed time in seconds."""
    start = time.monotonic()
    with open(path, "w") as f:
        f.write(data)
    return time.monotonic() - start


def _timed_read(path: str) -> float:
    """Read a file and return elapsed time in seconds."""
    start = time.monotonic()
    with open(path, "r") as f:
        f.read()
    return time.monotonic() - start


class TestDelayWriteMedium:
    """delay_write_medium.conf -- 100% 200ms delay on writes."""

    def test_delay_write_medium(self, smb_path):
        data = "Test data for delay injection."
        times = []
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"delay_wm_{i}.txt")
            times.append(_timed_write(p, data))

        avg = sum(times) / len(times)
        # 200ms FUSE delay on write; SMB may batch but average should
        # be noticeably above baseline (~0.05s without faults)
        assert avg > 0.15, (
            f"Average write time {avg:.3f}s too fast for 200ms delay "
            f"(times: {[f'{t:.3f}' for t in times]})"
        )

    def test_delay_write_medium_reads_unaffected(self, smb_path):
        """Reads should not be delayed by write-only delay config."""
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"delay_wm_read_{i}.txt")
            with open(p, "w") as f:
                f.write("read test data")

        times = []
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"delay_wm_read_{i}.txt")
            times.append(_timed_read(p))

        avg = sum(times) / len(times)
        assert avg < 0.3, (
            f"Average read time {avg:.3f}s too slow -- delay leaking to reads?"
        )


class TestDelayReadWrite:
    """delay_read_write.conf -- 100% 200ms delay on read+write."""

    def test_delay_read_write(self, smb_path):
        data = "Test data for read+write delay."
        times = []
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"delay_rw_{i}.txt")
            times.append(_timed_write(p, data))

        avg = sum(times) / len(times)
        assert avg > 0.15, (
            f"Average write time {avg:.3f}s too fast for 200ms delay "
            f"(times: {[f'{t:.3f}' for t in times]})"
        )

    def test_delay_read_write_reads(self, smb_path):
        """Reads should also be delayed."""
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"delay_rw_read_{i}.txt")
            with open(p, "w") as f:
                f.write("read test data")

        times = []
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"delay_rw_read_{i}.txt")
            times.append(_timed_read(p))

        avg = sum(times) / len(times)
        assert avg > 0.15, (
            f"Average read time {avg:.3f}s too fast for 200ms delay "
            f"(times: {[f'{t:.3f}' for t in times]})"
        )

    def test_delay_read_write_integrity(self, smb_path):
        """Delay should not corrupt data."""
        data = "integrity check data for delay test"
        p = os.path.join(smb_path, "delay_rw_integrity.txt")
        with open(p, "w") as f:
            f.write(data)
        with open(p, "r") as f:
            result = f.read()
        assert result == data, "Data corrupted despite delay-only config"


class TestDelayReadProb:
    """delay_read_prob.conf -- 50% 300ms delay on reads."""

    def test_delay_read_prob(self, smb_path):
        """With 50% probability, some reads should be noticeably slower."""
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"delay_rp_{i}.txt")
            with open(p, "w") as f:
                f.write("probabilistic delay test data")

        times = []
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"delay_rp_{i}.txt")
            times.append(_timed_read(p))

        slow_count = sum(1 for t in times if t > 0.2)
        assert slow_count > 0, (
            f"No slow reads detected at 50% delay probability "
            f"(times: {[f'{t:.3f}' for t in times]})"
        )

    def test_delay_read_prob_writes_unaffected(self, smb_path):
        """Writes should not be delayed by read-only delay config."""
        data = "write speed test"
        times = []
        for i in range(NUM_OPS):
            p = os.path.join(smb_path, f"delay_rp_write_{i}.txt")
            times.append(_timed_write(p, data))

        avg = sum(times) / len(times)
        assert avg < 0.3, (
            f"Average write time {avg:.3f}s too slow -- delay leaking to writes?"
        )
