"""PEP 508 Marker parsing and evaluation.

Derived from pypa/packaging: packaging/markers.py, packaging/_parser.py and
packaging/_tokenizer.py (Apache 2.0 / BSD).
Baseline: pypa/packaging 26.2
"""

load("@re.bzl", "re")
load("//pypackaging/private/specifiers:specifiers.bzl", "parse_specifier", "specifier_contains")
load("//pypackaging/private/utils:utils.bzl", "utils")

# ---------------------------------------------------------------------------
# Tokenizer primitives (shared with requirements.bzl)
# ---------------------------------------------------------------------------

_WS = " \t"

# Characters matched by Python's `\w` in the ASCII range. Any non-ASCII
# character is treated as a word character, which approximates `\w` for the
# letters and digits that can legitimately appear next to a token.
_ASCII_WORD_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

# Upstream VARIABLE token, longest first so that a prefix never shadows a
# longer name.
_VARIABLES = (
    "platform.python_implementation",
    "platform_python_implementation",
    "implementation_version",
    "python_implementation",
    "python_full_version",
    "implementation_name",
    "dependency_groups",
    "platform_release",
    "platform.machine",
    "platform.version",
    "platform_machine",
    "platform_version",
    "platform_system",
    "python_version",
    "sys.platform",
    "sys_platform",
    "os.name",
    "os_name",
    "extras",
    "extra",
)

# Longest first.
_OPS = ("===", "==", "~=", "!=", "<=", ">=", "<", ">")

def _is_word_char(c):
    return c in _ASCII_WORD_CHARS or c >= "\200"

def _is_boundary(src, pos):
    """Returns True if `pos` is a regex `\\b` word boundary in `src`."""
    before = pos > 0 and _is_word_char(src[pos - 1])
    after = pos < len(src) and _is_word_char(src[pos])
    return before != after

def _match_word(src, pos, word):
    """Matches `\\bword\\b` at `pos`."""
    return (
        src.startswith(word, pos) and
        _is_boundary(src, pos) and
        _is_boundary(src, pos + len(word))
    )

def skip_ws(src, pos):
    """Returns the position after any spaces or tabs starting at `pos`.

    Internal helper shared with requirements.bzl; not part of the public API.

    Args:
        src: The source string.
        pos: The start position.

    Returns:
        The position of the first non-whitespace character at or after `pos`.
    """
    for _ in range(len(src) - pos):
        if src[pos] in _WS:
            pos += 1
        else:
            break
    return pos

def at_end(src, pos):
    """Returns True if the upstream END token (regex `$`) matches at `pos`.

    Like Python's `$` without MULTILINE, this matches at the end of the string
    and also just before a single trailing newline.

    Internal helper shared with requirements.bzl; not part of the public API.

    Args:
        src: The source string.
        pos: The position to check.

    Returns:
        True if at the end of the input.
    """
    n = len(src)
    return pos == n or (pos == n - 1 and src[pos] == "\n")

def syntax_error(ctx, message, span_start, span_end = None):
    """Fails with an upstream-style `ParserSyntaxError` message.

    Internal helper shared with requirements.bzl; not part of the public API.

    Args:
        ctx: A struct with `src` (the full source text) and `label` (the
            error prefix, e.g. "Invalid marker").
        message: The error message.
        span_start: Start of the highlighted span.
        span_end: End of the highlighted span (the caret position); defaults
            to `span_start`.
    """
    if span_end == None:
        span_end = span_start
    caret = " " * span_start + "~" * (span_end - span_start) + "^"
    fail("{}: {}\n    {}\n    {}".format(ctx.label, message, ctx.src, caret))

# ---------------------------------------------------------------------------
# Python string literal decoding (upstream uses `ast.literal_eval`)
# ---------------------------------------------------------------------------

