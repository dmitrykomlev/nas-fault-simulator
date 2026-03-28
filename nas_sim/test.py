"""Test orchestration -- two-container model replacing scripts/run_tests.sh."""

from __future__ import annotations

import sys
import time
from dataclasses import dataclass
from typing import List, Optional

from nas_sim import console
from nas_sim.config import Config
from nas_sim.docker_utils import (
    ensure_network,
    ensure_volume,
    get_client,
    remove_container,
    remove_network,
    remove_volume,
)
from nas_sim.containers import start_target, start_test_runner, wait_for_smb


NETWORK_NAME = "nas-sim-test"


@dataclass
class TestScenario:
    name: str
    config_file: str
    pytest_args: str
    group: str


# All test scenarios matching the original run_tests.sh flow
SCENARIOS: List[TestScenario] = [
    # Group 1: basic operations (no faults)
    TestScenario("basic_ops", "no_faults.conf", "tests/test_basic_ops.py", "basic"),
    TestScenario("large_file", "no_faults.conf", "tests/test_large_file.py", "basic"),
    # Group 2: corruption tests
    TestScenario(
        "corruption_none", "corruption_none.conf",
        "tests/test_corruption.py -k none", "corruption",
    ),
    TestScenario(
        "corruption_medium", "corruption_medium.conf",
        "tests/test_corruption.py -k medium", "corruption",
    ),
    TestScenario(
        "corruption_high", "corruption_high.conf",
        "tests/test_corruption.py -k high", "corruption",
    ),
    TestScenario(
        "corruption_corner_prob", "corruption_corner_prob.conf",
        "tests/test_corruption.py -k corner_prob", "corruption",
    ),
    TestScenario(
        "corruption_corner_data", "corruption_corner_data.conf",
        "tests/test_corruption.py -k corner_data", "corruption",
    ),
    # Group 3: error injection tests
    TestScenario(
        "error_io_write_medium", "error_io_write_medium.conf",
        "tests/test_errors.py -k io_write_medium", "error",
    ),
    TestScenario(
        "error_io_read_medium", "error_io_read_medium.conf",
        "tests/test_errors.py -k io_read_medium", "error",
    ),
    TestScenario(
        "error_io_create_medium", "error_io_create_medium.conf",
        "tests/test_errors.py -k io_create_medium", "error",
    ),
    TestScenario(
        "error_io_create_high", "error_io_create_high.conf",
        "tests/test_errors.py -k io_create_high", "error",
    ),
    TestScenario(
        "error_io_all_high", "error_io_all_high.conf",
        "tests/test_errors.py -k io_all_high", "error",
    ),
    TestScenario(
        "error_access_create_medium", "error_access_create_medium.conf",
        "tests/test_errors.py -k access_create_medium", "error",
    ),
    TestScenario(
        "error_nospace_write_high", "error_nospace_write_high.conf",
        "tests/test_errors.py -k nospace_write_high", "error",
    ),
    # Group 4: delay injection tests
    TestScenario(
        "delay_write_medium", "delay_write_medium.conf",
        "tests/test_delay.py -k delay_write_medium", "delay",
    ),
    TestScenario(
        "delay_read_write", "delay_read_write.conf",
        "tests/test_delay.py -k delay_read_write", "delay",
    ),
    TestScenario(
        "delay_read_prob", "delay_read_prob.conf",
        "tests/test_delay.py -k delay_read_prob", "delay",
    ),
]


def _filter_scenarios(pattern: Optional[str]) -> List[TestScenario]:
    if not pattern:
        return list(SCENARIOS)
    return [s for s in SCENARIOS if pattern in s.name or pattern in s.group]


def _run_scenario(cfg: Config, scenario: TestScenario, verbose: bool) -> bool:
    """Run a single test scenario. Returns True on success."""
    vol_name = f"nas-sim-storage-{scenario.name}"
    target_name = f"nas-sim-target-{scenario.name}"
    runner_name = f"nas-sim-runner-{scenario.name}"

    console.header(f"Test: {scenario.name}")
    console.info(f"Config: {scenario.config_file}")
    console.info(f"Pytest: {scenario.pytest_args}")

    start = time.time()

    try:
        # Create fresh volume
        remove_volume(vol_name)
        ensure_volume(vol_name)

        # Start target container
        console.step(1, "Starting target container")
        if not start_target(
            cfg, scenario.config_file, target_name, NETWORK_NAME, vol_name
        ):
            return False

        # Wait for SMB readiness
        console.step(2, "Waiting for SMB readiness")
        if not wait_for_smb(target_name, cfg, timeout=30):
            console.error("SMB service did not become ready within 30s")
            return False
        console.success("SMB ready")

        # Start test runner
        console.step(3, "Running tests")
        verbose_flag = "-s" if verbose else ""
        pytest_args = f"{scenario.pytest_args} {verbose_flag}".strip()
        exit_code = start_test_runner(
            cfg, runner_name, NETWORK_NAME, vol_name,
            scenario.config_file, pytest_args,
        )

        elapsed = time.time() - start
        if exit_code == 0:
            console.success(f"{scenario.name} PASSED ({elapsed:.0f}s)")
            return True
        else:
            console.error(f"{scenario.name} FAILED (exit {exit_code}, {elapsed:.0f}s)")
            return False

    finally:
        remove_container(runner_name)
        remove_container(target_name)
        remove_volume(vol_name)


def run_tests(
    cfg: Config,
    filter_pattern: Optional[str] = None,
    preserve: bool = False,
    verbose: bool = False,
) -> int:
    """Run all (or filtered) test scenarios. Returns process exit code."""
    scenarios = _filter_scenarios(filter_pattern)
    if not scenarios:
        console.error(f"No scenarios match filter: {filter_pattern}")
        return 1

    console.header("NAS Fault Simulator - Test Suite")
    console.info(f"Scenarios: {len(scenarios)}")

    # Ensure network exists
    ensure_network(NETWORK_NAME)

    results = {}
    for scenario in scenarios:
        ok = _run_scenario(cfg, scenario, verbose)
        results[scenario.name] = ok
        if not ok and not preserve:
            # Continue running remaining tests (matching original behavior)
            pass

    # Summary
    console.header("Test Results Summary")
    passed = sum(1 for v in results.values() if v)
    failed = sum(1 for v in results.values() if not v)

    for name, ok in results.items():
        status = console._c(console._GREEN, "PASSED") if ok else console._c(console._RED, "FAILED")
        console.info(f"  {name}: {status}")

    console.info("")
    if failed == 0:
        console.success(f"All {passed} scenarios passed")
    else:
        console.error(f"{failed} of {passed + failed} scenarios failed")

    # Cleanup network
    try:
        remove_network(NETWORK_NAME)
    except Exception:
        pass

    return 0 if failed == 0 else 1
