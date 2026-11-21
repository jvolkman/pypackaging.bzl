"""PEP 508 Dependency Specification Parsing.

Derived from pypa/packaging: packaging/requirements.py and packaging/_parser.py
(Apache 2.0 / BSD).
Baseline: pypa/packaging 26.3
"""

load(
    "//pypackaging/private/markers:markers.bzl",
    "at_end",
    "is_word_char",
    "markers",
    "parse_marker_expression",
    "skip_ws",
    "syntax_error",
)
load("//pypackaging/private/specifiers:specifiers.bzl", "match_specifier_token", "try_parse_specifier")
load("//pypackaging/private/utils:utils.bzl", "utils")
load("//pypackaging/private/version:version.bzl", "strip_whitespace")

visibility(["//", "//pypackaging/..."])

_IDENTIFIER_START = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
_IDENTIFIER_CHARS = _IDENTIFIER_START + "._-"

# Upstream VERSION_LOCAL_LABEL_TRAIL is `\+[a-z0-9]+(?:[-_.][a-z0-9]+)*`
# (case-sensitive); it matches iff "+" is followed by one of these.
_LOCAL_LABEL_START = "abcdefghijklmnopqrstuvwxyz0123456789"

def _match_identifier(src, n, pos):
    """Matches upstream IDENTIFIER (`\\b[a-zA-Z0-9][a-zA-Z0-9._-]*\\b`).

    Returns:
        The end position of the match, or None.
    """
    if pos >= n or src[pos] not in _IDENTIFIER_START:
        return None
    if pos > 0 and is_word_char(src[pos - 1]):
        return None
    rest = src[pos:].lstrip(_IDENTIFIER_CHARS)
    end = n - len(rest)

    if is_word_char(src[end - 1]) and (end == n or not is_word_char(src[end])):
        return end

    # Backtrack until the match ends on a word boundary.
    end -= 1
    for _ in range(end - pos):
        if is_word_char(src[end - 1]) and (end == n or not is_word_char(src[end])):
            return end
        end -= 1
    return None

def _parse_requirement_marker(ctx, src, n, pos, span_start, expected):
    """requirement_marker = SEMICOLON marker WS?"""
    if pos >= n or src[pos] != ";":
        syntax_error(ctx, "Expected {} or end".format(expected), span_start, pos)
    pos += 1
    marker_start = pos
    marker, pos = parse_marker_expression(ctx, pos)
    pos = skip_ws(src, pos, n)
    return marker, src[marker_start:pos].strip(" \t"), pos

