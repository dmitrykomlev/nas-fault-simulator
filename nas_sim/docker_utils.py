"""Docker SDK helpers -- client, network, volume management."""

from __future__ import annotations

import sys
from typing import Optional

import docker
from docker.errors import DockerException, NotFound

from nas_sim import console


_client: Optional[docker.DockerClient] = None


def get_client() -> docker.DockerClient:
    """Return a cached Docker client, or exit with a clear message."""
    global _client
    if _client is not None:
        return _client
    try:
        _client = docker.from_env()
        _client.ping()
    except DockerException as exc:
        console.error(f"Cannot connect to Docker: {exc}")
        console.error("Make sure Docker Desktop is running.")
        sys.exit(1)
    return _client


# -- Network helpers ----------------------------------------------------------

def ensure_network(name: str) -> None:
    client = get_client()
    try:
        client.networks.get(name)
    except NotFound:
        client.networks.create(name, driver="bridge")


def remove_network(name: str) -> None:
    client = get_client()
    try:
        net = client.networks.get(name)
        net.remove()
    except NotFound:
        pass
    except Exception as exc:
        console.warn(f"Could not remove network {name}: {exc}")


# -- Volume helpers -----------------------------------------------------------

def ensure_volume(name: str) -> None:
    client = get_client()
    try:
        client.volumes.get(name)
    except NotFound:
        client.volumes.create(name)


def remove_volume(name: str) -> None:
    client = get_client()
    try:
        vol = client.volumes.get(name)
        vol.remove(force=True)
    except NotFound:
        pass
    except Exception as exc:
        console.warn(f"Could not remove volume {name}: {exc}")


# -- Container helpers --------------------------------------------------------

def remove_container(name: str) -> None:
    """Stop and remove a container by name (ignore if not found)."""
    client = get_client()
    try:
        c = client.containers.get(name)
        c.stop(timeout=5)
        c.remove(force=True)
    except NotFound:
        pass
    except Exception as exc:
        console.warn(f"Could not remove container {name}: {exc}")
