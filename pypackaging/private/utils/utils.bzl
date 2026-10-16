"""Utilities for packaging.

Derived from pypa/packaging: packaging/utils.py (Apache 2.0 / BSD).
"""

load("//pypackaging/private/tags:tags.bzl", "tags")
load("//pypackaging/private/version:version.bzl", "version")

_LOWER = "abcdefghijklmnopqrstuvwxyz"
_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
_DIGITS = "0123456789"
_VALID_NORMALIZED_START = _LOWER + _DIGITS
_VALID_NORMALIZED_CHAR = _VALID_NORMALIZED_START + "-"
_VALID_WHEEL_NAME_CHARS = _LOWER + _UPPER + _DIGITS + "._"
_VALID_NAME_START = _LOWER + _UPPER + _DIGITS
_VALID_NAME_CHAR = _VALID_NAME_START + "._-"

def _is_valid_name(name):
    # Equivalent to packaging's
    # re.fullmatch(r"[a-z0-9]|[a-z0-9][a-z0-9._-]*[a-z0-9]", name, re.I | re.A).
    if not name:
        return False
    if name[0] not in _VALID_NAME_START or name[-1] not in _VALID_NAME_START:
        return False

    # buildifier: disable=string-iteration
    for c in name.elems():
        if c not in _VALID_NAME_CHAR:
            return False
    return True

def canonicalize_name(name, validate = False):
    """Takes a valid Python package or extra name, and returns the normalized form of it.

    Lowercases the name and replaces runs of `-`, `_` and `.` with a single `-`
    (PEP 503). Starlark's `lower()` only lowercases ASCII letters, so unlike
    packaging, non-ASCII letters are left unchanged. Valid distribution names
    are ASCII-only, so this only matters when `validate` is False.

    Args:
        name: The name to normalize.
        validate: If True, `fail()` unless `name` is a valid distribution name
            per the core metadata spec (ASCII letters and digits, with `.`,
            `_` and `-` allowed except at the start and end), like packaging
            raising `InvalidName`.

    Returns:
        The normalized name.
    """
    if validate and not _is_valid_name(name):
        fail("name is invalid: {}".format(repr(name)))

    value = name.lower().replace("_", "-").replace(".", "-")

    # Collapse repeats
    for _i in range(len(value)):
        if "--" in value:
            value = value.replace("--", "-")
        else:
            break
    return value

def is_normalized_name(name):
    """Check if a name is already normalized.

    Args:
        name: The name to check.

    Returns:
        True if normalized, False otherwise.
    """

    # Equivalent to regex: ^[a-z0-9]+(?:-[a-z0-9]+)*$
    if not name:
        return False

    if name[0] not in _VALID_NORMALIZED_START:
        return False

    if name[-1] not in _VALID_NORMALIZED_START:
        return False

    if "--" in name:
        return False

    # buildifier: disable=string-iteration
    for c in name.elems():
        if c not in _VALID_NORMALIZED_CHAR:
            return False

    return True

def canonicalize_version(version_input, strip_trailing_zero = True):
    """Return a canonical form of a version as a string.

    Args:
        version_input: The version to canonicalize (string or Version struct).
        strip_trailing_zero: Whether to strip trailing zeros.

    Returns:
        The canonicalized version string.
    """
    v = version_input
    if type(v) == "string":
        # Upstream returns unaltered if invalid.
        # We try to parse, if it fails (returns None or fails), we return the original string.
        # But our parse_version fails hard via fail().
        # Let's assume valid for now or handle failure if we can catch it (Starlark can't catch easily).
        v = version.parse(version_input)

    # Reconstruct string, potentially stripping trailing zeros.
    release = v.release
    if strip_trailing_zero:
        rel_list = list(release)
        i = len(rel_list)
        for _ in range(len(rel_list)):
            if i > 1 and rel_list[i - 1] == 0:
                i -= 1
            else:
                break
        release = tuple(rel_list[:i])

    version_str = ".".join([str(p) for p in release])
    if v.epoch:
        version_str = "{}!{}".format(v.epoch, version_str)
    if v.pre:
        version_str += "".join([str(p) for p in v.pre])
    if v.post:
        version_str += ".post{}".format(v.post[1])
    if v.dev:
        version_str += ".dev{}".format(v.dev[1])
    if v.local:
        version_str += "+{}".format(".".join([str(p) for p in v.local]))

    return version_str

def parse_wheel_filename(filename, validate_order = False):
    """Parses the filename of a wheel file.

    Args:
        filename: The filename to parse.
        validate_order: Whether to validate tag order.

    Returns:
        A struct containing name, version, build, and tags.
    """
    if not filename.endswith(".whl"):
        fail("Invalid wheel filename (extension must be '.whl'): {}".format(filename))

    filename = filename[:-4]
    dashes = filename.count("-")
    if dashes not in (4, 5):
        fail("Invalid wheel filename (wrong number of parts): {}".format(filename))

    parts = filename.split("-", dashes - 2)
    name_part = parts[0]

    # Equivalent to regex: ^[\w._]*$
    is_valid_wheel_name = True

    # buildifier: disable=string-iteration
    for c in name_part.elems():
        if c not in _VALID_WHEEL_NAME_CHARS:
            is_valid_wheel_name = False
            break

    if "__" in name_part or not is_valid_wheel_name:
        fail("Invalid project name in filename: {}".format(filename))

    name = canonicalize_name(name_part)

    # version.parse might fail hard.
    ver = version.parse(parts[1])

    if dashes == 5:
        build_part = parts[2]

        # Equivalent to regex: ^(\d+)(.*)$
        if not build_part or build_part[0] not in _DIGITS:
            fail("Invalid build number: {} in {}".format(build_part, filename))

        i = 0

        # buildifier: disable=string-iteration
        for c in build_part.elems():
            if c in _DIGITS:
                i += 1
            else:
                break

        build = (int(build_part[:i]), build_part[i:])
    else:
        build = ()

    tag_str = parts[-1]
    parsed_tags = tags.parse_tag(tag_str, validate_order = validate_order)

    return struct(
        name = name,
        version = ver,
        build = build,
        tags = parsed_tags,
    )

def parse_sdist_filename(filename):
    """Parses the filename of a sdist file.

    Args:
        filename: The filename to parse.

    Returns:
        A struct containing name and version.
    """
    if filename.endswith(".tar.gz"):
        file_stem = filename[:-7]
    elif filename.endswith(".zip"):
        file_stem = filename[:-4]
    else:
        fail("Invalid sdist filename (extension must be '.tar.gz' or '.zip'): {}".format(filename))

    # Starlark doesn't have rpartition. We can simulate it.
    idx = file_stem.rfind("-")
    if idx == -1:
        fail("Invalid sdist filename: {}".format(filename))

    name_part = file_stem[:idx]
    version_part = file_stem[idx + 1:]

    name = canonicalize_name(name_part)
    ver = version.parse(version_part)

    return struct(
        name = name,
        version = ver,
    )

utils = struct(
    canonicalize_name = canonicalize_name,
    is_normalized_name = is_normalized_name,
    canonicalize_version = canonicalize_version,
    parse_wheel_filename = parse_wheel_filename,
    parse_sdist_filename = parse_sdist_filename,
)
