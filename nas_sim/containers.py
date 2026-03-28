"""Container lifecycle helpers for target and test-runner containers."""

from __future__ import annotations

import time
from typing import Optional

from nas_sim import console
from nas_sim.config import Config
from nas_sim.docker_utils import get_client, remove_container


def start_target(
    cfg: Config,
    config_file: str,
    container_name: str,
    network_name: str,
    volume_name: str,
    smb_port: Optional[int] = None,
    event_volume: Optional[str] = None,
) -> bool:
    """Start the FUSE+Samba target container. Returns True on success."""
    client = get_client()
    remove_container(container_name)

    ports = {}
    if smb_port is not None:
        ports["445/tcp"] = smb_port

    environment = {
        "NAS_MOUNT_POINT": cfg.mount_point,
        "NAS_STORAGE_PATH": cfg.storage_path,
        "NAS_LOG_FILE": cfg.log_file,
        "NAS_LOG_LEVEL": cfg.log_level,
        "SMB_SHARE_NAME": cfg.smb_share,
        "SMB_USERNAME": cfg.smb_username,
        "SMB_PASSWORD": cfg.smb_password,
        "CONFIG_FILE": config_file,
        "USE_HOST_STORAGE": "true",
    }

    volumes = {
        volume_name: {"bind": cfg.storage_path, "mode": "rw"},
    }

    # Mount event socket directory if provided
    if event_volume:
        volumes[event_volume] = {"bind": "/var/run/nas-emu", "mode": "rw"}

    # Mount config files read-only
    volumes[cfg.configs_dir] = {"bind": "/configs", "mode": "ro"}

    try:
        client.containers.run(
            cfg.image_name,
            name=container_name,
            detach=True,
            privileged=True,
            cap_add=["SYS_ADMIN"],
            devices=["/dev/fuse:/dev/fuse"],
            security_opt=["apparmor:unconfined"],
            ports=ports,
            environment=environment,
            volumes=volumes,
            network=network_name,
            hostname="target",
        )
        return True
    except Exception as exc:
        console.error(f"Failed to start target container: {exc}")
        return False


def wait_for_smb(container_name: str, cfg: Config, timeout: int = 30) -> bool:
    """Poll SMB readiness inside the target container using smbclient."""
    client = get_client()
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            ctr = client.containers.get(container_name)
            rc, _ = ctr.exec_run(
                f"smbclient -L //localhost -U {cfg.smb_username}%{cfg.smb_password}",
                demux=True,
            )
            if rc == 0:
                return True
        except Exception:
            pass
        time.sleep(1)
    return False


def start_test_runner(
    cfg: Config,
    container_name: str,
    network_name: str,
    volume_name: str,
    test_config: str,
    pytest_args: str = "",
    event_volume: Optional[str] = None,
) -> int:
    """Start the test-runner container. Returns the exit code."""
    client = get_client()
    remove_container(container_name)

    environment = {
        "SMB_HOST": "target",
        "SMB_PORT": "445",
        "SMB_SHARE": cfg.smb_share,
        "SMB_USERNAME": cfg.smb_username,
        "SMB_PASSWORD": cfg.smb_password,
        "SMB_MOUNT": "/mnt/smb",
        "RAW_STORAGE": cfg.storage_path,
        "TEST_CONFIG": test_config,
    }

    volumes = {
        volume_name: {"bind": cfg.storage_path, "mode": "ro"},
    }

    # Mount event socket directory if provided
    if event_volume:
        volumes[event_volume] = {"bind": "/var/run/nas-emu", "mode": "rw"}
        environment["EVENT_SOCKET_PATH"] = "/var/run/nas-emu/events.sock"

    # ENTRYPOINT is ["pytest"], so command is just the args
    cmd = f"-v --tb=short {pytest_args}"

    try:
        ctr = client.containers.run(
            cfg.test_image_name,
            command=cmd,
            name=container_name,
            detach=True,
            privileged=True,
            cap_add=["SYS_ADMIN"],
            environment=environment,
            volumes=volumes,
            network=network_name,
        )

        # Stream logs in real time
        for line in ctr.logs(stream=True, follow=True):
            text = line.decode("utf-8", errors="replace").rstrip("\n")
            if text:
                print(f"  {text}")

        ctr.reload()
        return ctr.attrs["State"]["ExitCode"]
    except Exception as exc:
        console.error(f"Test runner failed: {exc}")
        return 1
