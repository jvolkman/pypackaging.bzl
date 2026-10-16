"""PEP 508 Dependency Specification Parsing.

Derived from pypa/packaging: packaging/requirements.py and packaging/_parser.py
(Apache 2.0 / BSD).
Baseline: pypa/packaging 26.2
"""

load(
    "//pypackaging/private/markers:markers.bzl",
    "at_end",
    "markers",
    "parse_marker_expression",
    "skip_ws",
    "syntax_error",
)
load("//pypackaging/private/specifiers:specifiers.bzl", "match_specifier_token", "specifiers")
load("//pypackaging/private/utils:utils.bzl", "utils")

_IDENTIFIER_START = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
_IDENTIFIER_CHARS = _IDENTIFIER_START + "._-"
_ASCII_WORD_CHARS = _IDENTIFIER_START + "_"

# Upstream VERSION_LOCAL_LABEL_TRAIL is `\+[a-z0-9]+(?:[-_.][a-z0-9]+)*`
# (case-sensitive); it matches iff "+" is followed by one of these.
_LOCAL_LABEL_START = "abcdefghijklmnopqrstuvwxyz0123456789"

def _is_word_char(c):
    return c in _ASCII_WORD_CHARS or c >= "\200"

def _match_identifier(src, pos):
    """Matches upstream IDENTIFIER (`\\b[a-zA-Z0-9][a-zA-Z0-9._-]*\\b`).

    Returns:
        The end position of the match, or None.
    """
    n = len(src)
    if pos >= n or src[pos] not in _IDENTIFIER_START:
        return None
    if pos > 0 and _is_word_char(src[pos - 1]):
        return None
    end = pos + 1
    for _ in range(n - end):
        if src[end] in _IDENTIFIER_CHARS:
            end += 1
        else:
            break

    # Backtrack until the match ends on a word boundary.
    for _ in range(end - pos):
        if _is_word_char(src[end - 1]) and (end == n or not _is_word_char(src[end])):
            return end
        end -= 1
    return None