# One single-character string per byte value, used to build UTF-8 output.
_BYTES = (
    "\000\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037" +
    "\040\041\042\043\044\045\046\047\050\051\052\053\054\055\056\057\060\061\062\063\064\065\066\067\070\071\072\073\074\075\076\077" +
    "\100\101\102\103\104\105\106\107\110\111\112\113\114\115\116\117\120\121\122\123\124\125\126\127\130\131\132\133\134\135\136\137" +
    "\140\141\142\143\144\145\146\147\150\151\152\153\154\155\156\157\160\161\162\163\164\165\166\167\170\171\172\173\174\175\176\177" +
    "\200\201\202\203\204\205\206\207\210\211\212\213\214\215\216\217\220\221\222\223\224\225\226\227\230\231\232\233\234\235\236\237" +
    "\240\241\242\243\244\245\246\247\250\251\252\253\254\255\256\257\260\261\262\263\264\265\266\267\270\271\272\273\274\275\276\277" +
    "\300\301\302\303\304\305\306\307\310\311\312\313\314\315\316\317\320\321\322\323\324\325\326\327\330\331\332\333\334\335\336\337" +
    "\340\341\342\343\344\345\346\347\350\351\352\353\354\355\356\357\360\361\362\363\364\365\366\367\370\371\372\373\374\375\376\377"
)

_SIMPLE_ESCAPES = {
    "\n": "",
    "\"": "\"",
    "'": "'",
    "\\": "\\",
    "a": "\007",
    "b": "\010",
    "f": "\014",
    "n": "\n",
    "r": "\r",
    "t": "\t",
    "v": "\013",
}

_OCT_DIGITS = "01234567"
_HEX_DIGITS = "0123456789abcdefABCDEF"
_HEX_ESCAPE_LEN = {"U": 8, "u": 4, "x": 2}

def _utf8(cp):
    if cp < 0x80:
        return _BYTES[cp]
    if cp < 0x800:
        return _BYTES[0xC0 | (cp >> 6)] + _BYTES[0x80 | (cp & 0x3F)]
    if cp < 0x10000:
        return (
            _BYTES[0xE0 | (cp >> 12)] +
            _BYTES[0x80 | ((cp >> 6) & 0x3F)] +
            _BYTES[0x80 | (cp & 0x3F)]
        )
    return (
        _BYTES[0xF0 | (cp >> 18)] +
        _BYTES[0x80 | ((cp >> 12) & 0x3F)] +
        _BYTES[0x80 | ((cp >> 6) & 0x3F)] +
        _BYTES[0x80 | (cp & 0x3F)]
    )

def _decode_python_str(ctx, start, end):
    """Decodes the quoted string `src[start:end + 1]` like `ast.literal_eval`."""
    body = ctx.src[start + 1:end]
    if "\\" not in body and "\n" not in body and "\r" not in body and "\000" not in body:
        return body

    out = []
    n = len(body)
    i = 0
    for _ in range(n):
        if i >= n:
            break
        c = body[i]
        if c == "\n" or c == "\r" or c == "\000":
            syntax_error(ctx, "Invalid string literal (unescaped newline or NUL character)", start, end + 1)
        if c != "\\":
            out.append(c)
            i += 1
            continue
        if i + 1 >= n:
            syntax_error(ctx, "Invalid string literal (the closing quote is escaped)", start, end + 1)
        d = body[i + 1]
        if d in _SIMPLE_ESCAPES:
            out.append(_SIMPLE_ESCAPES[d])
            i += 2
        elif d == "\r":
            # Line continuation (\r or \r\n).
            i += 2
            if i < n and body[i] == "\n":
                i += 1
        elif d in _OCT_DIGITS:
            j = i + 1
            for _ in range(3):
                if j < n and body[j] in _OCT_DIGITS:
                    j += 1
                else:
                    break
            out.append(_utf8(int(body[i + 1:j], 8)))
            i = j
        elif d in _HEX_ESCAPE_LEN:
            count = _HEX_ESCAPE_LEN[d]
            digits = body[i + 2:i + 2 + count]
            if len(digits) != count or digits.lstrip(_HEX_DIGITS):
                syntax_error(ctx, "Invalid string literal (truncated \\{} escape)".format(d), start, end + 1)
            cp = int(digits, 16)
            if cp > 0x10FFFF:
                syntax_error(ctx, "Invalid string literal (illegal Unicode character)", start, end + 1)
            out.append(_utf8(cp))
            i += 2 + count
        elif d == "N":
            syntax_error(ctx, "Invalid string literal (\\N{...} escapes are not supported)", start, end + 1)
        elif d == "\000":
            syntax_error(ctx, "Invalid string literal (NUL character)", start, end + 1)
        else:
            # Unknown escapes are kept verbatim, like Python.
            out.append("\\")
            i += 1
    return "".join(out)

# ---------------------------------------------------------------------------
# Marker parser
# ---------------------------------------------------------------------------

def _variable(name):
    return struct(type = "variable", value = name)

def _string(value):
    return struct(type = "string", value = value)

