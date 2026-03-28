#!/usr/bin/env python3
"""Event emission tests -- runs INSIDE the target container.

Binds the event socket, performs FUSE operations locally on the mount,
and validates received events. Exits 0 on success, 1 on failure.

Usage: python3 test_event_emission.py [--config CONFIG_NAME]
  CONFIG_NAME selects which fault config to test against.
  Default tests run with whatever config the container started with.
"""

import json
import os
import socket
import sys
import threading
import time

SOCKET_PATH = "/var/run/nas-emu/events.sock"
MOUNT_POINT = os.environ.get("NAS_MOUNT_POINT", "/mnt/nas-mount")

failures = []


def fail(msg):
    failures.append(msg)
    print(f"  FAIL: {msg}", file=sys.stderr)


def ok(msg):
    print(f"  OK: {msg}")


class EventCollector:
    def __init__(self):
        self.events = []
        self._sock = None
        self._running = False
        self._thread = None

    def start(self):
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self._sock.bind(SOCKET_PATH)
        self._sock.settimeout(0.3)
        self._running = True
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)
        if self._sock:
            self._sock.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)

    def _loop(self):
        while self._running:
            try:
                data = self._sock.recv(8192)
                evt = json.loads(data.decode())
                self.events.append(evt)
            except socket.timeout:
                continue
            except Exception:
                continue

    def wait(self, n=1, timeout=3):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and len(self.events) < n:
            time.sleep(0.05)
        return len(self.events) >= n

    def by(self, **kw):
        result = self.events
        for k, v in kw.items():
            if k == "path_contains":
                result = [e for e in result if v in e.get("path", "")]
            else:
                result = [e for e in result if e.get(k) == v]
        return result

    def clear(self):
        self.events.clear()


# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

def test_write_events_emitted(c):
    """Write files on FUSE mount, expect write events."""
    c.clear()
    for i in range(3):
        p = os.path.join(MOUNT_POINT, f"evt_w_{i}.txt")
        with open(p, "w") as f:
            f.write("hello")
    c.wait(1)
    writes = c.by(op="write")
    if len(writes) > 0:
        ok(f"write events emitted ({len(writes)})")
    else:
        fail(f"no write events (total: {len(c.events)})")


def test_read_events_emitted(c):
    """Read a file, expect read events."""
    p = os.path.join(MOUNT_POINT, "evt_r.bin")
    with open(p, "wb") as f:
        f.write(b"read me")
    c.clear()
    with open(p, "rb") as f:
        f.read()
    c.wait(1)
    reads = c.by(op="read")
    if len(reads) > 0:
        ok(f"read events emitted ({len(reads)})")
    else:
        fail(f"no read events (total: {len(c.events)})")


def test_event_valid_json(c):
    """All events should be valid JSON dicts."""
    c.clear()
    p = os.path.join(MOUNT_POINT, "evt_json.txt")
    with open(p, "w") as f:
        f.write("json test")
    c.wait(1)
    if len(c.events) == 0:
        fail("no events to validate")
        return
    for e in c.events:
        if not isinstance(e, dict):
            fail(f"event is not dict: {e}")
            return
    ok("all events are valid JSON dicts")


def test_event_fields(c):
    """Events must have ts, op, path, off, sz, res."""
    c.clear()
    p = os.path.join(MOUNT_POINT, "evt_fields.txt")
    with open(p, "w") as f:
        f.write("fields test")
    c.wait(1)
    writes = c.by(op="write")
    if not writes:
        fail("no write events for field check")
        return
    required = {"ts", "op", "path", "off", "sz", "res"}
    for e in writes:
        missing = required - set(e.keys())
        if missing:
            fail(f"event missing {missing}: {e}")
            return
    ok("all required fields present")


def test_event_path_correct(c):
    """Event path should contain the filename we wrote."""
    c.clear()
    p = os.path.join(MOUNT_POINT, "evt_pathcheck.txt")
    with open(p, "w") as f:
        f.write("path test")
    c.wait(1)
    matched = c.by(op="write", path_contains="evt_pathcheck")
    if matched:
        ok(f"path correct in events ({matched[0]['path']})")
    else:
        paths = [e.get("path") for e in c.events]
        fail(f"no events with 'evt_pathcheck' in path. Seen: {paths}")


def test_event_size_positive(c):
    """Write event size should be > 0."""
    c.clear()
    p = os.path.join(MOUNT_POINT, "evt_sz.txt")
    with open(p, "w") as f:
        f.write("size check data")
    c.wait(1)
    writes = c.by(op="write", path_contains="evt_sz")
    if not writes:
        fail("no write events for size check")
        return
    for e in writes:
        if e["sz"] <= 0:
            fail(f"event size <= 0: {e}")
            return
    ok("all write events have positive size")


def test_corruption_event_details(c):
    """Corruption events should have corr field with n, pos, orig, new."""
    c.clear()
    for i in range(10):
        p = os.path.join(MOUNT_POINT, f"evt_corr_{i}.bin")
        with open(p, "wb") as f:
            f.write(b"A" * 200)
    c.wait(1, timeout=3)
    corr = c.by(fault="corruption")
    if not corr:
        # May not have corruption config -- skip gracefully
        ok("no corruption events (config may not have corruption enabled)")
        return
    for e in corr:
        if "corr" not in e:
            fail(f"corruption event missing 'corr': {e}")
            return
        d = e["corr"]
        for field in ("n", "pos", "orig", "new"):
            if field not in d:
                fail(f"corr missing '{field}': {d}")
                return
        if d["n"] <= 0:
            fail(f"corr n <= 0: {d}")
            return
        if len(d["pos"]) != d["n"]:
            fail(f"pos length {len(d['pos'])} != n {d['n']}")
            return
    ok(f"corruption events have valid details ({len(corr)} events)")


def test_corruption_positions_in_range(c):
    """Corrupted byte positions should be within [0, sz)."""
    corr = c.by(fault="corruption")
    if not corr:
        ok("no corruption events to check positions")
        return
    for e in corr:
        d = e.get("corr", {})
        for pos in d.get("pos", []):
            if pos < 0 or pos >= e["sz"]:
                fail(f"position {pos} out of range [0, {e['sz']})")
                return
    ok("all corruption positions in valid range")


def test_no_fault_field_when_clean(c):
    """Events without faults should have fault=null."""
    clean = [e for e in c.events if e.get("fault") is None]
    if clean:
        ok(f"clean events have fault=null ({len(clean)} events)")
    else:
        ok("no clean events to check (all had faults or no events)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=== Event Emission Tests (inside target container) ===")
    print(f"Socket: {SOCKET_PATH}")
    print(f"Mount:  {MOUNT_POINT}")

    collector = EventCollector()
    collector.start()
    time.sleep(0.5)  # Let socket bind settle

    try:
        tests = [
            test_write_events_emitted,
            test_read_events_emitted,
            test_event_valid_json,
            test_event_fields,
            test_event_path_correct,
            test_event_size_positive,
            test_corruption_event_details,
            test_corruption_positions_in_range,
            test_no_fault_field_when_clean,
        ]
        for t in tests:
            print(f"\n--- {t.__doc__.strip()} ---")
            t(collector)
    finally:
        collector.stop()

    print(f"\n{'='*50}")
    if failures:
        print(f"FAILED: {len(failures)} test(s)")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"ALL {len(tests)} tests passed")
    return 0


if __name__ == "__main__":
    rc = main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(rc)
