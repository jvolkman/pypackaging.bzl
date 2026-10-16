"""PEP 440 Version handling.

Derived from pypa/packaging: packaging/version.py (Apache 2.0 / BSD).
Baseline: pypa/packaging 26.2
"""

def _fail_invalid_version(version):
    fail("Invalid version: {}".format(version))

# Versions are parsed by hand rather than with a regex: it is much faster in
# Starlark. The accepted grammar is packaging's VERSION_PATTERN, matched
# case-insensitively against the whole (stripped) string:
#
#   v?
#   (?:[0-9]+!)?                                       epoch
#   [0-9]+(?:\.[0-9]+)*                                release
#   (?:[._-]?(?:alpha|a|beta|b|preview|pre|c|rc)[._-]?[0-9]*)?          pre
#   (?:-[0-9]+|[._-]?(?:post|rev|r)[._-]?[0-9]*)?                       post
#   (?:[._-]?dev[._-]?[0-9]*)?                                          dev
#   (?:\+[a-z0-9]+(?:[._-][a-z0-9]+)*)?                                 local
#
# Taking every optional part greedily (and the longest label) gives the same
# result as the backtracking regex: no label is a prefix of a label that can
# follow it, and a separator consumed by one part is never required by the
# next one (a separator followed by digits is always taken as the number).

_DIGITS = "0123456789"
_LOCAL_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
_SEPARATORS = (".", "_", "-")

# Longest labels first.
_PRE_LABELS = ("alpha", "a", "beta", "b", "preview", "pre", "c", "rc")
_POST_LABELS = ("post", "rev", "r")
_DEV_LABELS = ("dev",)

# Sort ranks for pre-release: dev-only < a < b < rc < stable (no pre-release).
_PRE_RANK = {"a": 0, "b": 1, "rc": 2}
_PRE_RANK_DEV_ONLY = -1  # sorts before a(0)
_PRE_RANK_STABLE = 3  # sorts after rc(2)

# In local version segments, strings sort before ints per PEP 440.
_LOCAL_STR_RANK = -1  # sorts before all non-negative ints

# Pre-computed suffix for stable releases (no pre, post, or dev segments).
_STABLE_SUFFIX = (_PRE_RANK_STABLE, 0, 0, 0, 1, 0)

def _cmpkey(epoch, release, pre, post, dev, local):
    # Strip trailing zeros: 1.0.0 compares equal to 1.
    len_release = len(release)
    i = len_release
    for _ in range(len_release):
        if i and release[i - 1] == 0:
            i -= 1
        else:
            break
    trimmed = release if i == len_release else release[:i]

    # Fast path: stable release with no local segment.
    if pre == None and post == None and dev == None and local == None:
        return (epoch, trimmed, _STABLE_SUFFIX)

    if pre == None and post == None and dev != None:
        # dev-only (e.g. 1.0.dev1) sorts before all pre-releases.
        pre_rank, pre_n = _PRE_RANK_DEV_ONLY, 0
    elif pre == None:
        pre_rank, pre_n = _PRE_RANK_STABLE, 0
    else:
        pre_rank, pre_n = _PRE_RANK[pre[0]], pre[1]

    post_rank = 0 if post == None else 1
    post_n = 0 if post == None else post[1]

    dev_rank = 1 if dev == None else 0
    dev_n = 0 if dev == None else dev[1]

    suffix = (pre_rank, pre_n, post_rank, post_n, dev_rank, dev_n)

    if local == None:
        return (epoch, trimmed, suffix)

    cmp_local = []
    for seg in local:
        if type(seg) == type(0):
            cmp_local.append((seg, ""))
        else:
            cmp_local.append((_LOCAL_STR_RANK, seg))

    return (epoch, trimmed, suffix, tuple(cmp_local))

_PRE_NORMALIZATION = {
    "alpha": "a",
    "beta": "b",
    "c": "rc",
    "pre": "rc",
    "preview": "rc",
}

def get_public_key(v):
    """Returns the comparison key for the public version (without local segment)."""
    if v.local == None:
        return v.key
    return _cmpkey(v.epoch, v.release, v.pre, v.post, v.dev, None)

def version_key(epoch, release, pre, post, dev, local):
    """Returns the comparison key for a version built from the given parts."""
    return _cmpkey(epoch, release, pre, post, dev, local)