def _parse_marker_var(ctx, pos):
    """marker_var = VARIABLE | QUOTED_STRING"""
    src = ctx.src
    if _is_boundary(src, pos):
        for v in _VARIABLES:
            if src.startswith(v, pos) and _is_boundary(src, pos + len(v)):
                name = v.replace(".", "_")
                if name == "python_implementation":
                    name = "platform_python_implementation"
                return _variable(name), pos + len(v)
    if pos < len(src) and src[pos] in "'\"":
        end = src.find(src[pos], pos + 1)
        if end != -1:
            return _string(_decode_python_str(ctx, pos, end)), end + 1
    syntax_error(ctx, "Expected a marker variable or quoted string", pos)
    return None, pos  # Unreachable

def _parse_marker_op(ctx, pos):
    """marker_op = IN | NOT IN | OP"""
    src = ctx.src
    if _match_word(src, pos, "in"):
        return "in", pos + 2
    if _match_word(src, pos, "not"):
        pos += 3
        if pos >= len(src) or src[pos] not in _WS:
            syntax_error(ctx, "Expected whitespace after 'not'", pos)
        pos = skip_ws(src, pos)
        if not _match_word(src, pos, "in"):
            syntax_error(ctx, "Expected 'in' after 'not'", pos)
        return "not in", pos + 2
    for op in _OPS:
        if src.startswith(op, pos):
            return op, pos + len(op)
    syntax_error(ctx, "Expected marker operator, one of <=, <, !=, ==, >=, >, ~=, ===, in, not in", pos)
    return None, pos  # Unreachable

def _parse_marker_item(ctx, pos):
    """marker_item = WS? marker_var WS? marker_op WS? marker_var WS?"""
    src = ctx.src
    pos = skip_ws(src, pos)
    lhs, pos = _parse_marker_var(ctx, pos)
    pos = skip_ws(src, pos)
    op, pos = _parse_marker_op(ctx, pos)
    pos = skip_ws(src, pos)
    rhs, pos = _parse_marker_var(ctx, pos)
    pos = skip_ws(src, pos)

    # PEP 685: normalize the value compared against `extra` (upstream
    # `_normalize_extras`). Upstream only does this for top-level items, so
    # `(extra == 'Foo_Bar')` never matches there; we normalize at every
    # nesting level.
    if lhs.type == "variable" and lhs.value == "extra":
        rhs = _string(utils.canonicalize_name(rhs.value))
    elif rhs.type == "variable" and rhs.value == "extra":
        lhs = _string(utils.canonicalize_name(lhs.value))
    return (lhs, op, rhs), pos

def parse_marker_expression(ctx, pos):
    """Parses `marker = marker_atom (BOOLOP marker_atom)*` starting at `pos`.

    Iterative (no recursion), so arbitrarily deep nesting is supported.
    Internal helper shared with requirements.bzl; not part of the public API.

    Args:
        ctx: A struct with `src` and `label` (see `syntax_error`).
        pos: The start position.

    Returns:
        A tuple of (marker tree, position after the marker and any trailing
        whitespace).
    """
    src = ctx.src
    n = len(src)
    stack = []  # (open paren position, parent expression)
    current = []

    # Every iteration consumes at least one character ("(" or a marker item).
    for _ in range(n + 1):
        # marker_atom: WS? "(" WS? marker WS? ")" WS? | WS? marker_item WS?
        pos = skip_ws(src, pos)
        if pos < n and src[pos] == "(":
            stack.append((pos, current))
            current = []
            pos += 1
            continue

        item, pos = _parse_marker_item(ctx, pos)
        current.append(item)

        # After an atom: look for a BOOLOP, else close a parenthesis.
        expect_atom = False
        for _ in range(len(stack) + 1):
            if _match_word(src, pos, "and") or _match_word(src, pos, "or"):
                op = "and" if src.startswith("and", pos) else "or"
                current.append(op)
                pos += len(op)
                expect_atom = True
                break
            if not stack:
                return current, pos
            if pos < n and src[pos] == ")":
                _open_pos, parent = stack.pop()
                parent.append(current)
                current = parent
                pos = skip_ws(src, pos + 1)
            else:
                syntax_error(
                    ctx,
                    "Expected matching RIGHT_PARENTHESIS for LEFT_PARENTHESIS, after marker expression",
                    stack[-1][0],
                    pos,
                )
        if not expect_atom:
            fail("internal error: marker parser did not terminate")

    fail("internal error: marker parser did not terminate")

