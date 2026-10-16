"""manylinux platform tag generation.

Derived from pypa/packaging: packaging/_manylinux.py (Apache 2.0 / BSD).
See README.md for details.
"""

# Highest glibc minor version assumed for every glibc major version older
# than the requested one (packaging's _LAST_GLIBC_MINOR default).
_LAST_GLIBC_MINOR = 50

_LEGACY_MANYLINUX_MAP = {
    (2, 17): "manylinux2014",
    (2, 12): "manylinux2010",
    (2, 5): "manylinux1",
}

def manylinux_platforms(version, arch):
    """Generates manylinux platforms.

    Equivalent to packaging's `_manylinux.platform_tags([arch])` on a host
    whose glibc version is `version`: every glibc version from `version` down
    to 2.17 (2.5 on x86_64/i686), each followed by its legacy alias if it has
    one. For a glibc major version above 2, every older major version is
    assumed to go up to minor version 50, and versions down to X.0 are
    included for major versions other than 2.

    Args:
        version: The glibc version tuple (major, minor).
        arch: The architecture string.

    Returns:
        A list of manylinux platform strings.
    """
    platforms = []

    # Oldest glibc to be supported regardless of architecture is (2, 17).
    too_old_glibc2_minor = 16
    if arch in ("x86_64", "i686"):
        # On x86/i686 also oldest glibc to be supported is (2, 5).
        too_old_glibc2_minor = 4

    # We can assume compatibility across glibc major versions.
    glibc_max_list = [(version[0], version[1])]
    for glibc_major in range(version[0] - 1, 1, -1):
        glibc_max_list.append((glibc_major, _LAST_GLIBC_MINOR))

    for glibc_max in glibc_max_list:
        if glibc_max[0] == 2:
            min_minor = too_old_glibc2_minor
        else:
            # For other glibc major versions oldest supported is (x, 0).
            min_minor = -1
        for glibc_minor in range(glibc_max[1], min_minor, -1):
            platforms.append("manylinux_{}_{}_{}".format(glibc_max[0], glibc_minor, arch))
            legacy = _LEGACY_MANYLINUX_MAP.get((glibc_max[0], glibc_minor))
            if legacy:
                platforms.append("{}_{}".format(legacy, arch))

    return platforms
