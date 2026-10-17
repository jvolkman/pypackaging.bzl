"""Android platform tag generation.

Derived from pypa/packaging: packaging/tags.py (Apache 2.0 / BSD).
See README.md for details.
"""

visibility(["//", "//pypackaging/..."])

def android_platforms(api_level, abi):
    """Generates Android platforms.

    Args:
        api_level: The maximum Android API level.
        abi: The Android ABI. ".", "-" and " " are replaced with underscores,
            like packaging (e.g. "arm64-v8a" -> "arm64_v8a").

    Returns:
        A list of Android platform strings, from `api_level` down to 16.
    """
    abi = abi.replace(".", "_").replace("-", "_").replace(" ", "_")
    platforms = []
    for ver in range(api_level, 15, -1):
        platforms.append("android_{}_{}".format(ver, abi))
    return platforms
