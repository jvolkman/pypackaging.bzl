"""PEP 440 Version Specifiers.

Derived from pypa/packaging: packaging/specifiers.py (Apache 2.0 / BSD).
Baseline: pypa/packaging 26.2

Differences from `packaging.specifiers`:

* `~=` derives its prefix from the normalized specifier version per PEP 440
  (e.g. `~=1.0c1` -> `>=1.0c1, ==1.*` and `~=v1.0` -> `>=1.0, ==1.*`), rather
  than splitting the raw version string.
* Specifiers and sets are immutable structs, so there is no constructor-level
  `prereleases` argument; pass `prereleases` to `contains`, `set_contains`,
  `filter` or `set_filter` instead, which gives the same results.
* `filter` and `set_filter` take no `key` argument. Set operations (`&`),
  `is_unsatisfiable` and string normalization (`str()`) are not provided, and
  struct equality compares specifiers as written (upstream considers `==1.0`
  and `==1` equal).
* `===` compares case-insensitively using ASCII case folding only.
* `parse` and `parse_set` fail on invalid input, since Starlark has no
  exceptions.
"""

load(
    "//pypackaging/private/version:version.bzl",
    "contains_whitespace",
    "get_public_key",
    "lstrip_whitespace",
    "parse_stripped_version",
    "scan_version_prefix",
    "strip_whitespace",
    "try_parse_version",
    "version_to_string",
    "whitespace_len_at",
)

visibility(["//", "//pypackaging/..."])

_TWO_CHAR_OPS = {"==": True, "!=": True, "~=": True, "<=": True, ">=": True}
_OP_FIRST_CHARS = "=!<~>"

def _fail_invalid_specifier(spec):
    fail("Invalid specifier: {}".format(spec))

def try_parse_specifier(spec_str):
    """Parses a specifier, returning None if it is invalid.

    Internal helper (e.g. for markers.bzl); not part of the public API.

    The version is parsed once here and validated structurally: the specifier
    grammar is the PEP 440 version grammar, minus local versions for ordered
    comparisons and ~=, plus a trailing `.*` on a bare release for == and !=,
    and with at least two release segments for ~=.

    Args:
        spec_str: The specifier string to parse.

    Returns:
        A specifier struct (see `parse_specifier`), or None.
    """
    return _try_parse_stripped_specifier(strip_whitespace(spec_str))

def _try_parse_stripped_specifier(stripped):
    """Like `try_parse_specifier`, for a string without surrounding whitespace."""
    if not stripped or stripped[0] not in _OP_FIRST_CHARS:
        return None
    if stripped[:3] == "===":
        version = lstrip_whitespace(stripped[3:])
        if ";" in version or ")" in version or contains_whitespace(version):
            return None
        return struct(operator = "===", version = version, parsed_version = None)

    op2 = stripped[:2]
    if op2 in _TWO_CHAR_OPS:
        operator, version = op2, lstrip_whitespace(stripped[2:])
    elif stripped[0] == "<" or stripped[0] == ">":
        operator, version = stripped[0], lstrip_whitespace(stripped[1:])
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
    spec = try_parse_specifier(spec_str)
    if spec == None:
        _fail_invalid_specifier(spec_str)
    return spec

def match_specifier_token(s):
    """Matches packaging's SPECIFIER token at the start of `s`.

    Internal helper for the requirement tokenizer; not part of the public API.
    This is an unanchored match of `Specifier._specifier_regex_str` (without
    surrounding whitespace), so it never looks past the end of the token.

    The token grammar is the specifier grammar, so the parsed specifier is
    returned along with the token's length.

    Args:
        s: The string to match.

    Returns:
        `(length, spec)`: the length of the token and the specifier struct
        (see `parse_specifier`), or `(0, None)` if `s` doesn't start with a
        specifier.
    """
    if not s or s[0] not in _OP_FIRST_CHARS:
        return 0, None

    if s[:3] == "===":
        # ===\s*[^\s;)]*
        rest = lstrip_whitespace(s[3:])
        end = 0
        for _ in range(len(rest)):
            if rest[end] in ";)" or whitespace_len_at(rest, end):
                break
            end += 1
        spec = struct(operator = "===", version = rest[:end], parsed_version = None)
        return len(s) - len(rest) + end, spec

    op2 = s[:2]
    if op2 in _TWO_CHAR_OPS:
        op = op2
        rest = lstrip_whitespace(s[2:])
    elif s[0] == "<" or s[0] == ">":
        op = s[0]
        rest = lstrip_whitespace(s[1:])
    else:
        return 0, None

    if op == "==" or op == "!=":
        n, v = scan_version_prefix(rest, allow_local = True, allow_wildcard = True)
    elif op == "~=":
        n, v = scan_version_prefix(rest, allow_local = False, min_release_len = 2)
    else:
        n, v = scan_version_prefix(rest, allow_local = False)
    if not n:
        return 0, None
    return len(s) - len(rest) + n, struct(operator = op, version = rest[:n], parsed_version = v)

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
        if (
            not sv.is_postrelease and
            v.is_postrelease and
            sv.dev == None and
            v.pre == sv.pre and
            v.key[0] == sv.key[0] and
            v.key[1] == sv.key[1]
        ):
            return False

        # >V must not match a local version of V.
        if v.local != None and get_public_key(v) == sv.key:
            return False

        return True

    if operator == "<":
        if not v.key < sv.key:
            return False

        # <V must not match a pre-release of V unless V is itself a pre-release.
        if (
            not sv.is_prerelease and
            v.is_prerelease and
            v.key[0] == sv.key[0] and
            v.key[1] == sv.key[1] and
            (sv.post == None or (v.pre == None and v.post == sv.post))
        ):
            return False

        return True

    if operator == "~=":
        # ~=X.Y.Z is >=X.Y.Z, ==X.Y.*. The prefix comes from the normalized
        # release, as PEP 440 says. Parsing guarantees at least two release
        # segments.
        return get_public_key(v) >= sv.key and _prefix_match(v, sv.epoch, sv.release[:-1])

    fail("Invalid specifier: unknown operator {}".format(operator))