def make_version(epoch, release, pre, post, dev, local, version_str = ""):
    """Creates a Version struct and calculates its key."""
    key = _cmpkey(epoch, release, pre, post, dev, local)
    return struct(
        version_str = version_str,
        epoch = epoch,
        release = release,
        pre = pre,
        post = post,
        dev = dev,
        local = local,
        key = key,
        is_prerelease = (pre != None or dev != None),
        is_postrelease = (post != None),
        is_devrelease = (dev != None),
    )

_DIGITS_AND_DOT = ".0123456789"

# UTF-8 encodings of the non-ASCII code points for which Python's str.isspace()
# is true. Bazel strings are byte strings, so these show up as multi-character
# sequences. The built-in strip() already handles the ASCII ones
# (" \t\n\r\v\f" and \x1c-\x1f).
_UNICODE_WHITESPACE = (
    "\302\205",  # U+0085 NEXT LINE
    "\302\240",  # U+00A0 NO-BREAK SPACE
    "\341\232\200",  # U+1680 OGHAM SPACE MARK
    "\342\200\200",  # U+2000 EN QUAD
    "\342\200\201",  # U+2001 EM QUAD
    "\342\200\202",  # U+2002 EN SPACE
    "\342\200\203",  # U+2003 EM SPACE
    "\342\200\204",  # U+2004 THREE-PER-EM SPACE
    "\342\200\205",  # U+2005 FOUR-PER-EM SPACE
    "\342\200\206",  # U+2006 SIX-PER-EM SPACE
    "\342\200\207",  # U+2007 FIGURE SPACE
    "\342\200\210",  # U+2008 PUNCTUATION SPACE
    "\342\200\211",  # U+2009 THIN SPACE
    "\342\200\212",  # U+200A HAIR SPACE
    "\342\200\250",  # U+2028 LINE SEPARATOR
    "\342\200\251",  # U+2029 PARAGRAPH SEPARATOR
    "\342\200\257",  # U+202F NARROW NO-BREAK SPACE
    "\342\201\237",  # U+205F MEDIUM MATHEMATICAL SPACE
    "\343\200\200",  # U+3000 IDEOGRAPHIC SPACE
)

_ASCII_WHITESPACE = (" ", "\t", "\n", "\r", "\013", "\014", "\034", "\035", "\036", "\037")

def strip_whitespace(s):
    """Removes leading and trailing whitespace like Python's `str.strip()`.

    Unlike the built-in `strip()`, this also removes UTF-8 encoded Unicode
    whitespace such as U+00A0.

    Args:
        s: The string to strip.

    Returns:
        The stripped string.
    """
    s = s.strip()

    # Fast path: both ends are ASCII, so there is nothing more to strip.
    if not s or (s[0] < "\200" and s[-1] < "\200"):
        return s

    for _ in range(len(s)):
        if s.startswith(_UNICODE_WHITESPACE):
            for ws in _UNICODE_WHITESPACE:
                if s.startswith(ws):
                    s = s[len(ws):].strip()
                    break
        elif s.endswith(_UNICODE_WHITESPACE):
            for ws in _UNICODE_WHITESPACE:
                if s.endswith(ws):
                    s = s[:-len(ws)].strip()
                    break
        else:
            break
    return s

def contains_whitespace(s):
    """Returns True if `s` contains a character that Python's `\\s` matches.

    Args:
        s: The string to check.

    Returns:
        True if the string contains ASCII or UTF-8 encoded Unicode whitespace.
    """
    for ws in _ASCII_WHITESPACE:
        if ws in s:
            return True
    for ws in _UNICODE_WHITESPACE:
        if ws in s:
            return True
    return False

def parse_version(version_str):
    """Parses a version string into a struct.

    Leading and trailing whitespace is ignored, like `packaging.version.Version`.

    Args:
        version_str: The version string to parse. Fails if it isn't a valid
            PEP 440 version.

    Returns:
        A struct representing the parsed version, with these fields:

        * `version_str`: the input string without surrounding whitespace.
        * `epoch`: the epoch as an int.
        * `release`: the release segment as a tuple of ints.
        * `pre`: `("a" | "b" | "rc", int)` or None.
        * `post`: `("post", int)` or None.
        * `dev`: `("dev", int)` or None.
        * `local`: the local segment as a tuple of lowercase strings and ints,
          or None.
        * `key`: a sort key. Compare keys to compare versions.
        * `is_prerelease`, `is_postrelease`, `is_devrelease`: bools.
    """
    v = try_parse_version(version_str)
    if v == None:
        _fail_invalid_version(version_str)
    return v

