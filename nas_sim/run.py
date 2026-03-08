"""Run command -- replaces scripts/run-fuse.sh and run-nas-simulator.sh."""

from __future__ import annotations

import sys

from nas_sim import console
from nas_sim.config import Config
from nas_sim.docker_utils import get_client, remove_container
from nas_sim.port_utils import find_free_port


def run_container(cfg: Config, config_file: str, port: int | None = None) -> None:
    """Start a single FUSE+Samba container for interactive use."""
    client = get_client()
    container_name = "nas-fault-simulator"

    # Check image exists
    try:
        client.images.get(cfg.image_name)
    except Exception:
        console.error(
            f"Image '{cfg.image_name}' not found. Run: python -m nas_sim build"
        )
        sys.exit(1)

    smb_port = port or find_free_port(cfg.smb_port)

    console.header("NAS Fault Simulator - Starting")
    console.info(f"Config: {config_file}")
    console.info(f"SMB port: {smb_port}")
    console.info(f"Container: {container_name}")

    remove_container(container_name)

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

    # Mount host storage dir + configs
    storage_dir = str(cfg.project_root / "nas-storage")
    volumes = {
        storage_dir: {"bind": cfg.storage_path, "mode": "rw"},
        cfg.configs_dir: {"bind": "/configs", "mode": "ro"},
    }

    try:
        client.containers.run(
            cfg.image_name,
            name=container_name,
            detach=True,
            privileged=True,
            cap_add=["SYS_ADMIN"],
            devices=["/dev/fuse:/dev/fuse"],
            security_opt=["apparmor:unconfined"],
            ports={"445/tcp": smb_port},
            environment=environment,
            volumes=volumes,
        )
    except Exception as exc:
        console.error(f"Failed to start container: {exc}")
        sys.exit(1)

    console.success("Container started successfully")
    console.info("")
    console.info("SMB Share Access:")
    console.info(
        f"  smb://{cfg.smb_username}:{cfg.smb_password}"
        f"@localhost:{smb_port}/{cfg.smb_share}"
    )
    console.info("")
    console.info("To stop:")
    console.info("  python -m nas_sim stop")
    console.info("")
    console.info("Container logs:")
    console.info(f"  docker logs {container_name}")


def stop_container() -> None:
    """Stop the user-facing container."""
    remove_container("nas-fault-simulator")
    console.success("Container stopped")
