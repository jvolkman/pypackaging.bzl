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

def _expand_platform(platform):
    """Expands a single platform into its compatible platforms.

    Returns:
        A tuple `(platforms, linux_fallbacks)`. `linux_fallbacks` holds the
        generic `linux_<arch>` platforms implied by a manylinux/musllinux
        platform. They are returned separately because packaging gives them
        the lowest priority, after every manylinux and musllinux platform.
    """
    if platform.startswith("macosx_"):
        parts = platform.split("_")
        if len(parts) >= 4:
            if parts[1].isdigit() and parts[2].isdigit():
                major = int(parts[1])
                minor = int(parts[2])
                arch = "_".join(parts[3:])
                return mac_platforms((major, minor), arch), []
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
        parts = platform.split("_")
        if len(parts) >= 3:
            if parts[1].isdigit():
                api_level = int(parts[1])
                abi = "_".join(parts[2:])
                return android_platforms(api_level, abi), []
    elif platform.startswith("ios_"):
        parts = platform.split("_")
        if len(parts) >= 4:
            if parts[1].isdigit() and parts[2].isdigit():
                major = int(parts[1])
                minor = int(parts[2])
                multiarch = "_".join(parts[3:])
                return ios_platforms(major, minor, multiarch), []

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
    """Return a list of supported tags.

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

# Exported struct
tags = struct(
    get_supported = get_supported,
    parse_tag = parse_tag,
)

tags_internal = struct(
    expand_allowed_platforms = _expand_allowed_platforms,
)