def try_parse_version(version_str):
    """Like `parse_version`, but returns None instead of failing on invalid input.

    Args:
        version_str: The version string to parse.

    Returns:
        A struct representing the parsed version, or None if `version_str` is
        not a valid PEP 440 version.
    """
    return parse_stripped_version(strip_whitespace(version_str))

def parse_stripped_version(version_str):
    """Parses a version string that must not contain any whitespace.

    Args:
        version_str: The version string to parse.

    Returns:
        A struct representing the parsed version, or None if `version_str` is
        not a valid PEP 440 version.
    """
    if version_str and not version_str.lstrip(_DIGITS_AND_DOT):
        parts = version_str.split(".")
        if "" in parts:
            return None
        release = tuple([int(p) for p in parts])
        return make_version(0, release, None, None, None, None, version_str)

    return _parse_version_full(version_str)

def _split_digits(s):
    """Splits `s` into its leading ASCII digits and the rest."""
    rest = s.lstrip(_DIGITS)
    return s[:len(s) - len(rest)], rest

def _take_label(s, labels):
    """Matches `[._-]?label` at the start of `s`.

    Returns:
        (label, rest), or (None, s) if no label matches.
    """
    t = s[1:] if s.startswith(_SEPARATORS) else s
    for label in labels:
        if t.startswith(label):
            return label, t[len(label):]
    return None, s

def _take_number(s):
    """Matches `[._-]?[0-9]*` at the start of `s`.

    Returns:
        (number or None, rest).
    """
    t = s[1:] if s.startswith(_SEPARATORS) else s
    digits, rest = _split_digits(t)
    if digits:
        return int(digits), rest
    return None, t

def _parse_version_full(version_str):
    s = version_str.lower()
    if s.startswith("v"):
        s = s[1:]

    digits, s = _split_digits(s)
    if not digits:
        return None
    epoch = 0
    if s.startswith("!"):
        epoch = int(digits)
        digits, s = _split_digits(s[1:])
        if not digits:
            return None

    release = [int(digits)]
    for _ in range(len(s)):
        if not s.startswith(".") or not s[1:2] or s[1:2] not in _DIGITS:
            break
        digits, s = _split_digits(s[1:])
        release.append(int(digits))

    pre = None
    label, s = _take_label(s, _PRE_LABELS)
    if label != None:
        number, s = _take_number(s)
        pre = (_PRE_NORMALIZATION.get(label, label), number or 0)

    post = None
    if s.startswith("-") and s[1:2] and s[1:2] in _DIGITS:
        digits, s = _split_digits(s[1:])
        post = ("post", int(digits))
    else:
        label, s = _take_label(s, _POST_LABELS)
        if label != None:
            number, s = _take_number(s)
            post = ("post", number or 0)

    dev = None
    label, s = _take_label(s, _DEV_LABELS)
    if label != None:
        number, s = _take_number(s)
        dev = ("dev", number or 0)

    local = None
    if s.startswith("+"):
        parts = s[1:].replace("_", ".").replace("-", ".").split(".")
        local = []
        for part in parts:
            if not part or part.lstrip(_LOCAL_CHARS):
                return None
            local.append(int(part) if not part.lstrip(_DIGITS) else part)
        local = tuple(local)
        s = ""

    if s:
        return None

    return make_version(epoch, tuple(release), pre, post, dev, local, version_str)

def version_to_string(v):
    """Returns the normalized string form of a parsed version.

    This is upstream's `str(Version)`, e.g. `1.0.0-RC1` becomes `1.0.0rc1` and
    `v1!2.0-post3` becomes `1!2.0.post3`. Trailing zeros are kept.

    Args:
        v: A version struct returned by `parse`.

    Returns:
        The normalized version string.
    """
    s = ".".join([str(x) for x in v.release])
    if v.epoch != 0:
        s = "{}!{}".format(v.epoch, s)
    if v.pre != None:
        s += "{}{}".format(v.pre[0], v.pre[1])
    if v.post != None:
        s += ".post{}".format(v.post[1])
    if v.dev != None:
        s += ".dev{}".format(v.dev[1])
    if v.local != None:
        s += "+" + ".".join([str(x) for x in v.local])
    return s

version = struct(
    parse = parse_version,
    try_parse = try_parse_version,
    to_string = version_to_string,
    get_public_key = get_public_key,
)