def parse_marker(marker_str):
    """Parses a PEP 508 marker string into an AST-like structure.

    The grammar, error conditions and value processing follow
    `packaging.markers.Marker` (packaging 26.2): quoted strings are decoded like
    Python string literals (`\\N{...}` escapes are not supported), dotted
    variable names are mapped to their underscore form, `python_implementation`
    is an alias for `platform_python_implementation`, and the value compared
    against `extra` is normalized (PEP 685) at every nesting level.

    Unlike upstream, the empty string is accepted and returns `[]`, which
    `evaluate` treats as always true. Whitespace-only input is rejected.

    Invalid input fails with an upstream-style message that shows the marker
    and a caret at the error position.

    Args:
        marker_str: The marker string to parse.

    Returns:
        A list representing the parsed marker tree. Each comparison is a tuple
        `(lhs, op, rhs)` where `lhs`/`rhs` are `struct(type, value)` with
        `type` either "variable" or "string" and `op` a string such as "==",
        "in" or "not in"; boolean operators are the strings "and"/"or"; and
        parenthesized groups are nested lists.
    """
    if marker_str == "":
        return []
    ctx = struct(src = marker_str, label = "Invalid marker")
    tree, pos = parse_marker_expression(ctx, 0)
    if not at_end(marker_str, pos):
        syntax_error(ctx, "Expected end of marker expression", pos)
    return tree

# ---------------------------------------------------------------------------
# Serialization (upstream `str(Marker)`)
# ---------------------------------------------------------------------------

def _format_node(node):
    if node.type == "string":
        return "\"" + node.value + "\""
    return node.value

def _format_item(item):
    lhs, op, rhs = item
    return "{} {} {}".format(_format_node(lhs), op, _format_node(rhs))

def marker_to_string(markers):
    """Serializes a parsed marker tree like upstream `str(Marker)`.

    Variables are emitted in their normalized form and string values are
    always double-quoted (without escaping, like upstream). Redundant
    parentheses around a whole group are dropped.

    Divergence: upstream also drops the parentheses of a doubly parenthesized
    nested group, e.g. `a and ((b or c))` becomes `a and b or c`, which changes
    the meaning. This implementation keeps them: `a and (b or c)`.

    Args:
        markers: A parsed marker tree (from `parse`).

    Returns:
        The normalized marker string ("" for an empty tree).
    """
    out = []

    # Work items: ("node", node, first) or ("text", text), processed LIFO.
    work = [("node", markers, True)]
    for _ in range(1 << 30):
        if not work:
            break
        entry = work.pop()
        if entry[0] == "text":
            out.append(entry[1])
            continue
        node = entry[1]
        first = entry[2]

        # A single-element list wrapping a list or item is formatted as its
        # element (upstream `_format_marker`).
        for _ in range(1 << 30):
            if type(node) == "list" and len(node) == 1 and type(node[0]) in ("list", "tuple"):
                node = node[0]
            else:
                break

        if type(node) == "tuple":
            out.append(_format_item(node))
        elif type(node) == "list":
            if not first:
                work.append(("text", ")"))
            for i in range(len(node) - 1, -1, -1):
                work.append(("node", node[i], False))
                if i:
                    work.append(("text", " "))
            if not first:
                work.append(("text", "("))
        else:
            out.append(node)
    return "".join(out)

# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------

_MARKERS_REQUIRING_VERSION = {
    "implementation_version": True,
    "platform_release": True,
    "python_full_version": True,
    "python_version": True,
}

_MARKERS_ALLOWING_SET = {
    "dependency_groups": True,
    "extras": True,
}

_COLLECTION_TYPES = ("list", "tuple", "set", "dict")

# Characters matched by Python's `\s` in the ASCII range, sorted.
_PY_WS = "\t\n\013\014\r\034\035\036\037 "

# Local, non-failing validators that mirror upstream's
# `try: Specifier(op + value) except InvalidSpecifier` and the implicit
# `Version(...)` parse in `Specifier.contains` (see `_eval_item`). They follow
# `packaging.specifiers.Specifier._regex` and `packaging.version.VERSION_PATTERN`.
# TODO: switch to non-failing parse helpers from specifiers.bzl / version.bzl
# once those exist.
_PRE = r"(?:[-_.]?(?:alpha|beta|preview|pre|a|b|c|rc)[-_.]?[0-9]*)?"
_POST = r"(?:-[0-9]+|[-_.]?(?:post|rev|r)[-_.]?[0-9]*)?"
_DEV = r"(?:[-_.]?dev[-_.]?[0-9]*)?"
_LOCAL = r"(?:\+[a-z0-9]+(?:[-_.][a-z0-9]+)*)?"
_RELEASE = r"v?(?:[0-9]+!)?[0-9]+(?:\.[0-9]+)*"

