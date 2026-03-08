"""Large file handling via SMB -- port of test_large_file_ops.sh.

Runs with no_faults.conf (fault injection disabled).
"""

import os

import pytest


class TestLargeFile:
    """Large file read/write operations through SMB share."""

    def test_large_file_write_read(self, smb_path):
        """Write and read back a 10 MB file."""
        fpath = os.path.join(smb_path, "large_10mb.bin")
        size = 10 * 1024 * 1024  # 10 MB
        # Deterministic pattern
        chunk = bytes(range(256)) * 4096  # 1 MB chunk
        try:
            with open(fpath, "wb") as f:
                written = 0
                while written < size:
                    to_write = min(len(chunk), size - written)
                    f.write(chunk[:to_write])
                    written += to_write

            # Verify size
            assert os.path.getsize(fpath) == size

            # Read back and verify
            with open(fpath, "rb") as f:
                read_back = f.read()
            assert len(read_back) == size

            # Verify content integrity
            expected = (chunk * 10)[:size]
            assert read_back == expected
        finally:
            if os.path.exists(fpath):
                os.remove(fpath)

    def test_large_file_partial_read(self, smb_path):
        """Write a large file, then read specific offsets."""
        fpath = os.path.join(smb_path, "large_partial.bin")
        size = 5 * 1024 * 1024  # 5 MB
        pattern = b"ABCD" * (size // 4)
        try:
            with open(fpath, "wb") as f:
                f.write(pattern)

            # Read from middle
            with open(fpath, "rb") as f:
                f.seek(size // 2)
                mid_data = f.read(1024)
            expected = pattern[size // 2 : size // 2 + 1024]
            assert mid_data == expected
        finally:
            if os.path.exists(fpath):
                os.remove(fpath)
