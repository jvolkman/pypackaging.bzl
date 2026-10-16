"""PEP 440 Version Specifiers.

Derived from pypa/packaging: packaging/specifiers.py (Apache 2.0 / BSD).
Baseline: pypa/packaging 26.2

Differences from `packaging.specifiers`:

* `~=` derives its prefix from the normalized specifier version, as PEP 440
  says: `~=1.0c1` is `>=1.0c1, ==1.*` and `~=v1.0` is `>=1.0, ==1.*`.
  packaging 26.2 derives it from the raw string, so it treats unusual
  spellings such as `~=1.0c1`, `~=1.0.r1` or `~=1.0.RC1` as `==1.0.*`, and
  `~=v1.0` matches nothing.
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
    "match_version_prefix",
    "parse_stripped_version",
    "strip_whitespace",
    "try_parse_version",
    "version_key",
    "version_to_string",
    "whitespace_len_at",
)

visibility(["//", "//pypackaging/..."])

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
    spec = try_parse_specifier(spec_str)
    if spec == None:
        _fail_invalid_specifier(spec_str)
    return spec

# Operators in the order of the alternatives in packaging's specifier regex.
_TOKEN_OPERATORS = ("==", "!=", "~=", "<=", ">=", "<", ">")

def match_specifier_token(s):
    """Matches packaging's SPECIFIER token at the start of `s`.

    Internal helper for the requirement tokenizer; not part of the public API.
    This is an unanchored match of `Specifier._specifier_regex_str` (without
    surrounding whitespace), so it never looks past the end of the token.

    Args:
        s: The string to match.

    Returns:
        The length of the token, or 0 if `s` doesn't start with a specifier.
    """
    if s.startswith("==="):
        # ===\s*[^\s;)]*
        rest = lstrip_whitespace(s[3:])
        end = 0
        for _ in range(len(rest)):
            if rest[end] in ";)" or whitespace_len_at(rest, end):
                break
            end += 1
        return len(s) - len(rest) + end

    for op in _TOKEN_OPERATORS:
        if s.startswith(op):
            rest = lstrip_whitespace(s[len(op):])
            if op == "==" or op == "!=":
                n = match_version_prefix(rest, allow_local = True, allow_wildcard = True)
            elif op == "~=":
                n = match_version_prefix(rest, allow_local = False, min_release_len = 2)
            else:
                n = match_version_prefix(rest, allow_local = False)
            if not n:
                return 0
            return len(s) - len(rest) + n
    return 0

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
    include_prereleases = prereleases if prereleases != None else specifier_prereleases(spec)
    result = []
    held_prereleases = []
    found_final = False
    for item in versions:
        v, version_str = _coerce(item)
        if not _matches(spec, v, version_str):
            continue
        if v == None:
            # Only === can match a string that isn't a valid version.
            result.append(item)
        elif not v.is_prerelease or include_prereleases:
            found_final = True
            result.append(item)
        elif prereleases == None:
            held_prereleases.append(item)

    if not found_final and prereleases == None:
        result.extend(held_prereleases)
    return result

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
    spec_strs = [strip_whitespace(s) for s in spec_set_str.split(",")]
    specs = [parse_specifier(s) for s in spec_strs if s]

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

def _set_matches(spec_set, v, version_str):
    for spec in spec_set.specs:
        if not _matches(spec, v, version_str):
            return False
    return True

def _needs_parse(spec_set):
    for spec in spec_set.specs:
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
    if type(version) == "string" and prereleases != False and not installed and not _needs_parse(spec_set):
        # Only === specifiers (or none at all): no need to parse.
        return _set_matches(spec_set, None, version)

    v, version_str = _coerce(version)
    if v != None and v.is_prerelease:
        if installed:
            prereleases = True
        if prereleases == False:
            return False
    return _set_matches(spec_set, v, version_str)

def _pep440_filter_prereleases(items, parsed):
    """Drops pre-releases if there is at least one final release."""
    for v in parsed:
        if v != None and not v.is_prerelease:
            return [item for item, v in zip(items, parsed) if v == None or not v.is_prerelease]
    return items

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
    if prereleases == None:
        prereleases = specifier_set_prereleases(spec_set)

    items = []
    parsed = []
    for item in versions:
        v, version_str = _coerce(item)
        if prereleases == False and v != None and v.is_prerelease:
            continue
        if _set_matches(spec_set, v, version_str):
            items.append(item)
            parsed.append(v)

    if prereleases != None:
        return items
    return _pep440_filter_prereleases(items, parsed)

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