_SPECIFIER_RE = re.compile(
    r"\s*(?:" +
    r"===\s*[^\s;)]*" +
    r"|(?:==|!=)\s*" + _RELEASE + r"(?:\.\*|" + _PRE + _POST + _DEV + _LOCAL + r")?" +
    r"|~=\s*v?(?:[0-9]+!)?[0-9]+(?:\.[0-9]+)+" + _PRE + _POST + _DEV +
    r"|(?:<=|>=|<|>)\s*" + _RELEASE + _PRE + _POST + _DEV +
    r")\s*",
    re.I,
)

_VERSION_RE = re.compile(_RELEASE + _PRE + _POST + _DEV + _LOCAL, re.I)

_DIGITS_AND_DOT = ".0123456789"

def _is_plain_release(s):
    return s != "" and not s.lstrip(_DIGITS_AND_DOT) and "" not in s.split(".")

def _is_valid_specifier(spec_str):
    # Fast path for the common `<op><digits and dots>` form.
    for op in _OPS:
        if spec_str.startswith(op):
            rest = spec_str[len(op):]
            if _is_plain_release(rest) and (op != "~=" or "." in rest):
                return True
            break
    return _SPECIFIER_RE.fullmatch(spec_str) != None

def _is_valid_version(s):
    return _is_plain_release(s) or _VERSION_RE.fullmatch(s) != None

def _env_lookup(environment, key, item):
    value = environment.get(key)
    if value == None:
        fail("Undefined environment variable '{}' in marker `{}`".format(key, _format_item(item)))
    return value

def _canonicalize_collection(value, key, item):
    out = []
    for v in value:
        if type(v) != "string":
            fail("Marker environment value for '{}' must contain only strings, got {} (in marker `{}`)".format(
                key,
                type(v),
                _format_item(item),
            ))
        out.append(utils.canonicalize_name(v))
    return out

def _eval_item(item, environment):
    lhs, op, rhs = item

    if lhs.type == "variable":
        key = lhs.value
        lhs_val = _env_lookup(environment, key, item)
        rhs_val = rhs.value
        env_val = lhs_val
    else:
        key = rhs.value
        lhs_val = lhs.value
        rhs_val = _env_lookup(environment, key, item)
        env_val = rhs_val

    # Non-standard, uv-compatible extension: `extra` may be a list/tuple of
    # active extras (already normalized by `_prepare_environment`).
    if key == "extra" and type(env_val) in ("list", "tuple"):
        value = rhs_val if lhs.type == "variable" else lhs_val
        if op == "==" or op == "===":
            return value in env_val
        if op == "!=":
            return value not in env_val
        fail("Operator '{}' is not supported when 'extra' is a list of extras (in marker `{}`); only ==, === and != are".format(
            op,
            _format_item(item),
        ))

    if type(lhs_val) != "string":
        fail("Cannot evaluate marker `{}`: the left-hand side must be a string, but '{}' is a {}".format(
            _format_item(item),
            key,
            type(lhs_val),
        ))
    if type(rhs_val) != "string" and type(rhs_val) not in _COLLECTION_TYPES:
        fail("Marker environment value for '{}' must be a string or a collection of strings, got {} (in marker `{}`)".format(
            key,
            type(rhs_val),
            _format_item(item),
        ))

    if key in _MARKERS_ALLOWING_SET:
        lhs_val = utils.canonicalize_name(lhs_val)
        if type(rhs_val) == "string":
            rhs_val = utils.canonicalize_name(rhs_val)
        else:
            rhs_val = _canonicalize_collection(rhs_val, key, item)

    # Upstream `_eval_op`: version comparison when `op + rhs` is a valid
    # specifier; otherwise fall through to the string operator table.
    if key in _MARKERS_REQUIRING_VERSION and type(rhs_val) == "string" and op != "in" and op != "not in":
        spec_str = op + rhs_val
        if _is_valid_specifier(spec_str):
            spec = parse_specifier(spec_str)
            if spec.operator == "===":
                return specifier_contains(spec, lhs_val)
            stripped = lhs_val.strip(_PY_WS)
            if not _is_valid_version(stripped):
                return False
            return specifier_contains(spec, stripped)

    if op == "in":
        return lhs_val in rhs_val
    if op == "not in":
        return lhs_val not in rhs_val
    if op == "<" or op == ">":
        return False
    if op == "==" or op == "<=" or op == ">=":
        return lhs_val == rhs_val
    if op == "!=":
        return lhs_val != rhs_val
    fail("Undefined comparison: operator '{}' is not defined for {} and {} (in marker `{}`)".format(
        op,
        repr(lhs_val),
        repr(rhs_val),
        _format_item(item),
    ))