def _parse(req_str):
    """Parses a requirement string following upstream's grammar.

    Returns:
        A struct with the raw (unnormalized) parts.
    """
    ctx = struct(src = req_str, label = "Invalid requirement")
    src = req_str
    n = len(src)

    # requirement = WS? IDENTIFIER WS? extras WS? requirement_details END
    pos = skip_ws(src, 0, n)
    end = _match_identifier(src, n, pos)
    if end == None:
        syntax_error(ctx, "Expected package name at the start of dependency specifier", pos)
    name = src[pos:end]
    pos = skip_ws(src, end, n)

    # extras = (LEFT_BRACKET WS? extras_list? WS? RIGHT_BRACKET)?
    extras = []
    if pos < n and src[pos] == "[":
        open_pos = pos
        pos = skip_ws(src, pos + 1, n)

        # extras_list = IDENTIFIER (WS? COMMA WS? IDENTIFIER)*
        end = _match_identifier(src, n, pos)
        if end != None:
            extras.append(src[pos:end])
            pos = end
            for _ in range(n - pos):
                pos = skip_ws(src, pos, n)
                if _match_identifier(src, n, pos) != None:
                    syntax_error(ctx, "Expected comma between extra names", pos)
                if pos >= n or src[pos] != ",":
                    break
                pos = skip_ws(src, pos + 1, n)
                end = _match_identifier(src, n, pos)
                if end == None:
                    syntax_error(ctx, "Expected extra name after comma", pos)
                extras.append(src[pos:end])
                pos = end
        pos = skip_ws(src, pos, n)
        if pos >= n or src[pos] != "]":
            syntax_error(ctx, "Expected matching RIGHT_BRACKET for LEFT_BRACKET, after extras", open_pos, pos)
        pos += 1
    pos = skip_ws(src, pos, n)

    # requirement_details = AT URL (WS requirement_marker?)?
    #                     | specifier WS? (requirement_marker)?
    url = None
    specs = []
    marker = None
    marker_str = None
    if pos < n and src[pos] == "@":
        pos = skip_ws(src, pos + 1, n)
        url_start = pos
        sp = src.find(" ", pos)
        tb = src.find("\t", pos)
        if sp == -1:
            end = tb if tb != -1 else n
        elif tb == -1:
            end = sp
        else:
            end = sp if sp < tb else tb
        if end == pos:
            syntax_error(ctx, "Expected URL after @", pos)
        url = src[pos:end]
        pos = end
        if not at_end(src, pos, n):
            pos = skip_ws(src, pos, n)
            if not at_end(src, pos, n):
                marker, marker_str, pos = _parse_requirement_marker(
                    ctx,
                    src,
                    n,
                    pos,
                    url_start,
                    "semicolon (after URL and whitespace)",
                )
    else:
        # specifier = LEFT_PARENTHESIS WS? version_many WS? RIGHT_PARENTHESIS
        #           | WS? version_many WS?
        specifier_start = pos
        paren_pos = None
        if pos < n and src[pos] == "(":
            paren_pos = pos
            pos += 1
        pos = skip_ws(src, pos, n)

        # version_many = (SPECIFIER (WS? COMMA WS? SPECIFIER)*)?
        # (a trailing comma is accepted, like upstream)
        if pos < n and src[pos] in "=!<~>":
            for _ in range(n - pos):
                if pos >= n or src[pos] not in "=!<~>":
                    break
                token_len, spec = match_specifier_token(src[pos:])
                if not token_len:
                    break
                token_start = pos
                pos += token_len
                specs.append(spec)
                if src.startswith(".*", pos):
                    msg = (
                        ".* suffix cannot be used with pre-release, post-release, dev or local versions" if spec.operator in ("==", "!=") else ".* suffix can only be used with `==` or `!=` operators"
                    )
                    syntax_error(ctx, msg, token_start, pos + 1)
                if pos + 1 < n and src[pos] == "+" and src[pos + 1] in _LOCAL_LABEL_START:
                    syntax_error(ctx, "Local version label can only be used with `==` or `!=` operators", token_start, pos)
                pos = skip_ws(src, pos, n)
                if pos >= n or src[pos] != ",":
                    break
                pos = skip_ws(src, pos + 1, n)
        pos = skip_ws(src, pos, n)
        if paren_pos != None:
            if pos >= n or src[pos] != ")":
                syntax_error(
                    ctx,
                    "Expected matching RIGHT_PARENTHESIS for LEFT_PARENTHESIS, after version specifier",
                    paren_pos,
                    pos,
                )
            pos += 1
        pos = skip_ws(src, pos, n)
        if not at_end(src, pos, n):
            marker, marker_str, pos = _parse_requirement_marker(
                ctx,
                src,
                n,
                pos,
                specifier_start,
                "comma (within version specifier), semicolon (after version specifier)" if specs else "semicolon (after name with no version specifier)",
            )

    if not at_end(src, pos, n):
        syntax_error(ctx, "Expected end of dependency specifier", pos)

    return struct(
        name = name,
        extras = extras,
        specs = specs,
        url = url,
        marker = marker,
        marker_str = marker_str,
    )

