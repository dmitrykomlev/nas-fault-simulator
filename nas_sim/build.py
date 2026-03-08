"""Build command -- replaces scripts/build.sh."""

from __future__ import annotations

from nas_sim import console
from nas_sim.config import Config
from nas_sim.docker_utils import get_client


def build_image(cfg: Config, no_cache: bool = False, test_image: bool = False) -> bool:
    """Build the Docker image. Returns True on success."""
    client = get_client()
    root = str(cfg.project_root)

    if test_image:
        tag = cfg.test_image_name
        dockerfile = "Dockerfile.test"
        console.header("Building test-runner image")
    else:
        tag = cfg.image_name
        dockerfile = "Dockerfile"
        console.header("Building NAS Fault Simulator image")

    console.info(f"Context: {root}")
    console.info(f"Dockerfile: {dockerfile}")
    console.info(f"Tag: {tag}")
    if no_cache:
        console.info("Cache: disabled")

    try:
        _, logs = client.images.build(
            path=root,
            tag=tag,
            dockerfile=dockerfile,
            nocache=no_cache,
            rm=True,
        )
        console.stream_build_output(logs)
        console.success(f"Image '{tag}' built successfully")
        return True
    except Exception as exc:
        console.error(f"Build failed: {exc}")
        return False
