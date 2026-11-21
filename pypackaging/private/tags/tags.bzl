"""PEP 425 compatibility tag parsing, expansion, and selection.

Derived from pypa/packaging: packaging/tags.py, packaging/_manylinux.py, and
packaging/_musllinux.py (Apache 2.0 / BSD), and pypa/pip:
pip/_internal/utils/compatibility_tags.py (MIT).
See README.md for details.
"""

visibility(["//", "//pypackaging/..."])

_DIGITS = "0123456789"
_IDENT_START = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
_IDENT_CHARS = _IDENT_START + _DIGITS

# Highest glibc minor version assumed for every glibc major version older
# than the requested one (packaging's _LAST_GLIBC_MINOR default).
_LAST_GLIBC_MINOR = 50

_LEGACY_MANYLINUX_MAP = {
    (2, 17): "manylinux2014",
    (2, 12): "manylinux2010",
    (2, 5): "manylinux1",
}

_LEGACY_TO_PEP600 = {
    "manylinux1": (2, 5),
    "manylinux2010": (2, 12),
    "manylinux2014": (2, 17),
}

_ARCH_FALLBACKS = {
    "armv8l": ["armv8l", "armv7l"],
}

# ---------------------------------------------------------------------------
# Platform tag expansion
# ---------------------------------------------------------------------------

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
    return (int(version_str[0]),)

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

    # Oldest glibc to be supported regardless of architecture is (2, 17),
    # except x86_64/i686 which go down to (2, 5).
    too_old_glibc2_minor = 4 if arch in ("x86_64", "i686") else 16

    glibc_max_list = [(version[0], version[1])]
    for glibc_major in range(version[0] - 1, 1, -1):
        glibc_max_list.append((glibc_major, _LAST_GLIBC_MINOR))

    for glibc_major, glibc_max_minor in glibc_max_list:
        min_minor = too_old_glibc2_minor if glibc_major == 2 else -1
        for glibc_minor in range(glibc_max_minor, min_minor, -1):
            platforms.append("manylinux_{}_{}_{}".format(glibc_major, glibc_minor, arch))
            legacy = _LEGACY_MANYLINUX_MAP.get((glibc_major, glibc_minor))
            if legacy:
                platforms.append("{}_{}".format(legacy, arch))

    return platforms

def _musllinux_platforms(version, arch):
    major, minor = version
    return ["musllinux_{}_{}_{}".format(major, m, arch) for m in range(minor, -1, -1)]

def _mac_binary_formats(version, cpu_arch):
    formats = [cpu_arch]
    if cpu_arch == "x86_64":
        if version < (10, 4):
            return []
        formats.extend(["intel", "fat64", "fat3"])
    elif cpu_arch == "i386":
        if version < (10, 4):
            return []
        formats.extend(["intel", "fat3", "fat"])
    elif cpu_arch == "ppc64":
        if version > (10, 5) or version < (10, 4):
            return []
        formats.append("fat64")
    elif cpu_arch == "ppc":
        if version > (10, 6):
            return []
        formats.extend(["fat3", "fat"])

    if cpu_arch in ("arm64", "x86_64"):
        formats.append("universal2")

    if cpu_arch in ("x86_64", "i386", "ppc64", "ppc", "intel"):
        formats.append("universal")

    return formats

def _mac_platforms(version, arch):
    platforms = []
    if version >= (10, 0) and version < (11, 0):
        for minor_version in range(version[1], -1, -1):
            for binary_format in _mac_binary_formats((10, minor_version), arch):
                platforms.append("macosx_10_{}_{}".format(minor_version, binary_format))

    if version >= (11, 0):
        for major_version in range(version[0], 10, -1):
            for binary_format in _mac_binary_formats((major_version, 0), arch):
                platforms.append("macosx_{}_0_{}".format(major_version, binary_format))

        # Fallback to 10.x.
        if arch == "x86_64":
            for minor_version in range(16, 3, -1):
                for binary_format in _mac_binary_formats((10, minor_version), arch):
                    platforms.append("macosx_10_{}_{}".format(minor_version, binary_format))
        else:
            for minor_version in range(16, 3, -1):
                platforms.append("macosx_10_{}_universal2".format(minor_version))

    return platforms

