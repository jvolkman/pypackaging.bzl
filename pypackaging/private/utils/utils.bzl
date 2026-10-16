"""Utilities for packaging.

Derived from pypa/packaging: packaging/utils.py (Apache 2.0 / BSD).
"""

load("@re.bzl", "re")
load("//pypackaging/private/tags:tags.bzl", "tags")
load("//pypackaging/private/version:version.bzl", "version")

_LOWER = "abcdefghijklmnopqrstuvwxyz"
_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
_DIGITS = "0123456789"
_VALID_NORMALIZED_START = _LOWER + _DIGITS
_VALID_NORMALIZED_CHAR = _VALID_NORMALIZED_START + "-"

# ASCII characters not matched by packaging's r"[\w\d._]" (re.UNICODE): ASCII
# control characters, space and punctuation other than "_" and ".".
_INVALID_ASCII_WHEEL_NAME_CHARS = (
    "\000\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017" +
    "\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037" +
    "\177 !\"#$%&'()*+,-/:;<=>?@[\\]^`{|}~"
)
_VALID_NAME_START = _LOWER + _UPPER + _DIGITS
_VALID_NAME_CHAR = _VALID_NAME_START + "._-"

# PEP 440 version pattern, as used by version.parse(). It is needed here to
# detect invalid versions without failing, since Starlark can't catch fail().
_VERSION_RE = re.compile(r"""
    v?
    (?:
        (?:[0-9]+!)?
        [0-9]+(?:\.[0-9]+)*
        (?:[._-]?(?:alpha|a|beta|b|preview|pre|c|rc)[._-]?[0-9]*)?
        (?:
            (?:-[0-9]+)
            |
            (?:[._-]?(?:post|rev|r)[._-]?[0-9]*)
        )?
        (?:[._-]?dev[._-]?[0-9]*)?
    )
    (?:\+[a-z0-9]+(?:[._-][a-z0-9]+)*)?
""", re.X | re.I)

def _try_parse_version(version_str):
    """Parses a version like packaging's Version(), or returns None if invalid.

    Leading and trailing whitespace is ignored, like packaging.
    """
    version_str = version_str.strip()
    if not _VERSION_RE.fullmatch(version_str):
        return None
    return version.parse(version_str)

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

    With `strip_trailing_zero = False`, the result is the normalized PEP 440
    form, i.e. packaging's `str(Version(...))`.

    Args:
        version_input: The version to canonicalize (string or Version struct).
            A string that isn't a valid PEP 440 version is returned unchanged,
            like packaging. Leading and trailing whitespace is ignored.
        strip_trailing_zero: Whether to strip trailing zeros from the release
            segment (e.g. "1.0.0" -> "1").

    Returns:
        The canonicalized version string.
    """
    v = version_input
    if type(v) == "string":
        v = _try_parse_version(version_input)
        if v == None:
            return version_input

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

def _is_valid_wheel_name(name):
    # Equivalent to packaging's re.match(r"^[\w\d._]*$", name, re.UNICODE),
    # except that every non-ASCII character is accepted: Starlark can't tell
    # Unicode letters and digits from other characters.

    # buildifier: disable=string-iteration
    for c in name.elems():
        if c in _INVALID_ASCII_WHEEL_NAME_CHARS:
            return False
    return True

def parse_wheel_filename(filename, validate_order = False):
    """Parses the filename of a wheel file.

    The returned struct has these fields:

    * `name`: the project name, normalized with `canonicalize_name`.
    * `version`: the Version struct. Its `version_str` field is the version
      text exactly as it appears in the filename (e.g. `1.0.0.RC1`). For the
      normalized form (packaging's `str(version)`, e.g. `1.0.0rc1`), use
      `canonicalize_version(version, strip_trailing_zero = False)`.
    * `build`: `()` or a `(number, suffix)` build tag tuple, e.g. `(1, "abc")`.
    * `tags`: a list of Tag structs, as returned by `tags.parse_tag`.

    Like packaging, the project name may contain non-ASCII characters. Any
    non-ASCII character is accepted, where packaging only accepts Unicode
    word characters.

    Args:
        filename: The filename to parse.
        validate_order: Whether to fail if compressed tag set components
            aren't in sorted order (PEP 425).

    Returns:
        A struct containing name, version, build, and tags.
    """
    if not filename.endswith(".whl"):
        fail("Invalid wheel filename (extension must be '.whl'): {}".format(repr(filename)))

    filename = filename[:-4]
    dashes = filename.count("-")
    if dashes not in (4, 5):
        fail("Invalid wheel filename (wrong number of parts): {}".format(repr(filename)))

    parts = filename.split("-", dashes - 2)
    name_part = parts[0]

    # See PEP 427 for the rules on escaping the project name.
    if "__" in name_part or not _is_valid_wheel_name(name_part):
        fail("Invalid project name: {}".format(repr(filename)))

    name = canonicalize_name(name_part)

    ver = _try_parse_version(parts[1])
    if ver == None:
        fail("Invalid wheel filename (invalid version): {}".format(repr(filename)))

    if dashes == 5:
        build_part = parts[2]

        # Equivalent to regex: ^(\d+)(.*)$
        if not build_part or build_part[0] not in _DIGITS:
            fail("Invalid build number: {} in {}".format(build_part, repr(filename)))

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
    if validate_order:
        for component in tag_str.split("-"):
            component_parts = component.split(".")
            if component_parts != sorted(component_parts):
                fail("Invalid wheel filename (compressed tag set components must be in sorted order per PEP 425): {}".format(repr(filename)))
    parsed_tags = tags.parse_tag(tag_str)

    return struct(
        name = name,
        version = ver,
        build = build,
        tags = parsed_tags,
    )

def parse_sdist_filename(filename):
    """Parses the filename of a sdist file.

    The returned struct has these fields:

    * `name`: the project name, normalized with `canonicalize_name`.
    * `version`: the Version struct. Its `version_str` field is the version
      text exactly as it appears in the filename. For the normalized form, use
      `canonicalize_version(version, strip_trailing_zero = False)`.

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
        fail("Invalid sdist filename (extension must be '.tar.gz' or '.zip'): {}".format(repr(filename)))

    # We are requiring a PEP 440 version, which cannot contain dashes,
    # so we split on the last dash.
    idx = file_stem.rfind("-")
    if idx == -1:
        fail("Invalid sdist filename: {}".format(repr(filename)))

    name_part = file_stem[:idx]
    version_part = file_stem[idx + 1:]

    name = canonicalize_name(name_part)
    ver = _try_parse_version(version_part)
    if ver == None:
        fail("Invalid sdist filename (invalid version): {}".format(repr(filename)))

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
