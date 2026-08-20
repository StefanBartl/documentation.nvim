"""Parity fixture — Python.

One documented public function, one private helper, an import, a call,
a module-level constant and a marker.
"""

from other import bump

MAX = 10


def _double(n):
    """Double a value.

    Args:
        n: How much.

    Returns:
        The doubled value.
    """
    return n * 2


def widen(n):
    """Widen a value.

    Args:
        n: How much.

    Returns:
        The widened value.
    """
    # TODO: cap at MAX
    return _double(n) + bump(MAX)
