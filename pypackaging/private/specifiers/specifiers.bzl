"""PEP 440 Version Specifiers.

Derived from pypa/packaging: packaging/specifiers.py (Apache 2.0 / BSD).
Baseline: pypa/packaging 26.2
"""

load("@re.bzl", "re")
load("//pypackaging/private/version:version.bzl", "get_public_key", "make_version", "parse_version")

def _fail_invalid_specifier(spec):
    fail("Invalid specifier: {}".format(spec))

def _post_base(v):
    return make_version(v.epoch, v.release, v.pre, None, None, None)

def _earliest_prerelease(v):
    return make_version(v.epoch, v.release, v.pre, v.post, ("dev", 0), None)

_PRE_POST_DEV_RE_STR = r"""
(?:
    [-_\.]?
    (?:alpha|beta|preview|pre|a|b|c|rc)
    [-_\.]?
    [0-9]*
)?
(?:
    (?:-[0-9]+)|(?:[-_\.]?(?:post|rev|r)[-_\.]?[0-9]*)
)?
(?:[-_\.]?dev[-_\.]?[0-9]*)?
"""

_EQ_VERSION_RE = re.compile(
    r"""
    v?
    (?:[0-9]+!)?
    [0-9]+(?:\.[0-9]+)*
    (?:
        \.\*
        |
        """ + _PRE_POST_DEV_RE_STR + r"""
        (?:\+[a-z0-9]+(?:[-_\.][a-z0-9]+)*)?
    )?
    """,
    re.X | re.I,
)

_COMPAT_VERSION_RE = re.compile(
    r"""
    v?
    (?:[0-9]+!)?
    [0-9]+(?:\.[0-9]+)+
    """ + _PRE_POST_DEV_RE_STR,
    re.X | re.I,
)

_CMP_VERSION_RE = re.compile(
    r"""
    v?
    (?:[0-9]+!)?
    [0-9]+(?:\.[0-9]+)*
    """ + _PRE_POST_DEV_RE_STR,
    re.X | re.I,
)

_DIGITS_AND_DOT = ".0123456789"
_INVALID_ARBITRARY_CHARS = (" ", "\t", "\n", "\r", "\f", "\v", "\034", "\035", "\036", "\037", ";", ")")

def _is_plain_release(version, min_segments = 1):
    """Returns True if version is a valid dot-separated numeric release, False if invalid, or None if non-numeric."""
    if not version or version.lstrip(_DIGITS_AND_DOT):
        return None
    parts = version.split(".")
    return len(parts) >= min_segments and "" not in parts

def parse_specifier(spec_str):
    """Parses a single specifier string.

    Args:
        spec_str: The specifier string to parse.

    Returns:
        A struct representing the parsed specifier.
    """
    stripped = spec_str.strip()
    if stripped.startswith("==="):
        operator, version = "===", stripped[3:].strip()
        for c in _INVALID_ARBITRARY_CHARS:
            if c in version:
                _fail_invalid_specifier(spec_str)
    elif stripped.startswith(("==", "!=")):
        operator, version = stripped[:2], stripped[2:].strip()
        plain = _is_plain_release(version)
        if plain == False or (plain == None and not _EQ_VERSION_RE.fullmatch(version)):
            _fail_invalid_specifier(spec_str)
    elif stripped.startswith("~="):
        operator, version = "~=", stripped[2:].strip()
        plain = _is_plain_release(version, min_segments = 2)
        if plain == False or (plain == None and not _COMPAT_VERSION_RE.fullmatch(version)):
            _fail_invalid_specifier(spec_str)
    elif stripped.startswith(("<=", ">=")):
        operator, version = stripped[:2], stripped[2:].strip()
        plain = _is_plain_release(version)
        if plain == False or (plain == None and not _CMP_VERSION_RE.fullmatch(version)):
            _fail_invalid_specifier(spec_str)
    elif stripped.startswith(("<", ">")):
        operator, version = stripped[:1], stripped[1:].strip()
        plain = _is_plain_release(version)
        if plain == False or (plain == None and not _CMP_VERSION_RE.fullmatch(version)):
            _fail_invalid_specifier(spec_str)
    else:
        _fail_invalid_specifier(spec_str)
        return None  # Unreachable

    return struct(
        operator = operator,
        version = version,
    )