def _matches(spec, v, version_str):
    """Checks a candidate against a specifier.

    Args:
        spec: The specifier struct.
        v: The parsed candidate version, or None if it isn't a valid version.
        version_str: The candidate as a string, or None if the candidate was
            given as a parsed version. === compares this string.
    """
    if spec.operator == "===":
        if version_str == None:
            version_str = version_to_string(v)
        return version_str.lower() == spec.version.lower()
    if v == None:
        return False
    return _matches_parsed(spec, v)

def _coerce(candidate):
    """Returns (parsed version or None, candidate string or None)."""
    if type(candidate) == "string":
        return try_parse_version(candidate), candidate
    if type(candidate) != "struct":
        fail("version must be a string or a struct returned by version.parse, got {}: {}".format(type(candidate), repr(candidate)))
    return candidate, None

def specifier_prereleases(spec):
    """Returns whether a specifier implies that pre-releases are allowed.

    This is upstream's `Specifier.prereleases` for a specifier constructed
    without an explicit `prereleases` argument: False for `!=` and for `==`
    with a wildcard, None for `===` with a version that isn't valid PEP 440,
    and otherwise whether the specifier's version is a pre-release.

    Args:
        spec: The specifier struct.

    Returns:
        True, False, or None.
    """
    operator = spec.operator
    if operator == "!=":
        return False
    if operator == "==" and spec.version.endswith(".*"):
        return False
    if operator == "===":
        v = try_parse_version(spec.version)
        if v == None:
            return None
        return v.is_prerelease
    return _spec_version(spec).is_prerelease

def specifier_contains(spec, version, prereleases = None):
    """Checks if a version satisfies a specifier.

    This is upstream's `Specifier.contains`. Pre-releases are accepted unless
    `prereleases` is False: there are no other candidates to prefer, so the
    PEP 440 rule to exclude them doesn't apply. A `version` that is not a valid
    PEP 440 version never matches, except that `===` compares it as a string.

    Args:
        spec: The specifier struct.
        version: The version to check: a string or a struct returned by
            `version.parse`.
        prereleases: If False, pre-release versions never match. None (the
            default) and True accept them.

    Returns:
        True if the version satisfies the specifier, False otherwise.
    """
    if spec.operator == "===" and type(version) == "string":
        v, version_str = None, version
        if prereleases == False:
            v = try_parse_version(version)
    else:
        v, version_str = _coerce(version)
    if not _matches(spec, v, version_str):
        return False
    return not (prereleases == False and v != None and v.is_prerelease)

def _all_match(specs, v, version_str):
    for spec in specs:
        if not _matches(spec, v, version_str):
            return False
    return True

def _filter_versions(specs, versions, prereleases, default_prereleases):
    include_prereleases = prereleases if prereleases != None else default_prereleases
    if prereleases == False:
        out = []
        for item in versions:
            v, version_str = _coerce(item)
            if (v == None or not v.is_prerelease) and _all_match(specs, v, version_str):
                out.append(item)
        return out
    if include_prereleases:
        out = []
        for item in versions:
            v, version_str = _coerce(item)
            if _all_match(specs, v, version_str):
                out.append(item)
        return out

    # prereleases is None and specs do not imply prereleases: keep matching
    # prereleases only if no matching final release is found.
    out = []
    finals = []
    has_final = False
    for item in versions:
        v, version_str = _coerce(item)
        if not _all_match(specs, v, version_str):
            continue
        out.append(item)
        if v == None or not v.is_prerelease:
            finals.append(item)
            if v != None:
                has_final = True
    return finals if has_final else out

