"""Event emission tests for the FUSE driver management layer.

Tests verify that the FUSE driver emits structured JSON events
to a Unix domain socket for every filesystem operation. A Python
listener binds the socket before operations, then validates events.

The event socket is shared between target and runner containers
via a Docker volume at /var/run/nas-emu/.
"""

import json
import os
import socket
import threading
import time


EVENT_SOCKET = os.environ.get("EVENT_SOCKET_PATH", "/var/run/nas-emu/events.sock")
RECV_TIMEOUT = 5  # seconds to wait for events


class EventCollector:
    """Collects events from the FUSE driver via Unix DGRAM socket."""

    def __init__(self, socket_path=EVENT_SOCKET):
        self.socket_path = socket_path
        self.events = []
        self._sock = None
        self._thread = None
        self._running = False

    def start(self):
        # Remove stale socket file
        if os.path.exists(self.socket_path):
            os.unlink(self.socket_path)

        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self._sock.bind(self.socket_path)
        self._sock.settimeout(0.5)
        self._running = True
        self._thread = threading.Thread(target=self._recv_loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)
        if self._sock:
            self._sock.close()
        if os.path.exists(self.socket_path):
            os.unlink(self.socket_path)

    def _recv_loop(self):
        while self._running:
            try:
                data = self._sock.recv(8192)
                try:
                    event = json.loads(data.decode("utf-8"))
                    self.events.append(event)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    pass  # Skip malformed datagrams
            except socket.timeout:
                continue

    def wait_for_events(self, min_count=1, timeout=RECV_TIMEOUT):
        """Wait until at least min_count events are collected."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if len(self.events) >= min_count:
                return True
            time.sleep(0.1)
        return len(self.events) >= min_count

    def get_events(self, op=None, fault=None, path_contains=None):
        """Filter collected events."""
        result = self.events
        if op:
            result = [e for e in result if e.get("op") == op]
        if fault:
            result = [e for e in result if e.get("fault") == fault]
        if path_contains:
            result = [e for e in result if path_contains in e.get("path", "")]
        return result


class TestEventEmissionWrite:
    """no_faults.conf -- verify events emitted for write operations."""

    def test_event_emission_write(self, smb_path):
        collector = EventCollector()
        collector.start()
        try:
            # Give collector time to bind
            time.sleep(0.5)

            # Write files via SMB
            for i in range(5):
                p = os.path.join(smb_path, f"evt_write_{i}.txt")
                with open(p, "w") as f:
                    f.write("event test data")

            # Wait for events
            collector.wait_for_events(min_count=1, timeout=3)

            # Verify write events received
            write_events = collector.get_events(op="write")
            assert len(write_events) > 0, (
                f"No write events received "
                f"(total events: {len(collector.events)})"
            )
        finally:
            collector.stop()

    def test_event_format_valid_json(self, smb_path):
        collector = EventCollector()
        collector.start()
        try:
            time.sleep(0.5)
            p = os.path.join(smb_path, "evt_json_test.txt")
            with open(p, "w") as f:
                f.write("json format test")

            collector.wait_for_events(min_count=1, timeout=3)

            # All events should be valid JSON (already parsed in collector)
            assert len(collector.events) > 0, "No events received"
            for event in collector.events:
                assert isinstance(event, dict), f"Event is not a dict: {event}"
        finally:
            collector.stop()

    def test_event_fields_present(self, smb_path):
        collector = EventCollector()
        collector.start()
        try:
            time.sleep(0.5)
            p = os.path.join(smb_path, "evt_fields_test.txt")
            with open(p, "w") as f:
                f.write("fields test data")

            collector.wait_for_events(min_count=1, timeout=3)

            write_events = collector.get_events(op="write")
            assert len(write_events) > 0, "No write events"

            required_fields = {"ts", "op", "path", "off", "sz", "res"}
            for event in write_events:
                missing = required_fields - set(event.keys())
                assert not missing, (
                    f"Event missing fields {missing}: {event}"
                )
        finally:
            collector.stop()

    def test_event_path_correct(self, smb_path):
        collector = EventCollector()
        collector.start()
        try:
            time.sleep(0.5)
            p = os.path.join(smb_path, "evt_path_check.txt")
            with open(p, "w") as f:
                f.write("path check data")

            collector.wait_for_events(min_count=1, timeout=3)

            matching = collector.get_events(
                op="write", path_contains="evt_path_check"
            )
            assert len(matching) > 0, (
                f"No events with path containing 'evt_path_check'. "
                f"Paths seen: {[e.get('path') for e in collector.events]}"
            )
        finally:
            collector.stop()

    def test_event_size_positive(self, smb_path):
        collector = EventCollector()
        collector.start()
        try:
            time.sleep(0.5)
            data = "size check data with known length"
            p = os.path.join(smb_path, "evt_size_check.txt")
            with open(p, "w") as f:
                f.write(data)

            collector.wait_for_events(min_count=1, timeout=3)

            write_events = collector.get_events(
                op="write", path_contains="evt_size_check"
            )
            assert len(write_events) > 0, "No write events for size check"
            for event in write_events:
                assert event["sz"] > 0, f"Event size is 0: {event}"
        finally:
            collector.stop()


class TestEventEmissionRead:
    """no_faults.conf -- verify events emitted for read operations."""

    def test_event_emission_read(self, smb_path):
        # Create file first
        p = os.path.join(smb_path, "evt_read_test.txt")
        with open(p, "w") as f:
            f.write("read event test data")

        collector = EventCollector()
        collector.start()
        try:
            time.sleep(0.5)

            # Read the file
            with open(p, "r") as f:
                f.read()

            collector.wait_for_events(min_count=1, timeout=3)

            read_events = collector.get_events(op="read")
            assert len(read_events) > 0, (
                f"No read events received "
                f"(total events: {len(collector.events)})"
            )
        finally:
            collector.stop()


class TestEventEmissionCorruption:
    """corruption_high.conf -- verify corruption events have details."""

    def test_event_emission_corruption_details(self, smb_path):
        collector = EventCollector()
        collector.start()
        try:
            time.sleep(0.5)

            # Write files (corruption config should corrupt some)
            for i in range(10):
                p = os.path.join(smb_path, f"evt_corr_{i}.bin")
                with open(p, "wb") as f:
                    f.write(b"A" * 200)

            collector.wait_for_events(min_count=1, timeout=3)

            # Check for corruption events
            corr_events = collector.get_events(fault="corruption")
            assert len(corr_events) > 0, (
                f"No corruption events. "
                f"Faults seen: {set(e.get('fault') for e in collector.events)}"
            )

            # Verify corruption detail fields
            for event in corr_events:
                assert "corr" in event, f"Corruption event missing 'corr': {event}"
                corr = event["corr"]
                assert "n" in corr, f"Missing corruption count 'n': {corr}"
                assert "pos" in corr, f"Missing positions 'pos': {corr}"
                assert "orig" in corr, f"Missing original values 'orig': {corr}"
                assert "new" in corr, f"Missing corrupted values 'new': {corr}"
                assert corr["n"] > 0, f"Corruption count is 0: {corr}"
                assert len(corr["pos"]) == corr["n"], "pos length != n"
                assert len(corr["orig"]) == corr["n"], "orig length != n"
                assert len(corr["new"]) == corr["n"], "new length != n"
        finally:
            collector.stop()

    def test_event_emission_corruption_positions_valid(self, smb_path):
        collector = EventCollector()
        collector.start()
        try:
            time.sleep(0.5)

            p = os.path.join(smb_path, "evt_corr_pos.bin")
            data_size = 200
            with open(p, "wb") as f:
                f.write(b"B" * data_size)

            collector.wait_for_events(min_count=1, timeout=3)

            corr_events = collector.get_events(
                fault="corruption", path_contains="evt_corr_pos"
            )
            for event in corr_events:
                corr = event.get("corr", {})
                for pos in corr.get("pos", []):
                    assert 0 <= pos < event["sz"], (
                        f"Position {pos} out of range [0, {event['sz']})"
                    )
        finally:
            collector.stop()