def _parse_requirement_marker(ctx, pos, span_start, expected):
    """requirement_marker = SEMICOLON marker WS?"""
    src = ctx.src
    if pos >= len(src) or src[pos] != ";":
        syntax_error(ctx, "Expected {} or end".format(expected), span_start, pos)
    pos += 1
    marker_start = pos
    marker, pos = parse_marker_expression(ctx, pos)
    pos = skip_ws(src, pos)
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
    pos = skip_ws(src, 0)
    end = _match_identifier(src, pos)
    if end == None:
        syntax_error(ctx, "Expected package name at the start of dependency specifier", pos)
    name = src[pos:end]
    pos = skip_ws(src, end)

    # extras = (LEFT_BRACKET WS? extras_list? WS? RIGHT_BRACKET)?
    extras = []
    if pos < n and src[pos] == "[":
        open_pos = pos
        pos = skip_ws(src, pos + 1)

        # extras_list = IDENTIFIER (WS? COMMA WS? IDENTIFIER)*
        end = _match_identifier(src, pos)
        if end != None:
            extras.append(src[pos:end])
            pos = end
            for _ in range(n):
                pos = skip_ws(src, pos)
                if _match_identifier(src, pos) != None:
                    syntax_error(ctx, "Expected comma between extra names", pos)
                if pos >= n or src[pos] != ",":
                    break
                pos = skip_ws(src, pos + 1)
                end = _match_identifier(src, pos)
                if end == None:
                    syntax_error(ctx, "Expected extra name after comma", pos)
                extras.append(src[pos:end])
                pos = end
        pos = skip_ws(src, pos)
        if pos >= n or src[pos] != "]":
            syntax_error(ctx, "Expected matching RIGHT_BRACKET for LEFT_BRACKET, after extras", open_pos, pos)
        pos += 1
    pos = skip_ws(src, pos)

    # requirement_details = AT URL (WS requirement_marker?)?
    #                     | specifier WS? (requirement_marker)?
    url = None
    specs = []
    marker = None
    marker_str = None
    if pos < n and src[pos] == "@":
        pos = skip_ws(src, pos + 1)
        url_start = pos
        end = pos
        for _ in range(n - pos):
            if src[end] not in " \t":
                end += 1
            else:
                break
        if end == pos:
            syntax_error(ctx, "Expected URL after @", pos)
        url = src[pos:end]
        pos = end
        if not at_end(src, pos):
            if src[pos] not in " \t":
                syntax_error(ctx, "Expected whitespace after URL", pos)
            pos = skip_ws(src, pos)
            if not at_end(src, pos):
                marker, marker_str, pos = _parse_requirement_marker(
                    ctx,
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
        pos = skip_ws(src, pos)

        # version_many = (SPECIFIER (WS? COMMA WS? SPECIFIER)*)?
        # (a trailing comma is accepted, like upstream)
        for _ in range(n):
            token_len = match_specifier_token(src[pos:])
            if not token_len:
                break
            token_start = pos
            pos += token_len
            specs.append(src[token_start:pos])
            if src.startswith(".*", pos):
                syntax_error(ctx, ".* suffix can only be used with `==` or `!=` operators", token_start, pos + 1)
            if src.startswith("+", pos) and src[pos + 1:pos + 2] and src[pos + 1] in _LOCAL_LABEL_START:
                syntax_error(ctx, "Local version label can only be used with `==` or `!=` operators", token_start, pos)
            pos = skip_ws(src, pos)
            if pos >= n or src[pos] != ",":
                break
            pos = skip_ws(src, pos + 1)
        pos = skip_ws(src, pos)
        if paren_pos != None:
            if pos >= n or src[pos] != ")":
                syntax_error(
                    ctx,
                    "Expected matching RIGHT_PARENTHESIS for LEFT_PARENTHESIS, after version specifier",
                    paren_pos,
                    pos,
                )
            pos += 1
        pos = skip_ws(src, pos)
        if not at_end(src, pos):
            marker, marker_str, pos = _parse_requirement_marker(
                ctx,
                pos,
                specifier_start,
                "comma (within version specifier), semicolon (after version specifier)" if specs else "semicolon (after name with no version specifier)",
            )

    if not at_end(src, pos):
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
    (packaging 26.2) does, failing with an upstream-style message that shows
    the input and a caret at the error position.

    Differences from upstream's `Requirement` object:

    - `name` is normalized (`utils.canonicalize_name`), and `extras` is a
      sorted, de-duplicated list of normalized extra names.
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
          url: The URL for `name @ url` requirements, else None.
          extras: Sorted list of unique, normalized extras.
          specifier: A specifier set struct, or None for URL requirements.
          marker: The parsed marker tree, or None.
          marker_str: The raw marker string, or None.
          req_str: The input string with surrounding whitespace stripped.
    """
    parsed = _parse(req_str)
    return struct(
        name = utils.canonicalize_name(parsed.name),
        url = parsed.url,
        extras = sorted({utils.canonicalize_name(e): True for e in parsed.extras}.keys()),
        specifier = None if parsed.url != None else specifiers.parse_set(",".join(parsed.specs)),
        marker = parsed.marker,
        marker_str = parsed.marker_str,
        req_str = req_str.strip(" \t\n\r\013\014"),
    )

def _spec_str(spec):
    return spec.operator + spec.version

def _spec_key(spec):
    if spec.operator == "===" or spec.version.endswith(".*"):
        return (spec.operator, spec.version)
    return (spec.operator, utils.canonicalize_version(spec.version, strip_trailing_zero = spec.operator != "~="))

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
    parsed = _parse(req.req_str)
    parts = [parsed.name]

    extras = sorted({e: True for e in parsed.extras}.keys())
    if extras:
        parts.append("[{}]".format(",".join(extras)))

    if req.specifier != None and req.specifier.specs:
        seen = {}
        spec_strs = []
        for spec in sorted(req.specifier.specs, key = _spec_str):
            key = _spec_key(spec)
            if key not in seen:
                seen[key] = True
                spec_strs.append(_spec_str(spec))
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