def _ios_platforms(major, minor, multiarch):
    multiarch = multiarch.replace("-", "_")
    if major < 12:
        return []

    platforms = ["ios_{}_{}_{}".format(major, m, multiarch) for m in range(minor, -1, -1)]
    for maj in range(major - 1, 11, -1):
        for m in range(9, -1, -1):
            platforms.append("ios_{}_{}_{}".format(maj, m, multiarch))
    return platforms

def _android_platforms(api_level, abi):
    abi = abi.replace(".", "_").replace("-", "_").replace(" ", "_")
    return ["android_{}_{}".format(ver, abi) for ver in range(api_level, 15, -1)]

def _match_apple_platform(platform):
    """Equivalent to pip's `re.match(r"(.+)_(\\d+)_(\\d+)_(.+)", platform)`.

    Returns:
        A `(name, major, minor, arch)` tuple, or None if there is no match.
    """
    parts = platform.split("_")

    # The first group is greedy, so prefer the right-most split.
    for i in range(len(parts) - 3, 0, -1):
        name = "_".join(parts[:i])
        rest = "_".join(parts[i + 2:])
        if name and parts[i].isdigit() and parts[i + 1].isdigit() and rest:
            return name, int(parts[i]), int(parts[i + 1]), rest
    return None

def _expand_linux(version, arch, expand_fn):
    archs = _ARCH_FALLBACKS.get(arch, [arch])

    # Like packaging 26.3's `_linux_platforms()`, native `linux_<arch>` tags
    # come before manylinux/musllinux tags.
    result = ["linux_" + a for a in archs]
    for a in archs:
        result.extend(expand_fn(version, a))
    return result

def _expand_platform(platform):
    """Expands a single platform into its compatible platforms."""
    if platform.startswith("macosx"):
        # Like pip, any "macosx*" prefix is accepted and kept, e.g.
        # "macosxcustom_10_9_x86_64" -> "macosxcustom_10_8_x86_64", ...
        m = _match_apple_platform(platform)
        if m:
            name, major, minor, arch = m
            res = _mac_platforms((major, minor), arch)
            if name == "macosx":
                return res
            return [name + p[len("macosx"):] for p in res]
    elif platform.startswith("ios"):
        m = _match_apple_platform(platform)
        if m:
            name, major, minor, multiarch = m
            res = _ios_platforms(major, minor, multiarch)
            if name == "ios":
                return res
            return [name + p[len("ios"):] for p in res]
    elif platform.startswith(("manylinux_", "musllinux_")):
        parts = platform.split("_")
        if len(parts) >= 4 and parts[1].isdigit() and parts[2].isdigit():
            expand_fn = manylinux_platforms if parts[0] == "manylinux" else _musllinux_platforms
            return _expand_linux((int(parts[1]), int(parts[2])), "_".join(parts[3:]), expand_fn)
    elif platform.startswith("manylinux"):
        parts = platform.split("_", 1)
        if len(parts) == 2:
            version = _LEGACY_TO_PEP600.get(parts[0])
            if version:
                return _expand_linux(version, parts[1], manylinux_platforms)
    elif platform.startswith("android_"):
        # Equivalent to pip's re.fullmatch(r"android_(\d+)_(.+)", platform).
        parts = platform.split("_", 2)
        if len(parts) == 3 and parts[1].isdigit() and parts[2]:
            return _android_platforms(int(parts[1]), parts[2])

    return [platform]

def expand_allowed_platforms(platforms):
    """Expands a list of platform strings into their full compatibility order.

    Internal helper exposed for tests; not part of the public API.

    Args:
        platforms: A list of platform strings.

    Returns:
        A deduplicated list of expanded platform strings, most preferred first.
    """
    if not platforms:
        return []

    seen = {}
    result = []

    for p in platforms:
        if p in seen:
            continue
        for add in _expand_platform(p):
            if add not in seen:
                seen[add] = True
                result.append(add)

    return result

# ---------------------------------------------------------------------------
# Interpreter tag generators
# ---------------------------------------------------------------------------

