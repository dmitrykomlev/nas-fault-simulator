"""Console output helpers. ASCII only, no emoji."""

import sys


# ANSI color codes
_RED = "\033[0;31m"
_GREEN = "\033[0;32m"
_YELLOW = "\033[1;33m"
_CYAN = "\033[0;36m"
_BOLD = "\033[1m"
_RESET = "\033[0m"


def _supports_color():
    return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()


def _c(code, text):
    if _supports_color():
        return f"{code}{text}{_RESET}"
    return text


def info(msg):
    print(msg)


def success(msg):
    print(_c(_GREEN, f"[OK] {msg}"))


def warn(msg):
    print(_c(_YELLOW, f"[WARN] {msg}"))


def error(msg):
    print(_c(_RED, f"[ERROR] {msg}"), file=sys.stderr)


def header(msg):
    line = "=" * 60
    print(f"\n{_c(_BOLD, line)}")
    print(_c(_BOLD, msg))
    print(_c(_BOLD, line))


def step(n, msg):
    print(f"\n{_c(_CYAN, f'Step {n}:')} {msg}")


def item(msg):
    print(f"  - {msg}")


def stream_build_output(generator):
    """Stream Docker build output line by line."""
    for chunk in generator:
        if "stream" in chunk:
            line = chunk["stream"].rstrip("\n")
            if line:
                print(f"  {line}")
        elif "error" in chunk:
            error(chunk["error"].rstrip("\n"))
