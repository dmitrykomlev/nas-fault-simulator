"""Statistical validation utilities for fault injection testing."""


def corruption_byte_diff(original: bytes, stored: bytes) -> float:
    """Return percentage of bytes that differ between original and stored."""
    if not original:
        return 0.0
    length = min(len(original), len(stored))
    if length == 0:
        return 0.0
    diff_count = sum(1 for i in range(length) if original[i] != stored[i])
    # Count length differences as corrupted bytes
    diff_count += abs(len(original) - len(stored))
    return (diff_count / len(original)) * 100.0


def check_probability_in_range(
    actual: float,
    expected: float,
    tolerance: float = 0.30,
) -> bool:
    """Check if actual probability is within tolerance of expected.

    For expected=0.5, tolerance=0.30 => acceptable range is [0.35, 0.65].
    """
    if expected == 0.0:
        return actual == 0.0
    low = expected * (1.0 - tolerance)
    high = expected * (1.0 + tolerance)
    return low <= actual <= high


def calculate_error_rate(results: list) -> float:
    """Calculate the fraction of False (failure) results in a list of bools."""
    if not results:
        return 0.0
    failures = sum(1 for r in results if not r)
    return failures / len(results)