def _is_threaded_cpython(abis):
    """Whether the ABIs describe a free-threaded CPython build (e.g. `cp313t`).

    The first version-specific CPython ABI (`cp\\d+(.*)`) or `"abi3t"` decides.
    """
    for abi in abis:
        if abi == "abi3t":
            return True
        if abi.startswith("cp"):
            flags = abi[2:].lstrip(_DIGITS)
            if len(flags) != len(abi) - 2:
                return "t" in flags
    return False

def cpython_tags(python_version, abis, platforms):
    """Generates CPython tags.

    Like packaging's `Tag`, the generated tags are lowercase.

    Args:
        python_version: The Python version tuple.
        abis: A list of ABIs. Every `abi3` and `none` entry (plus `abi3t` for
            free-threaded builds) is removed since they are handled separately;
            packaging only removes the first of each.
        platforms: A list of platforms.

    Returns:
        A list of CPython tag strings.
    """
    tags = []
    version_str = "".join([str(p) for p in python_version[:2]])
    interpreter = "cp" + version_str

    abi_list = abis or []

    # Free-threading is detected before filtering and lowercasing, like packaging.
    threading = _is_threaded_cpython(abi_list)
    ignored_abis = ("abi3", "abi3t", "none") if threading else ("abi3", "none")
    explicit_abis = [abi for abi in abi_list if abi not in ignored_abis]

    platforms = [p.lower() for p in platforms]
    for abi in explicit_abis:
        prefix = interpreter + "-" + abi.lower() + "-"
        tags.extend([prefix + platform for platform in platforms])

    has_abi3 = len(python_version) > 1 and python_version >= (3, 2)
    abi3_tag = "abi3t" if threading else "abi3"
    if has_abi3:
        prefix = interpreter + "-" + abi3_tag + "-"
        tags.extend([prefix + platform for platform in platforms])

    prefix = interpreter + "-none-"
    tags.extend([prefix + platform for platform in platforms])

    if has_abi3:
        major_prefix = "cp" + str(python_version[0])
        abi_suffix = "-" + abi3_tag + "-"
        for minor_version in range(python_version[1] - 1, 1, -1):
            prefix = major_prefix + str(minor_version) + abi_suffix
            tags.extend([prefix + platform for platform in platforms])

    return tags

def _generic_tags(interpreter, abis, platforms):
    tags = []
    abis_copy = list(abis) if abis else []
    if "none" not in abis_copy:
        abis_copy.append("none")

    interpreter = interpreter.lower()
    platforms = [p.lower() for p in platforms]
    for abi in abis_copy:
        prefix = interpreter + "-" + abi.lower() + "-"
        tags.extend([prefix + platform for platform in platforms])
    return tags

def _py_interpreter_range(python_version):
    major = str(python_version[0])
    if len(python_version) <= 1:
        return ["py" + major]
    versions = ["py" + major + str(python_version[1]), "py" + major]
    for minor in range(python_version[1] - 1, -1, -1):
        versions.append("py" + major + str(minor))
    return versions

