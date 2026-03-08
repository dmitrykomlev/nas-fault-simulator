"""Configuration loader -- replaces scripts/config.sh."""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


def find_project_root(start: Optional[Path] = None) -> Path:
    """Walk up from *start* until pyproject.toml is found."""
    d = start or Path(__file__).resolve().parent.parent
    while True:
        if (d / "pyproject.toml").is_file():
            return d
        parent = d.parent
        if parent == d:
            raise FileNotFoundError(
                "Could not find project root (directory containing pyproject.toml)"
            )
        d = parent


def _parse_env_file(path: Path) -> dict:
    """Minimal .env parser -- handles KEY=VALUE lines, ignores comments/blanks."""
    env = {}
    if not path.is_file():
        return env
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        # Strip surrounding quotes if present
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        env[key] = value
    return env


@dataclass
class Config:
    image_name: str = "nas-fault-simulator-fuse-dev"
    test_image_name: str = "nas-fault-simulator-test"
    smb_username: str = "nasusr"
    smb_password: str = "naspass"
    smb_share: str = "nasshare"
    mount_point: str = "/mnt/nas-mount"
    storage_path: str = "/var/nas-storage"
    log_file: str = "/var/log/nas-emu.log"
    log_level: str = "3"
    smb_port: int = 1445
    configs_dir: str = ""
    project_root: Path = field(default_factory=lambda: Path("."))

    @classmethod
    def load(cls, root: Optional[Path] = None) -> "Config":
        root = root or find_project_root()
        env = _parse_env_file(root / ".env")
        env.update(_parse_env_file(root / ".env.local"))

        return cls(
            image_name=env.get("IMAGE_NAME", cls.image_name),
            smb_username=env.get("SMB_USERNAME", cls.smb_username),
            smb_password=env.get("SMB_PASSWORD", cls.smb_password),
            smb_share=env.get("SMB_SHARE_NAME", cls.smb_share),
            mount_point=env.get("NAS_MOUNT_POINT", cls.mount_point),
            storage_path=env.get("NAS_STORAGE_PATH", cls.storage_path),
            log_file=env.get("NAS_LOG_FILE", cls.log_file),
            log_level=env.get("NAS_LOG_LEVEL", cls.log_level),
            smb_port=int(env.get("NAS_SMB_PORT", cls.smb_port)),
            configs_dir=str(root / "src" / "fuse-driver" / "tests" / "configs"),
            project_root=root,
        )
