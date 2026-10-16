"""PEP 508 Marker parsing and evaluation.

Derived from pypa/packaging: packaging/markers.py (Apache 2.0 / BSD).
Baseline: pypa/packaging 26.2
"""

load("@re.bzl", "re")
load("//pypackaging/private/specifiers:specifiers.bzl", "parse_specifier", "specifier_contains")
load("//pypackaging/private/utils:utils.bzl", "utils")

_WS = " \t"
_IDENT_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_."

# Longest first to avoid prefix matching issues
_VALID_VARS = (
    "platform.python_implementation",
    "platform_python_implementation",
    "python_full_version",
    "implementation_version",
    "python_implementation",
    "implementation_name",
    "dependency_groups",
    "platform_release",
    "platform_system",
    "platform.machine",
    "platform_machine",
    "platform.version",
    "platform_version",
    "python_version",
    "sys.platform",
    "sys_platform",
    "extras",
    "extra",
    "os.name",
    "os_name",
)

def _is_word_char(c):
    return c in _IDENT_CHARS

def _check_word_boundary(source, start, length):
    end = start + length
    if start > 0 and _is_word_char(source[start - 1]):
        return False
    if end < len(source) and _is_word_char(source[end]):
        return False
    return True

def _make_tokenizer(source):
    # Use a dict to allow mutation in Starlark
    return {
        "source": source,
        "position": 0,
        "next_token": None,
    }

def _tokenizer_check(tokenizer, name, peek = False):
    if tokenizer["next_token"] != None:
        fail("Cannot check for {}, already have {}".format(name, tokenizer["next_token"]))

    pos = tokenizer["position"]
    source = tokenizer["source"]

    if pos >= len(source):
        if name == "END":
            if not peek:
                tokenizer["next_token"] = struct(name = "END", text = "", position = pos)
            return True
        return False

    if name == "WS":
        if source[pos] not in _WS:
            return False
        i = pos
        for _ in range(len(source) - pos):
            if i < len(source) and source[i] in _WS:
                i += 1
            else:
                break
        if not peek:
            tokenizer["next_token"] = struct(name = "WS", text = source[pos:i], position = pos)
        return True

    if name == "LEFT_PARENTHESIS":
        if source[pos] == "(":
            if not peek:
                tokenizer["next_token"] = struct(name = "LEFT_PARENTHESIS", text = "(", position = pos)
            return True
        return False

    if name == "RIGHT_PARENTHESIS":
        if source[pos] == ")":
            if not peek:
                tokenizer["next_token"] = struct(name = "RIGHT_PARENTHESIS", text = ")", position = pos)
            return True
        return False

    if name == "QUOTED_STRING":
        q = source[pos]
        if q not in ("'", '"'):
            return False
        i = pos + 1
        found = False
        for _ in range(len(source) - i):
            if i < len(source):
                if source[i] == q:
                    found = True
                    i += 1
                    break
                i += 1
        if not found:
            return False
        if not peek:
            tokenizer["next_token"] = struct(name = "QUOTED_STRING", text = source[pos:i], position = pos)
        return True

    if name == "OP":
        # Longest first
        valid_ops = ("===", "==", "~=", "!=", "<=", ">=", "<", ">")
        for op in valid_ops:
            if source.startswith(op, pos):
                if not peek:
                    tokenizer["next_token"] = struct(name = "OP", text = op, position = pos)
                return True
        return False

    if name == "BOOLOP":
        for op in ("or", "and"):
            if source.startswith(op, pos) and _check_word_boundary(source, pos, len(op)):
                if not peek:
                    tokenizer["next_token"] = struct(name = "BOOLOP", text = op, position = pos)
                return True
        return False

    if name == "IN":
        if source.startswith("in", pos) and _check_word_boundary(source, pos, 2):
            if not peek:
                tokenizer["next_token"] = struct(name = "IN", text = "in", position = pos)
            return True
        return False

    if name == "NOT":
        if source.startswith("not", pos) and _check_word_boundary(source, pos, 3):
            if not peek:
                tokenizer["next_token"] = struct(name = "NOT", text = "not", position = pos)
            return True
        return False

    if name == "VARIABLE":
        for v in _VALID_VARS:
            if source.startswith(v, pos) and _check_word_boundary(source, pos, len(v)):
                if not peek:
                    tokenizer["next_token"] = struct(name = "VARIABLE", text = v, position = pos)
                return True
        return False

    if name == "END":
        # Handled at start if pos >= len(source)
        return False

    fail("Unknown token name: {}".format(name))

