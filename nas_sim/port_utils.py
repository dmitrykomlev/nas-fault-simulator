"""Cross-platform free port finder -- replaces netstat grep."""

import socket


def find_free_port(start: int = 1445) -> int:
    """Return the first TCP port >= *start* that is not in use."""
    port = start
    while port < 65535:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                port += 1
    raise RuntimeError(f"No free port found starting from {start}")