def _compatible_tags(python_version, interpreter, platforms):
    tags = []
    platforms = [p.lower() for p in platforms]
    py_versions = _py_interpreter_range(python_version)
    for version in py_versions:
        prefix = version + "-none-"
        tags.extend([prefix + platform for platform in platforms])

    if interpreter:
        tags.append(interpreter.lower() + "-none-any")

    tags.extend([version + "-none-any" for version in py_versions])
    return tags

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def get_supported(version = None, platforms = None, impl = None, abis = None):
    """Return a list of supported tags, most preferred first.

    A port of pip's `get_supported()` (`pip/_internal/utils/compatibility_tags.py`)
    on top of packaging's `cpython_tags()`, `generic_tags()` and
    `compatible_tags()`. Each requested platform is expanded into the
    platforms it is compatible with, as pip does for `--platform`:

    * `macosx*_X_Y_<arch>`: packaging's `mac_platforms((X, Y), arch)`. As in
      pip, a custom prefix such as `macosxcustom_` is kept.
    * `ios*_X_Y_<multiarch>`: packaging's `ios_platforms()`, likewise.
    * `android_N_<abi>`: packaging's `android_platforms()`.

    Differences from pip, all because this runs at analysis time without a
    host interpreter:

    * `manylinux_X_Y_<arch>`, legacy `manylinux1/2010/2014_<arch>` and
      `musllinux_X_Y_<arch>` are fully expanded, as packaging 26.3 does for the
      host platform in `_linux_platforms()`: native `linux_<arch>` first, then
      every older glibc/musl version with legacy aliases and `armv8l` ->
      `armv7l` fallback. pip only maps `manylinux2014` -> `manylinux2010`/
      `manylinux1` and `manylinux2010` -> `manylinux1`. As in packaging,
      nothing older than glibc 2.17 is emitted on architectures other than
      x86_64/i686, so `manylinux2010_aarch64` expands to just `linux_aarch64`.
    * `platforms=None`, `[]`, or platforms that all expand to nothing (e.g.
      `macosx_9_0_x86_64`) mean `["any"]`, and `abis=None` means no
      interpreter-specific ABIs; pip uses the host's platforms and ABIs.
      `version` is required and `impl` defaults to `"cp"`.
    * Every `"abi3"` and `"none"` entry (plus `"abi3t"` for free-threaded
      builds) in `abis` is ignored for CPython; packaging only removes the
      first occurrence of each.

    Tags are lowercase, like packaging's `Tag`.

    Args:
        version: The Python version string (e.g., "311").
        platforms: A list of allowed platforms.
        impl: The interpreter implementation prefix (e.g., "cp").
        abis: A list of ABIs.

    Returns:
        A list of compatibility tag strings.
    """
    if not version:
        fail("version is required")

    python_version = get_python_version(version)
    if not impl:
        impl = "cp"

    # Like pip's _get_custom_interpreter(): the version string is used verbatim.
    interpreter = impl + version

    # pip falls back to the host platforms when there are no platforms left
    # after expansion; there is no host platform here, so use "any".
    expanded_platforms = expand_allowed_platforms(platforms) or ["any"]

    if impl == "cp":
        supported = cpython_tags(python_version, abis, expanded_platforms)
    else:
        supported = _generic_tags(interpreter, abis, expanded_platforms)

    supported.extend(_compatible_tags(python_version, interpreter, expanded_platforms))
    return supported

def tag_str(tag):
    """Returns the `interpreter-abi-platform` string form of a Tag struct.

    Args:
        tag: A Tag struct, as returned by `parse_tag`.

    Returns:
        The tag string, e.g. "py3-none-any".
    """
    return tag.interpreter + "-" + tag.abi + "-" + tag.platform

def _dedupe(items):
    if len(items) <= 1:
        return items
    seen = {}
    out = []
    for item in items:
        if item not in seen:
            seen[item] = True
            out.append(item)
    return out

def _is_valid_interpreter(s):
    if not s:
        return False
    c = s[0]
    if c < "\200" and c not in _IDENT_START:
        return False
    rest = s.lstrip(_IDENT_CHARS)
    if not rest:
        return True

    # buildifier: disable=string-iteration
    for ch in rest.elems():
        if ch < "\200" and ch not in _IDENT_CHARS:
            return False
    return True