def specifier_contains(spec, version_str):
    """Checks if a version satisfies a specifier.

    Args:
        spec: The specifier struct.
        version_str: The version string to check.

    Returns:
        True if the version satisfies the specifier, False otherwise.
    """
    if spec.operator == "===":
        return version_str.lower() == spec.version.lower()

    v1 = parse_version(version_str)

    if spec.operator == "==":
        if spec.version.endswith(".*"):
            spec_v = parse_version(spec.version[:-2])
            if v1.epoch != spec_v.epoch:
                return False

            # Pad v1.release with zeros if it is shorter than spec_v.release
            v1_release = list(v1.release)
            if len(v1_release) < len(spec_v.release):
                v1_release.extend([0] * (len(spec_v.release) - len(v1_release)))

            return tuple(v1_release[:len(spec_v.release)]) == spec_v.release
        else:
            v2 = parse_version(spec.version)
            v1_key = get_public_key(v1) if not v2.local else v1.key
            return v1_key == v2.key

    if spec.operator == "!=":
        if spec.version.endswith(".*"):
            spec_v = parse_version(spec.version[:-2])
            if v1.epoch != spec_v.epoch:
                return True

            # Pad v1.release with zeros if it is shorter than spec_v.release
            v1_release = list(v1.release)
            if len(v1_release) < len(spec_v.release):
                v1_release.extend([0] * (len(spec_v.release) - len(v1_release)))

            return tuple(v1_release[:len(spec_v.release)]) != spec_v.release
        else:
            v2 = parse_version(spec.version)
            v1_key = get_public_key(v1) if not v2.local else v1.key
            return v1_key != v2.key

    v2 = parse_version(spec.version)

    if spec.operator == ">=":
        return get_public_key(v1) >= v2.key

    if spec.operator == "<=":
        return get_public_key(v1) <= v2.key

    if spec.operator == ">":
        if not v1.key > v2.key:
            return False

        if not v2.is_postrelease and v1.is_postrelease and _post_base(v1).key == v2.key:
            return False

        if v1.local != None and get_public_key(v1) == v2.key:
            return False

        return True

    if spec.operator == "<":
        if not v1.key < v2.key:
            return False

        if not v2.is_prerelease and v1.is_prerelease and v1.key >= _earliest_prerelease(v2).key:
            return False

        return True

    if spec.operator == "~=":
        if len(v2.release) < 2:
            fail("Compatible operator ~= requires at least two release segments")

        if not (get_public_key(v1) >= v2.key):
            return False

        prefix_release = v2.release[:-1]

        if v1.epoch != v2.epoch:
            return False
        if len(v1.release) < len(prefix_release):
            return False
        return v1.release[:len(prefix_release)] == prefix_release

    fail("Operator {} not implemented".format(spec.operator))

def parse_specifier_set(spec_set_str):
    """Parses a comma-separated set of specifiers.

    Args:
        spec_set_str: The specifier set string to parse.

    Returns:
        A struct representing the parsed specifier set.
    """
    if not spec_set_str:
        return struct(specs = [])

    spec_strs = [s.strip() for s in spec_set_str.split(",")]
    specs = [parse_specifier(s) for s in spec_strs]

    return struct(
        specs = specs,
    )

def specifier_set_contains(spec_set, version_str):
    """Checks if a version satisfies all specifiers in the set.

    Args:
        spec_set: The specifier set struct.
        version_str: The version string to check.

    Returns:
        True if the version satisfies all specifiers, False otherwise.
    """
    for spec in spec_set.specs:
        if not specifier_contains(spec, version_str):
            return False
    return True

specifiers = struct(
    parse = parse_specifier,
    contains = specifier_contains,
    parse_set = parse_specifier_set,
    set_contains = specifier_set_contains,
)