def _parse_requirement(req_str):
    """Parses a PEP 508 requirement (dependency specifier) string.

    Accepts and rejects exactly what `packaging.requirements.Requirement`
    (packaging 26.3) does, failing with an upstream-style message that shows
    the input and a caret at the error position.

    Differences from upstream's `Requirement` object:

    - `name` is normalized (`utils.canonicalize_name`), and `extras` is a
      sorted, de-duplicated list of normalized extra names. The names as
      written are in `raw_name` and `raw_extras`.
    - `specifier` is the result of `specifiers.parse_set` for name-based
      requirements (with no specifiers it has an empty `specs` list), but
      `None` for URL requirements.
    - `marker` is the parsed marker tree (see `markers.parse`), or `None` when
      the requirement has no marker. `marker_str` is the marker text exactly as
      written (without surrounding whitespace), or `None`.

    Args:
        req_str: The requirement string to parse.

    Returns:
        A struct with fields:
          name: The normalized project name.
          raw_name: The project name as written.
          url: The URL for `name @ url` requirements, else None.
          extras: Sorted list of unique, normalized extras.
          raw_extras: Sorted list of unique extras as written.
          specifier: A specifier set struct, or None for URL requirements.
          marker: The parsed marker tree, or None.
          marker_str: The raw marker string, or None.
          req_str: The input string with surrounding whitespace stripped.
    """

    # Fast path for a bare project name such as "requests".
    if req_str and req_str[0] in _IDENTIFIER_START and req_str[-1] in _IDENTIFIER_START and not req_str.lstrip(_IDENTIFIER_CHARS):
        return struct(
            name = utils.canonicalize_name(req_str),
            raw_name = req_str,
            url = None,
            extras = [],
            raw_extras = [],
            specifier = struct(specs = []),
            marker = None,
            marker_str = None,
            req_str = req_str,
        )

    parsed = _parse(req_str)
    raw_extras = parsed.extras
    if not raw_extras:
        extras = []
        dedup_raw_extras = []
    elif len(raw_extras) == 1:
        extras = [utils.canonicalize_name(raw_extras[0])]
        dedup_raw_extras = raw_extras
    else:
        extras = sorted({utils.canonicalize_name(e): True for e in raw_extras})
        dedup_raw_extras = sorted({e: True for e in raw_extras})

    return struct(
        name = utils.canonicalize_name(parsed.name),
        raw_name = parsed.name,
        url = parsed.url,
        extras = extras,
        raw_extras = dedup_raw_extras,
        specifier = None if parsed.url != None else _specifier_set(parsed.specs),
        marker = parsed.marker,
        marker_str = parsed.marker_str,
        req_str = strip_whitespace(req_str),
    )

def _specifier_set(specs):
    """Builds a specifier set struct (see `specifiers.parse_set`).

    Args:
        specs: The specifier structs matched by the tokenizer.
    """
    for spec in specs:
        if spec.operator == "===" and "," in spec.version:
            # Only an `===` version can contain a comma. Upstream joins the
            # specifiers and splits the result on commas, wrapping invalid
            # specifier errors as InvalidRequirement (packaging 26.3).
            parsed = []
            for item in ",".join([s.operator + s.version for s in specs]).split(","):
                stripped = strip_whitespace(item)
                if stripped:
                    sp = try_parse_specifier(stripped)
                    if sp == None:
                        fail("Invalid requirement: Invalid specifier: {}".format(stripped))
                    parsed.append(sp)
            return struct(specs = parsed)
    return struct(specs = specs)

def _spec_str(spec):
    return spec.operator + spec.version

def _spec_key(spec):
    op = spec.operator
    if op == "===" or spec.version.endswith(".*"):
        return (op, spec.version)
    v = getattr(spec, "parsed_version", None)
    if v != None:
        if op == "~=":
            return (op, v.epoch, v.release, v.pre, v.post, v.dev, v.local)
        return (op, v.key)
    return (op, utils.canonicalize_version(spec.version, strip_trailing_zero = op != "~="))

def _requirement_to_string(req):
    """Serializes a parsed requirement like upstream `str(Requirement)`.

    The project name and extras are emitted as originally written (extras
    sorted and de-duplicated), specifiers are sorted and de-duplicated, and the
    marker is normalized with `markers.to_string`.

    Args:
        req: A requirement struct returned by `parse`.

    Returns:
        The normalized requirement string.
    """
    parts = [req.raw_name]
    if req.raw_extras:
        parts.append("[{}]".format(",".join(req.raw_extras)))

    if req.specifier != None and req.specifier.specs:
        specs = req.specifier.specs
        if len(specs) == 1:
            parts.append(specs[0].operator + specs[0].version)
        else:
            seen = {}
            spec_strs = []
            for spec in sorted(specs, key = _spec_str):
                key = _spec_key(spec)
                if key not in seen:
                    seen[key] = True
                    spec_strs.append(spec.operator + spec.version)
            parts.append(",".join(spec_strs))

    if req.url:
        parts.append(" @ " + req.url)
        if req.marker:
            parts.append(" ")

    if req.marker:
        parts.append("; " + markers.to_string(req.marker))

    return "".join(parts)

requirements = struct(
    parse = _parse_requirement,
    to_string = _requirement_to_string,
)
