"""Corruption fault injection tests -- port of test_corruption_*.sh.

Each test is parameterized by config and expected behavior.
The TEST_CONFIG env var determines which scenario runs.
"""

import os
import time

import pytest

from tests.validation import corruption_byte_diff, check_probability_in_range


# Number of write samples for statistical tests
NUM_WRITES = 30


def _test_data() -> bytes:
    """200-byte deterministic test payload for reliable corruption measurement."""
    base = (
        b"This is a comprehensive test data string designed to be large "
        b"enough for reliable corruption percentage analysis. "
        b"It contains exactly 200 characters total, providing sufficient "
        b"data to accurately measure corruption per"
    )
    # Pad/trim to exactly 200 bytes
    return base[:200].ljust(200, b"X")


class TestCorruptionNone:
    """corruption_none.conf -- fault injection disabled, expect no corruption."""

    def test_none(self, smb_path, raw_storage):
        data = _test_data()
        corrupted = 0
        for i in range(NUM_WRITES):
            fname = f"corr_none_{i}.bin"
            smb_file = os.path.join(smb_path, fname)
            raw_file = os.path.join(raw_storage, fname)
            with open(smb_file, "wb") as f:
                f.write(data)
            time.sleep(0.1)
            if os.path.isfile(raw_file):
                stored = open(raw_file, "rb").read()
                if stored != data:
                    corrupted += 1
            # Cleanup
            if os.path.exists(smb_file):
                os.remove(smb_file)
        assert corrupted == 0, f"Expected 0 corruptions, got {corrupted}/{NUM_WRITES}"


class TestCorruptionMedium:
    """corruption_medium.conf -- 50% probability, 30% data corrupted."""

    def test_medium(self, smb_path, raw_storage):
        data = _test_data()
        corrupted = 0
        corruption_pcts = []
        for i in range(NUM_WRITES):
            fname = f"corr_med_{i}.bin"
            smb_file = os.path.join(smb_path, fname)
            raw_file = os.path.join(raw_storage, fname)
            with open(smb_file, "wb") as f:
                f.write(data)
            time.sleep(0.1)
            if os.path.isfile(raw_file):
                stored = open(raw_file, "rb").read()
                if stored != data:
                    corrupted += 1
                    pct = corruption_byte_diff(data, stored)
                    corruption_pcts.append(pct)
            if os.path.exists(smb_file):
                os.remove(smb_file)

        actual_prob = corrupted / NUM_WRITES
        assert corrupted > 0, "No corruption detected at all"
        assert check_probability_in_range(actual_prob, 0.5, tolerance=0.30), (
            f"Corruption probability {actual_prob:.2f} outside 0.35-0.65 range"
        )
        if corruption_pcts:
            avg_pct = sum(corruption_pcts) / len(corruption_pcts)
            # Allow wide tolerance on data corruption percentage
            assert 10.0 <= avg_pct <= 60.0, (
                f"Average corruption {avg_pct:.1f}% outside 10-60% range (expected ~30%)"
            )


class TestCorruptionHigh:
    """corruption_high.conf -- 100% probability, 70% data corrupted."""

    def test_high(self, smb_path, raw_storage):
        data = _test_data()
        corrupted = 0
        corruption_pcts = []
        for i in range(NUM_WRITES):
            fname = f"corr_high_{i}.bin"
            smb_file = os.path.join(smb_path, fname)
            raw_file = os.path.join(raw_storage, fname)
            with open(smb_file, "wb") as f:
                f.write(data)
            time.sleep(0.1)
            if os.path.isfile(raw_file):
                stored = open(raw_file, "rb").read()
                if stored != data:
                    corrupted += 1
                    pct = corruption_byte_diff(data, stored)
                    corruption_pcts.append(pct)
            if os.path.exists(smb_file):
                os.remove(smb_file)

        actual_prob = corrupted / NUM_WRITES
        # 100% probability -- expect nearly all files corrupted
        assert actual_prob >= 0.8, (
            f"Expected ~100% corruption, got {actual_prob:.2f}"
        )
        if corruption_pcts:
            avg_pct = sum(corruption_pcts) / len(corruption_pcts)
            assert avg_pct >= 40.0, (
                f"Average corruption {avg_pct:.1f}% too low (expected ~70%)"
            )


class TestCorruptionCornerProb:
    """corruption_corner_prob.conf -- 0% probability, 50% data.

    Zero probability should mean zero corruption regardless of data percentage.
    """

    def test_corner_prob(self, smb_path, raw_storage):
        data = _test_data()
        corrupted = 0
        for i in range(NUM_WRITES):
            fname = f"corr_cp_{i}.bin"
            smb_file = os.path.join(smb_path, fname)
            raw_file = os.path.join(raw_storage, fname)
            with open(smb_file, "wb") as f:
                f.write(data)
            time.sleep(0.1)
            if os.path.isfile(raw_file):
                stored = open(raw_file, "rb").read()
                if stored != data:
                    corrupted += 1
            if os.path.exists(smb_file):
                os.remove(smb_file)
        assert corrupted == 0, (
            f"0% probability should produce 0 corruptions, got {corrupted}"
        )


class TestCorruptionCornerData:
    """corruption_corner_data.conf -- 100% probability, 0% data.

    Zero data corruption percentage should mean no actual byte changes.
    """

    def test_corner_data(self, smb_path, raw_storage):
        data = _test_data()
        corrupted = 0
        for i in range(NUM_WRITES):
            fname = f"corr_cd_{i}.bin"
            smb_file = os.path.join(smb_path, fname)
            raw_file = os.path.join(raw_storage, fname)
            with open(smb_file, "wb") as f:
                f.write(data)
            time.sleep(0.1)
            if os.path.isfile(raw_file):
                stored = open(raw_file, "rb").read()
                if stored != data:
                    corrupted += 1
            if os.path.exists(smb_file):
                os.remove(smb_file)
        assert corrupted == 0, (
            f"0% data corruption should produce 0 actual changes, got {corrupted}"
        )
