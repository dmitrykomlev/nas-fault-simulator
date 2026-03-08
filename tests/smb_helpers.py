"""SMB mount/unmount helpers for use inside the test-runner container."""

import os
import subprocess
import time


def mount_smb(
    host: str,
    port: int,
    share: str,
    user: str,
    password: str,
    mountpoint: str,
) -> None:
    """Mount an SMB share via CIFS inside the container."""
    os.makedirs(mountpoint, exist_ok=True)
    cmd = [
        "mount", "-t", "cifs",
        f"//{host}/{share}",
        mountpoint,
        "-o", f"username={user},password={password},port={port},vers=3.0",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"SMB mount failed (rc={result.returncode}): {result.stderr.strip()}"
        )


def unmount_smb(mountpoint: str) -> None:
    """Unmount an SMB share (lazy, force)."""
    subprocess.run(["umount", "-lf", mountpoint], capture_output=True)


def wait_for_smb(host: str, port: int, user: str, password: str, timeout: int = 30) -> bool:
    """Poll until smbclient can list shares on the target."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = subprocess.run(
            ["smbclient", "-L", f"//{host}", "-p", str(port),
             "-U", f"{user}%{password}"],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            return True
        time.sleep(1)
    return False
