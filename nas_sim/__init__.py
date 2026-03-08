"""NAS Fault Simulator - Cross-platform Python orchestration."""

from pathlib import Path

__version__ = (Path(__file__).resolve().parent.parent / "VERSION").read_text().strip()
