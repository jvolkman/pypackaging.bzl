"""Platform tag generation logic derived from pip and packaging.tags.

Derived from pypa/pip: pip/_internal/utils/compatibility_tags.py (MIT)
and pypa/packaging: packaging/tags.py (Apache 2.0 / BSD).
See README.md for details.
"""

load("//pypackaging/private/tags:android.bzl", "android_platforms")
load("//pypackaging/private/tags:compatible.bzl", "compatible_tags")
load("//pypackaging/private/tags:cpython.bzl", "cpython_tags")
load("//pypackaging/private/tags:generic.bzl", "generic_tags")
load("//pypackaging/private/tags:ios.bzl", "ios_platforms")
load("//pypackaging/private/tags:macos.bzl", "mac_platforms")
load("//pypackaging/private/tags:manylinux.bzl", "manylinux_platforms")
load("//pypackaging/private/tags:musllinux.bzl", "musllinux_platforms")
load("//pypackaging/private/tags:utils.bzl", "get_python_version")

_ARCH_FALLBACKS = {
    "armv8l": ["armv8l", "armv7l"],
}

def _linux_fallbacks(archs):
    return ["linux_" + a for a in archs]

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

def _expand_platform(platform):
    """Expands a single platform into its compatible platforms.

    Returns:
        A tuple `(platforms, linux_fallbacks)`. `linux_fallbacks` holds the
        generic `linux_<arch>` platforms implied by a manylinux/musllinux
        platform. They are returned separately because packaging gives them
        the lowest priority, after every manylinux and musllinux platform.
    """
    if platform.startswith("macosx"):
        # Like pip, any "macosx*" prefix is accepted and kept, e.g.
        # "macosxcustom_10_9_x86_64" -> "macosxcustom_10_8_x86_64", ...
        m = _match_apple_platform(platform)
        if m:
            name, major, minor, arch = m
            return [
                "{}_{}".format(name, p[len("macosx_"):])
                for p in mac_platforms((major, minor), arch)
            ], []
    elif platform.startswith("ios"):
        m = _match_apple_platform(platform)
        if m:
            name, major, minor, multiarch = m
            return [
                "{}_{}".format(name, p[len("ios_"):])
                for p in ios_platforms(major, minor, multiarch)
            ], []
    elif platform.startswith("manylinux_"):
        parts = platform.split("_")
        if len(parts) >= 4:
            if parts[1].isdigit() and parts[2].isdigit():
                major = int(parts[1])
                minor = int(parts[2])
                arch = "_".join(parts[3:])
                archs = _ARCH_FALLBACKS.get(arch, [arch])

                result = []
                for a in archs:
                    result.extend(manylinux_platforms((major, minor), a))
                return result, _linux_fallbacks(archs)
    elif platform.startswith("manylinux"):
        parts = platform.split("_", 1)
        if len(parts) == 2:
            prefix = parts[0]
            arch = parts[1]
            archs = _ARCH_FALLBACKS.get(arch, [arch])
            legacy_to_pep600 = {
                "manylinux1": (2, 5),
                "manylinux2010": (2, 12),
                "manylinux2014": (2, 17),
            }
            version = legacy_to_pep600.get(prefix)
            if version:
                result = []
                for a in archs:
                    result.extend(manylinux_platforms(version, a))
                return result, _linux_fallbacks(archs)
    elif platform.startswith("musllinux_"):
        parts = platform.split("_")
        if len(parts) >= 4:
            if parts[1].isdigit() and parts[2].isdigit():
                major = int(parts[1])
                minor = int(parts[2])
                arch = "_".join(parts[3:])
                archs = _ARCH_FALLBACKS.get(arch, [arch])

                result = []
                for a in archs:
                    result.extend(musllinux_platforms((major, minor), a))
                return result, _linux_fallbacks(archs)
    elif platform.startswith("android_"):
        # Equivalent to pip's re.fullmatch(r"android_(\d+)_(.+)", platform).
        parts = platform.split("_", 2)
        if len(parts) == 3 and parts[1].isdigit() and parts[2]:
            return android_platforms(int(parts[1]), parts[2]), []

    return [platform], []