def parse_tag(tag, validate_order = False):
    """Parses the provided tag into a list of Tag structs.

    A compressed tag set such as `py2.py3-none-any` expands to one Tag per
    combination. packaging returns a `frozenset`; this returns a list without
    duplicates, in the order the components appear in the tag. Tag structs
    have `interpreter`, `abi` and `platform` fields, are lowercased like
    packaging's `Tag`, and compare equal by value.

    Like packaging 26.3, empty components (e.g. `py3--any`, `py3-none-any.`)
    and non-identifier interpreter tags (e.g. `2-none-any`) fail.

    Args:
        tag: The tag to parse (e.g., "py3-none-any").
        validate_order: Whether to check if compressed tag set components are in sorted order.

    Returns:
        A list of Tag structs.
    """
    if "." not in tag:
        components = tag.lower().split("-")
        if len(components) != 3:
            fail("Invalid tag: {}".format(tag))
        for component in components:
            if not component:
                fail("Invalid tag: tag {} has an empty component: {}".format(repr(tag), repr(component)))
        if not _is_valid_interpreter(components[0]):
            fail("Invalid tag: tag {} has an invalid interpreter: {}".format(repr(tag), repr(components[0])))
        return [struct(
            interpreter = components[0],
            abi = components[1],
            platform = components[2],
        )]

    raw_components = tag.split("-")
    if len(raw_components) != 3:
        fail("Invalid tag: {}".format(tag))
    for component in raw_components:
        if not component or "" in component.split("."):
            fail("Invalid tag: tag {} has an empty component: {}".format(repr(tag), repr(component)))

    if validate_order:
        for component in raw_components:
            if "." in component:
                parts = component.split(".")
                if parts != sorted(parts):
                    fail("Tag component {} is not in sorted order per PEP 425".format(component))

    components = tag.lower().split("-")
    interpreters = _dedupe(components[0].split(".")) if "." in components[0] else [components[0]]
    for interpreter in interpreters:
        if not _is_valid_interpreter(interpreter):
            fail("Invalid tag: tag {} has an invalid interpreter: {}".format(repr(tag), repr(interpreter)))
    abis = _dedupe(components[1].split(".")) if "." in components[1] else [components[1]]
    platforms = _dedupe(components[2].split(".")) if "." in components[2] else [components[2]]

    return [
        struct(interpreter = interpreter, abi = abi, platform = platform_)
        for interpreter in interpreters
        for abi in abis
        for platform_ in platforms
    ]

def priority_map(supported):
    """Builds a `{tag string: rank}` map from an ordered list of supported tags.

    Rank 0 is the most preferred tag. If a tag appears more than once, its
    first (best) rank is kept. Build the map once and reuse it with
    `select_compatible`, or look up `tag_str(tag)` directly, instead of
    scanning the supported tag list for every candidate.

    Args:
        supported: An ordered list of supported tags, most preferred first, as
            returned by `get_supported`. Entries may be tag strings (which are
            lowercased) or Tag structs. Compressed tag sets are not expanded.

    Returns:
        A dict mapping each tag string to its rank.
    """
    ranks = {}
    rank = 0
    for tag in supported:
        key = tag.lower() if type(tag) == "string" else (tag.interpreter + "-" + tag.abi + "-" + tag.platform)
        if key not in ranks:
            ranks[key] = rank
        rank += 1
    return ranks

def select_compatible(supported, tagged):
    """Orders things by their best-matching supported tag.

    A port of packaging's `create_compatible_tags_selector()`. Things with no
    supported tag are dropped. The rest are sorted by the rank of their best
    supported tag; ties keep their input order. To pick the best wheel, take
    the first element of the result.

    Args:
        supported: An ordered list of supported tags (most preferred first), or
            a map returned by `priority_map`. Pass a precomputed map when
            calling this repeatedly with the same supported tags.
        tagged: A list of `(thing, tags)` tuples, where `tags` is a list of Tag
            structs (e.g. `parse_wheel_filename(f).tags`) or tag strings.
            Compressed tag strings such as `py2.py3-none-any` are expanded
            with `parse_tag`.

    Returns:
        The compatible things, best match first.
    """
    ranks = supported if type(supported) == "dict" else priority_map(supported)
    ranked = []
    things = []
    for thing, thing_tags in tagged:
        best = None
        for t in thing_tags:
            if type(t) == "string":
                if "." in t:
                    for x in parse_tag(t):
                        rank = ranks.get(x.interpreter + "-" + x.abi + "-" + x.platform)
                        if rank != None and (best == None or rank < best):
                            best = rank
                else:
                    rank = ranks.get(t.lower())
                    if rank != None and (best == None or rank < best):
                        best = rank
            else:
                rank = ranks.get(t.interpreter + "-" + t.abi + "-" + t.platform)
                if rank != None and (best == None or rank < best):
                    best = rank
        if best != None:
            ranked.append((best, len(things)))
            things.append(thing)
    return [things[i] for _, i in sorted(ranked)]

# Exported struct
tags = struct(
    get_supported = get_supported,
    parse_tag = parse_tag,
    priority_map = priority_map,
    select_compatible = select_compatible,
    tag_str = tag_str,
)