def specifier_filter(spec, versions, prereleases = None):
    """Filters versions that satisfy a specifier.

    This is upstream's `Specifier.filter`. With `prereleases = None`, whether
    pre-releases are included comes from `prereleases(spec)`; if that is not
    True, matching pre-releases are only returned when no matching final
    release (or post-release) was found.

    Args:
        spec: The specifier struct.
        versions: A list of versions: strings or structs returned by
            `version.parse`. Strings that are not valid PEP 440 versions only
            match `===`.
        prereleases: True to include pre-releases, False to exclude them, or
            None for the default behavior described above.

    Returns:
        The matching items of `versions`, in order.
    """
    default_pre = specifier_prereleases(spec) if prereleases == None else None
    return _filter_versions([spec], versions, prereleases, default_pre)

def parse_specifier_set(spec_set_str):
    """Parses a comma-separated set of specifiers.

    Like `packaging.specifiers.SpecifierSet`, empty items are ignored, so
    `">=1.0,"`, `">=1.0,,<2"` and `" "` are accepted.

    Args:
        spec_set_str: The specifier set string to parse.

    Returns:
        A struct with a `specs` field: the list of parsed specifiers (see
        `parse`), in order.
    """
    specs = []
    for item in spec_set_str.split(","):
        item = strip_whitespace(item)
        if item:
            spec = _try_parse_stripped_specifier(item)
            if spec == None:
                _fail_invalid_specifier(item)
            specs.append(spec)

    return struct(
        specs = specs,
    )

def specifier_set_prereleases(spec_set):
    """Returns whether a specifier set implies that pre-releases are allowed.

    This is upstream's `SpecifierSet.prereleases` for a set constructed without
    an explicit `prereleases` argument: True if any specifier implies
    pre-releases (see `prereleases`), otherwise None.

    Args:
        spec_set: The specifier set struct.

    Returns:
        True or None.
    """
    for spec in spec_set.specs:
        if specifier_prereleases(spec):
            return True
    return None

def _needs_parse(specs):
    for spec in specs:
        if spec.operator != "===":
            return True
    return False

def specifier_set_contains(spec_set, version, prereleases = None, installed = None):
    """Checks if a version satisfies all specifiers in the set.

    This is upstream's `SpecifierSet.contains`. Pre-releases are accepted unless
    `prereleases` is False. A `version` that is not a valid PEP 440 version
    only matches if every specifier in the set is `===` and matches it as a
    string. An empty set matches everything.

    Args:
        spec_set: The specifier set struct.
        version: The version to check: a string or a struct returned by
            `version.parse`.
        prereleases: If False, pre-release versions never match. None (the
            default) and True accept them.
        installed: If True, a pre-release version is accepted even if
            `prereleases` is False.

    Returns:
        True if the version satisfies all specifiers, False otherwise.
    """
    specs = spec_set.specs
    if not specs and (prereleases != False or installed):
        return True
    if type(version) == "string" and prereleases != False and not installed and (not specs or (specs[0].operator == "===" and not _needs_parse(specs))):
        # Only === specifiers (or none at all): no need to parse.
        return _all_match(specs, None, version)

    v, version_str = _coerce(version)
    if v != None and v.is_prerelease:
        if installed:
            prereleases = True
        if prereleases == False:
            return False
    return _all_match(specs, v, version_str)

def specifier_set_filter(spec_set, versions, prereleases = None):
    """Filters versions that satisfy all specifiers in the set.

    This is upstream's `SpecifierSet.filter`. With `prereleases = None`,
    pre-releases are included if `set_prereleases(spec_set)` is True;
    otherwise matching pre-releases are only returned when no matching final
    release (or post-release) was found, as PEP 440 recommends.

    Args:
        spec_set: The specifier set struct.
        versions: A list of versions: strings or structs returned by
            `version.parse`. Strings that are not valid PEP 440 versions only
            match if every specifier is `===` (or the set is empty), and are
            never treated as pre-releases.
        prereleases: True to include pre-releases, False to exclude them, or
            None for the default behavior described above.

    Returns:
        The matching items of `versions`, in order.
    """
    default_pre = specifier_set_prereleases(spec_set) if prereleases == None else None
    return _filter_versions(spec_set.specs, versions, prereleases, default_pre)

specifiers = struct(
    parse = parse_specifier,
    contains = specifier_contains,
    filter = specifier_filter,
    prereleases = specifier_prereleases,
    parse_set = parse_specifier_set,
    set_contains = specifier_set_contains,
    set_filter = specifier_set_filter,
    set_prereleases = specifier_set_prereleases,
)