def _expand_allowed_platforms(platforms):
    if not platforms:
        return []

    seen = {}
    result = []
    deferred = []

    for p in platforms:
        if p in seen:
            continue
        additions, linux_fallbacks = _expand_platform(p)
        for add in additions:
            if add not in seen:
                seen[add] = True
                result.append(add)
        deferred.extend(linux_fallbacks)

    # Like packaging's `_linux_platforms()`, the generic `linux_<arch>`
    # platforms come after all manylinux/musllinux platforms.
    for add in deferred:
        if add not in seen:
            seen[add] = True
            result.append(add)

    return result

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
      `musllinux_X_Y_<arch>` are fully expanded, as packaging does for the host
      platform in `_linux_platforms()`: every older glibc/musl version, the
      legacy aliases, an `armv8l` -> `armv7l` fallback, and finally
      `linux_<arch>` (after all other expanded platforms). pip only maps
      `manylinux2014` -> `manylinux2010`/`manylinux1` and `manylinux2010` ->
      `manylinux1`. As in packaging, nothing older than glibc 2.17 is emitted
      on architectures other than x86_64/i686, so `manylinux2010_aarch64`
      expands to just `linux_aarch64`.
    * `platforms=None` or `[]` means `["any"]`, and `abis=None` means no
      interpreter-specific ABIs; pip uses the host's platforms and ABIs. If no
      platform remains after expansion (e.g. `macosx_9_0_x86_64`), only the
      platform-independent `*-none-any` tags are returned. `version` is
      required and `impl` defaults to `"cp"`.
    * Every `"abi3"` and `"none"` entry in `abis` is ignored for CPython;
      packaging only removes the first occurrence of each.

    Tags are lowercase, like packaging's `Tag`.

    Args:
        version: The Python version string (e.g., "311").
        platforms: A list of allowed platforms.
        impl: The interpreter implementation prefix (e.g., "cp").
        abis: A list of ABIs.

    Returns:
        A list of compatibility tag strings.
    """
    supported = []

    if version:
        python_version = get_python_version(version)
    else:
        fail("version is required")

    if not impl:
        impl = "cp"

    # Like pip's _get_custom_interpreter(): the version string is used verbatim.
    interpreter = impl + version

    if not platforms:
        expanded_platforms = ["any"]
    else:
        expanded_platforms = _expand_allowed_platforms(platforms)

    is_cpython = impl == "cp"
    if is_cpython:
        supported.extend(cpython_tags(python_version, abis, expanded_platforms))
    else:
        supported.extend(generic_tags(interpreter, abis, expanded_platforms))

    supported.extend(compatible_tags(python_version, interpreter, expanded_platforms))

    return supported

def tag_str(tag):
    """Returns the `interpreter-abi-platform` string form of a Tag struct.

    Args:
        tag: A Tag struct, as returned by `parse_tag`.

    Returns:
        The tag string, e.g. "py3-none-any".
    """
    return "{}-{}-{}".format(tag.interpreter, tag.abi, tag.platform)

def _make_tag(interpreter, abi, platform):
    return struct(
        interpreter = interpreter.lower(),
        abi = abi.lower(),
        platform = platform.lower(),
    )

def parse_tag(tag, validate_order = False):
    """Parses the provided tag into a list of Tag structs.

    A compressed tag set such as `py2.py3-none-any` expands to one Tag per
    combination. packaging returns a `frozenset`; this returns a list without
    duplicates, in the order the components appear in the tag. Tag structs
    have `interpreter`, `abi` and `platform` fields, are lowercased like
    packaging's `Tag`, and compare equal by value.

    Like packaging, empty components (e.g. `py3--any`) are not rejected; they
    produce tags with empty fields that never match a supported tag.

    Args:
        tag: The tag to parse (e.g., "py3-none-any").
        validate_order: Whether to check if compressed tag set components are in sorted order.

    Returns:
        A list of Tag structs.
    """
    components = tag.split("-")
    if len(components) != 3:
        fail("Invalid tag: {}".format(tag))

    component_parts = [component.split(".") for component in components]
    if validate_order:
        for parts in component_parts:
            if parts != sorted(parts):
                fail("Tag component {} is not in sorted order per PEP 425".format(".".join(parts)))

    interpreters, abis, platforms = component_parts

    seen = {}
    result = []
    for interpreter in interpreters:
        for abi in abis:
            for platform_ in platforms:
                t = _make_tag(interpreter, abi, platform_)
                key = tag_str(t)
                if key not in seen:
                    seen[key] = True
                    result.append(t)

    return result

def _tag_key(tag):
    if type(tag) == "string":
        return tag.lower()
    return tag_str(tag)

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
    for rank in range(len(supported)):
        key = _tag_key(supported[rank])
        if key not in ranks:
            ranks[key] = rank
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

    Returns:
        The compatible things, best match first.
    """
    ranks = supported if type(supported) == "dict" else priority_map(supported)
    ranked = []
    things = []
    for thing, thing_tags in tagged:
        best = None
        for t in thing_tags:
            rank = ranks.get(_tag_key(t))
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

tags_internal = struct(
    expand_allowed_platforms = _expand_allowed_platforms,
)
