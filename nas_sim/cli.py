"""CLI entry point -- python -m nas_sim <command>."""

from __future__ import annotations

import argparse
import sys

from nas_sim import __version__


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="nas-sim",
        description="NAS Fault Simulator orchestration tool",
    )
    sub = parser.add_subparsers(dest="command")

    # build
    p_build = sub.add_parser("build", help="Build Docker image(s)")
    p_build.add_argument("--no-cache", action="store_true", help="Disable Docker cache")
    p_build.add_argument(
        "--test-image", action="store_true", help="Build test-runner image too"
    )

    # run
    p_run = sub.add_parser("run", help="Run FUSE+Samba container")
    p_run.add_argument("--config", required=True, help="Config file name")
    p_run.add_argument("--port", type=int, default=None, help="Host SMB port")

    # stop
    sub.add_parser("stop", help="Stop running container")

    # test
    p_test = sub.add_parser("test", help="Run two-container test suite")
    p_test.add_argument("--filter", default=None, help="Filter scenarios by name/group")
    p_test.add_argument(
        "--preserve", action="store_true",
        help="Preserve containers on failure for debugging",
    )
    p_test.add_argument("--verbose", "-v", action="store_true", help="Verbose output")

    # clean
    p_clean = sub.add_parser("clean", help="Remove containers, volumes, networks")
    p_clean.add_argument(
        "--all", action="store_true", help="Also remove Docker images"
    )

    # version
    sub.add_parser("version", help="Show version")

    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 0

    if args.command == "version":
        print(f"nas-fault-simulator {__version__}")
        return 0

    # Lazy imports so --version/--help stays fast
    from nas_sim.config import Config
    from nas_sim import console

    cfg = Config.load()

    if args.command == "build":
        from nas_sim.build import build_image

        ok = build_image(cfg, no_cache=args.no_cache)
        if args.test_image and ok:
            ok = build_image(cfg, no_cache=args.no_cache, test_image=True)
        return 0 if ok else 1

    elif args.command == "run":
        from nas_sim.run import run_container

        run_container(cfg, args.config, args.port)
        return 0

    elif args.command == "stop":
        from nas_sim.run import stop_container

        stop_container()
        return 0

    elif args.command == "test":
        from nas_sim.test import run_tests
        from nas_sim.build import build_image

        # Auto-build both images before testing
        console.header("Pre-build: target image")
        if not build_image(cfg):
            return 1
        console.header("Pre-build: test-runner image")
        if not build_image(cfg, test_image=True):
            return 1

        return run_tests(cfg, args.filter, args.preserve, args.verbose)

    elif args.command == "clean":
        from nas_sim.docker_utils import (
            get_client,
            remove_container,
            remove_network,
            remove_volume,
        )
        from nas_sim.test import SCENARIOS, NETWORK_NAME

        console.info("Cleaning up containers, volumes, and networks...")
        remove_container("nas-fault-simulator")
        for s in SCENARIOS:
            remove_container(f"nas-sim-target-{s.name}")
            remove_container(f"nas-sim-runner-{s.name}")
            remove_volume(f"nas-sim-storage-{s.name}")
        remove_network(NETWORK_NAME)

        if args.all:
            client = get_client()
            for tag in [cfg.image_name, cfg.test_image_name]:
                try:
                    client.images.remove(tag, force=True)
                    console.info(f"Removed image: {tag}")
                except Exception:
                    pass

        console.success("Cleanup complete")
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