def _tokenizer_read(tokenizer):
    token = tokenizer["next_token"]
    if token == None:
        fail("No token to read")

    tokenizer["position"] += len(token.text)
    tokenizer["next_token"] = None

    return token

def _tokenizer_consume(tokenizer, name):
    if _tokenizer_check(tokenizer, name):
        _tokenizer_read(tokenizer)

def _tokenizer_expect(tokenizer, name, expected):
    if not _tokenizer_check(tokenizer, name):
        fail("Expected {}".format(expected))
    return _tokenizer_read(tokenizer)

def _parse_marker_var(tokenizer):
    if _tokenizer_check(tokenizer, "VARIABLE"):
        token = _tokenizer_read(tokenizer)
        name = token.text.replace(".", "_")
        if name == "python_implementation":
            name = "platform_python_implementation"
        return struct(type = "variable", value = name)
    elif _tokenizer_check(tokenizer, "QUOTED_STRING"):
        token = _tokenizer_read(tokenizer)

        # Strip quotes
        val = token.text[1:-1]
        return struct(type = "string", value = val)
    else:
        fail("Expected a marker variable or quoted string")

def _parse_marker_op(tokenizer):
    if _tokenizer_check(tokenizer, "IN"):
        _tokenizer_read(tokenizer)
        return "in"
    elif _tokenizer_check(tokenizer, "NOT"):
        _tokenizer_read(tokenizer)
        _tokenizer_expect(tokenizer, "WS", "whitespace after 'not'")
        _tokenizer_expect(tokenizer, "IN", "'in' after 'not'")
        return "not in"
    elif _tokenizer_check(tokenizer, "OP"):
        token = _tokenizer_read(tokenizer)
        return token.text
    else:
        fail("Expected marker operator")

def _parse_marker_item(tokenizer):
    _tokenizer_consume(tokenizer, "WS")
    lhs = _parse_marker_var(tokenizer)
    _tokenizer_consume(tokenizer, "WS")
    op = _parse_marker_op(tokenizer)
    _tokenizer_consume(tokenizer, "WS")
    rhs = _parse_marker_var(tokenizer)
    _tokenizer_consume(tokenizer, "WS")
    return (lhs, op, rhs)

def parse_marker(marker_str):
    """Parses a PEP 508 marker string into an AST-like structure.

    Args:
        marker_str: The marker string to parse.

    Returns:
        A list representing the parsed marker tree.
    """
    if not marker_str.strip():
        return []

    tokenizer = _make_tokenizer(marker_str)
    current_expr = []
    expr_stack = []
    expecting_atom = True

    for _ in range(len(marker_str) + 1):
        _tokenizer_consume(tokenizer, "WS")

        if _tokenizer_check(tokenizer, "END", peek = True):
            break

        if expecting_atom:
            if _tokenizer_check(tokenizer, "LEFT_PARENTHESIS"):
                _tokenizer_read(tokenizer)  # consume '('
                expr_stack.append(current_expr)
                current_expr = []
            else:
                item = _parse_marker_item(tokenizer)
                current_expr.append(item)
                expecting_atom = False
        elif _tokenizer_check(tokenizer, "BOOLOP"):
            token = _tokenizer_read(tokenizer)
            current_expr.append(token.text)
            expecting_atom = True
        elif _tokenizer_check(tokenizer, "RIGHT_PARENTHESIS"):
            _tokenizer_read(tokenizer)  # consume ')'
            if not expr_stack:
                fail("Unexpected ')'")
            subexpr = current_expr
            current_expr = expr_stack.pop()
            current_expr.append(subexpr)
        else:
            fail("Expected BOOLOP or ')'")

    if expr_stack:
        fail("Missing ')'")
    if not _tokenizer_check(tokenizer, "END", peek = True):
        fail("Marker parsing exceeded iteration limit")

    return current_expr

_OPS = ("===", "==", "~=", "!=", "<=", ">=", "<", ">")

def _format_node(node):
    if node.type == "string":
        return "\"" + node.value + "\""
    return node.value

def _format_item(item):
    lhs, op, rhs = item
    return "{} {} {}".format(_format_node(lhs), op, _format_node(rhs))

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

    # PEP 685: normalize the value compared against `extra`.
    if key == "extra":
        if lhs.type == "variable":
            rhs_val = utils.canonicalize_name(rhs_val)
        else:
            lhs_val = utils.canonicalize_name(lhs_val)

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
)
