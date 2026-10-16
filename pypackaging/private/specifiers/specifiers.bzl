"""PEP 440 Version Specifiers.

Derived from pypa/packaging: packaging/specifiers.py (Apache 2.0 / BSD).
Baseline: pypa/packaging 26.2
"""

load(
    "//pypackaging/private/version:version.bzl",
    "contains_whitespace",
    "get_public_key",
    "parse_stripped_version",
    "strip_whitespace",
    "try_parse_version",
    "version_key",
)

def _fail_invalid_specifier(spec):
    fail("Invalid specifier: {}".format(spec))

def _try_parse_specifier(spec_str):
    """Parses a specifier, returning None if it is invalid.

    The version is parsed once here and validated structurally: the specifier
    grammar is the PEP 440 version grammar, minus local versions for ordered
    comparisons and ~=, plus a trailing `.*` on a bare release for == and !=,
    and with at least two release segments for ~=.
    """
    stripped = strip_whitespace(spec_str)
    if stripped.startswith("==="):
        version = strip_whitespace(stripped[3:])
        if ";" in version or ")" in version or contains_whitespace(version):
            return None
        return struct(operator = "===", version = version, parsed_version = None)

    if stripped.startswith(("==", "!=", "~=", "<=", ">=")):
        operator, version = stripped[:2], strip_whitespace(stripped[2:])
    elif stripped.startswith(("<", ">")):
        operator, version = stripped[:1], strip_whitespace(stripped[1:])
    else:
        return None

    if version.endswith(".*"):
        if operator != "==" and operator != "!=":
            return None
        v = parse_stripped_version(version[:-2])
        if v == None or v.pre != None or v.post != None or v.dev != None or v.local != None:
            return None
    else:
        v = parse_stripped_version(version)
        if v == None:
            return None
        if v.local != None and operator != "==" and operator != "!=":
            return None
        if operator == "~=" and len(v.release) < 2:
            return None

    return struct(operator = operator, version = version, parsed_version = v)

def parse_specifier(spec_str):
    """Parses a single specifier string.

    Args:
        spec_str: The specifier string to parse. Fails if it isn't a valid
            PEP 440 specifier.

    Returns:
        A struct representing the parsed specifier, with these fields:

        * `operator`: one of `~=`, `==`, `!=`, `<=`, `>=`, `<`, `>`, `===`.
        * `version`: the version string as written (e.g. `1.0`, `1.0.*`).
        * `parsed_version`: the parsed version (see `version.parse`), without
          the `.*` suffix for wildcard specifiers. None for `===`.
    """
    spec = _try_parse_specifier(spec_str)
    if spec == None:
        _fail_invalid_specifier(spec_str)
    return spec

def _spec_version(spec):
    """Returns the parsed version of a non-=== specifier."""
    v = getattr(spec, "parsed_version", None)
    if v == None:
        # Support specifier structs that weren't created by parse_specifier.
        v = parse_specifier(spec.operator + spec.version).parsed_version
    return v

def _prefix_match(v, epoch, prefix):
    """Implements ==E!X.Y.*: the zero-padded release of `v` starts with `prefix`."""
    if v.epoch != epoch:
        return False
    release = v.release
    if len(release) < len(prefix):
        release = release + (0,) * (len(prefix) - len(release))
    return release[:len(prefix)] == prefix

def _equal(spec, sv, v):
    if spec.version.endswith(".*"):
        return _prefix_match(v, sv.epoch, sv.release)

    # Without a local segment in the spec, ignore the candidate's local segment.
    if sv.local == None:
        return get_public_key(v) == sv.key
    return v.key == sv.key

def _matches_parsed(spec, v):
    """Checks a parsed candidate version against a non-=== specifier."""
    operator = spec.operator
    sv = _spec_version(spec)

    if operator == "==":
        return _equal(spec, sv, v)

    if operator == "!=":
        return not _equal(spec, sv, v)

    if operator == ">=":
        return get_public_key(v) >= sv.key

    if operator == "<=":
        return get_public_key(v) <= sv.key

    if operator == ">":
        if not v.key > sv.key:
            return False

        # >V must not match a post-release of V unless V is itself a post-release.
        if not sv.is_postrelease and v.is_postrelease and version_key(v.epoch, v.release, v.pre, None, None, None) == sv.key:
            return False

        # >V must not match a local version of V.
        if v.local != None and get_public_key(v) == sv.key:
            return False

        return True

    if operator == "<":
        if not v.key < sv.key:
            return False

        # <V must not match a pre-release of V unless V is itself a pre-release.
        if not sv.is_prerelease and v.is_prerelease and v.key >= version_key(sv.epoch, sv.release, sv.pre, sv.post, ("dev", 0), None):
            return False

        return True

    if operator == "~=":
        # ~=X.Y.Z is >=X.Y.Z, ==X.Y.*. The prefix comes from the normalized
        # release, as PEP 440 says.
        if len(sv.release) < 2:
            fail("Invalid specifier: {}{} (~= requires at least two release segments)".format(operator, spec.version))
        return get_public_key(v) >= sv.key and _prefix_match(v, sv.epoch, sv.release[:-1])

    fail("Invalid specifier: unknown operator {}".format(operator))

def _matches(spec, v, version_str):
    """Checks a candidate against a specifier.

    Args:
        spec: The specifier struct.
        v: The parsed candidate version, or None if it isn't a valid version.
        version_str: The candidate version string.
    """
    if spec.operator == "===":
        return version_str.lower() == spec.version.lower()
    if v == None:
        return False
    return _matches_parsed(spec, v)

def specifier_contains(spec, version_str):
    """Checks if a version satisfies a specifier.

    Args:
        spec: The specifier struct.
        version_str: The version string to check.

    Returns:
        True if the version satisfies the specifier, False otherwise. Like
        upstream, a `version_str` that is not a valid PEP 440 version never
        matches, except that `===` compares it as a string.
    """
    if spec.operator == "===":
        return _matches(spec, None, version_str)
    return _matches(spec, try_parse_version(version_str), version_str)

def parse_specifier_set(spec_set_str):
    """Parses a comma-separated set of specifiers.

    Like `packaging.specifiers.SpecifierSet`, empty items are ignored, so
    `">=1.0,"`, `">=1.0,,<2"` and `" "` are accepted.

    Args:
        spec_set_str: The specifier set string to parse.

    Returns:
        A struct representing the parsed specifier set.
    """
    spec_strs = [strip_whitespace(s) for s in spec_set_str.split(",")]
    specs = [parse_specifier(s) for s in spec_strs if s]

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
    v = None
    for spec in spec_set.specs:
        if spec.operator != "===":
            v = try_parse_version(version_str)
            break

    for spec in spec_set.specs:
        if not _matches(spec, v, version_str):
            return False
    return True

specifiers = struct(
    parse = parse_specifier,
    contains = specifier_contains,
    parse_set = parse_specifier_set,
    set_contains = specifier_set_contains,
)
