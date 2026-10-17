"""Common utilities for platform tag generation.

Derived from pypa/pip: pip/_internal/utils/compatibility_tags.py (MIT).
See README.md for details.
"""

visibility(["//", "//pypackaging/..."])

def get_python_version(version_str):
    """Converts a version string such as "311" or "3" into a version tuple.

    Equivalent to pip's `_get_python_version()`: the first digit is the major
    version and the remaining digits are the minor version.

    Args:
        version_str: The version string without a dot (e.g. "311").

    Returns:
        A `(major, minor)` or `(major,)` tuple of ints.
    """
    if len(version_str) > 1:
        return (int(version_str[0]), int(version_str[1:]))
    else:
        return (int(version_str[0]),)
