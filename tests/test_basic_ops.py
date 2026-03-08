"""Basic filesystem operations via SMB -- port of test_basic_ops.sh.

Runs with no_faults.conf (fault injection disabled).
"""

import os
import time

import pytest


class TestBasicOps:
    """Basic file and directory operations through SMB share."""

    def test_create_read_write(self, smb_path):
        fpath = os.path.join(smb_path, "test_crw.txt")
        content = "Hello World from FUSE!"
        try:
            with open(fpath, "w") as f:
                f.write(content)
            with open(fpath, "r") as f:
                assert f.read() == content
        finally:
            if os.path.exists(fpath):
                os.remove(fpath)

    def test_directory_operations(self, smb_path):
        dpath = os.path.join(smb_path, "test_dir")
        fpath = os.path.join(dpath, "inner.txt")
        try:
            os.makedirs(dpath, exist_ok=True)
            assert os.path.isdir(dpath)
            with open(fpath, "w") as f:
                f.write("inner content")
            assert os.path.isfile(fpath)
            entries = os.listdir(dpath)
            assert "inner.txt" in entries
        finally:
            if os.path.exists(fpath):
                os.remove(fpath)
            if os.path.exists(dpath):
                os.rmdir(dpath)

    def test_file_rename(self, smb_path):
        orig = os.path.join(smb_path, "test_orig.txt")
        renamed = os.path.join(smb_path, "test_renamed.txt")
        content = "Rename test content"
        try:
            with open(orig, "w") as f:
                f.write(content)
            os.rename(orig, renamed)
            assert not os.path.exists(orig)
            assert os.path.isfile(renamed)
            with open(renamed, "r") as f:
                assert f.read() == content
        finally:
            for p in (orig, renamed):
                if os.path.exists(p):
                    os.remove(p)

    def test_file_permissions(self, smb_path):
        fpath = os.path.join(smb_path, "test_perm.txt")
        content = "Permission test"
        try:
            with open(fpath, "w") as f:
                f.write(content)
            os.chmod(fpath, 0o400)
            # Should still be readable
            with open(fpath, "r") as f:
                assert f.read() == content
        finally:
            # Restore write permission for cleanup
            if os.path.exists(fpath):
                os.chmod(fpath, 0o600)
                os.remove(fpath)

    def test_file_delete(self, smb_path):
        fpath = os.path.join(smb_path, "test_delete.txt")
        with open(fpath, "w") as f:
            f.write("delete me")
        assert os.path.exists(fpath)
        os.remove(fpath)
        assert not os.path.exists(fpath)

    def test_multiple_files(self, smb_path):
        paths = []
        try:
            for i in range(10):
                p = os.path.join(smb_path, f"multi_{i}.txt")
                paths.append(p)
                with open(p, "w") as f:
                    f.write(f"content {i}")
            for i, p in enumerate(paths):
                with open(p, "r") as f:
                    assert f.read() == f"content {i}"
        finally:
            for p in paths:
                if os.path.exists(p):
                    os.remove(p)

    def test_append_operations(self, smb_path):
        fpath = os.path.join(smb_path, "test_append.txt")
        try:
            with open(fpath, "w") as f:
                f.write("line1\n")
            with open(fpath, "a") as f:
                f.write("line2\n")
            with open(fpath, "r") as f:
                lines = f.readlines()
            assert len(lines) == 2
            assert lines[0] == "line1\n"
            assert lines[1] == "line2\n"
        finally:
            if os.path.exists(fpath):
                os.remove(fpath)