def _prepare_environment(environment):
    env = dict(environment)

    extra = env.get("extra")
    if extra == None or extra == "":
        env["extra"] = ""
    elif type(extra) == "string":
        env["extra"] = utils.canonicalize_name(extra)
    elif type(extra) in ("list", "tuple"):
        out = []
        for e in extra:
            if type(e) != "string":
                fail("Marker environment value for 'extra' must be a string or a list/tuple of strings, got an element of type {}".format(type(e)))
            out.append(utils.canonicalize_name(e))
        env["extra"] = out
    else:
        fail("Marker environment value for 'extra' must be a string or a list/tuple of strings, got {}".format(type(extra)))

    # Upstream `_repair_python_full_version`.
    python_full_version = env.get("python_full_version")
    if type(python_full_version) == "string" and python_full_version.endswith("+"):
        env["python_full_version"] = python_full_version + "local"
    return env

def evaluate_markers(markers, environment):
    """Evaluates a parsed marker expression against an environment.

    Semantics follow `packaging.markers.Marker.evaluate` (packaging 26.2):

    - `python_version`, `python_full_version`, `implementation_version` and
      `platform_release` are compared as PEP 440 versions when `op + value` is a
      valid specifier (pre-releases always match). If it is not a valid
      specifier, the comparison falls back to the string table below; if the
      version being tested is not a valid version, the comparison is False. A
      `python_full_version` ending in "+" gets "local" appended first.
    - All other comparisons use upstream's string table: `==`, `!=`, `in` and
      `not in` as usual, `<` and `>` are always False, `<=` and `>=` mean
      equality, and `~=` and `===` fail ("Undefined comparison").
    - `extra`, `extras` and `dependency_groups` values are normalized (PEP 685
      / PEP 735) on both sides.

    There is no default environment: every variable the marker references must
    be present, except `extra`, which defaults to "" (None is also treated as
    ""). Callers must supply `extras` / `dependency_groups` (as lists of
    strings) when markers use them.

    Non-standard extension (uv-compatible): `environment["extra"]` may be a
    list or tuple of strings, the set of active extras (uv also uses this for
    its conflict tokens). Each element is normalized. `extra == X`,
    `X == extra` and `===` are True iff X is in the set; `!=` is True iff it is
    not. An empty list therefore makes `==` False and `!=` True. Any other
    operator with a list-valued `extra` fails.

    Args:
        markers: The parsed marker tree (list), as returned by `parse`. An
            empty list evaluates to True.
        environment: A dict mapping marker variable names (underscore form)
            to values.

    Returns:
        True if the markers evaluate to true, False otherwise.
    """
    if not markers:
        return True

    environment = _prepare_environment(environment)

    # Stack holds tuples: (markers_list, index, groups)
    stack = [(markers, 0, [[]])]

    # Each step advances an index or pops a level, so this always terminates.
    for _ in range(1 << 30):
        current_markers, i, groups = stack[-1]

        if i >= len(current_markers):
            # Level finished: any(all(g) for g in groups)
            result = False
            for g in groups:
                if all(g):
                    result = True
                    break
            stack.pop()
            if not stack:
                return result
            stack[-1][2][-1].append(result)
            continue

        marker = current_markers[i]
        stack[-1] = (current_markers, i + 1, groups)

        if type(marker) == "list":
            stack.append((marker, 0, [[]]))
        elif type(marker) == "tuple":
            groups[-1].append(_eval_item(marker, environment))
        elif marker == "or":
            groups.append([])
        elif marker == "and":
            pass
        else:
            fail("Unexpected marker: {}".format(marker))

    fail("internal error: marker evaluation did not terminate")

markers = struct(
    parse = parse_marker,
    evaluate = evaluate_markers,
    to_string = marker_to_string,
)
