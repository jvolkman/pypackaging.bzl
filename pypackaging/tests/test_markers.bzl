"""Tests for markers.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/markers:markers.bzl", "markers")

_ENV = {
    "implementation_name": "cpython",
    "implementation_version": "3.12.4",
    "os_name": "posix",
    "platform_machine": "x86_64",
    "platform_python_implementation": "CPython",
    "platform_release": "",
    "platform_system": "Linux",
    "platform_version": "",
    "python_full_version": "3.12.4",
    "python_version": "3.12",
    "sys_platform": "linux",
}

def _eval(marker, **overrides):
    env = dict(_ENV)
    env.update(overrides)
    return markers.evaluate(markers.parse(marker), env)

def _test_marker_parser_impl(env, _target):
    # Simple
    m = markers.parse("python_version >= '3.6'")
    env.expect.that_int(len(m)).equals(1)
    item = m[0]
    env.expect.that_str(item[0].type).equals("variable")
    env.expect.that_str(item[0].value).equals("python_version")
    env.expect.that_str(item[1]).equals(">=")
    env.expect.that_str(item[2].type).equals("string")
    env.expect.that_str(item[2].value).equals("3.6")

    # With parens
    m = markers.parse("(python_version >= '3.6')")
    env.expect.that_int(len(m)).equals(1)
    sub = m[0]
    env.expect.that_int(len(sub)).equals(1)
    item = sub[0]
    env.expect.that_str(item[0].value).equals("python_version")

    # Complex
    m = markers.parse("python_version >= '3.6' and os_name == 'posix'")
    env.expect.that_int(len(m)).equals(3)
    env.expect.that_str(m[1]).equals("and")

    # In
    m = markers.parse("python_version in '3.6 3.7'")
    env.expect.that_int(len(m)).equals(1)
    item = m[0]
    env.expect.that_str(item[1]).equals("in")

    # Not In
    m = markers.parse("python_version not in '3.6 3.7'")
    env.expect.that_int(len(m)).equals(1)
    item = m[0]
    env.expect.that_str(item[1]).equals("not in")

def _test_marker_parser(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_parser_impl)

def _test_marker_evaluation_impl(env, _target):
    env_vars = {
        "python_version": "3.7",
        "os_name": "posix",
        "sys_platform": "linux",
        "platform_python_implementation": "CPython",
        "dependency_groups": ["dev", "test"],
        "extras": ["foo", "Bar"],  # Mixed case to test normalization
    }

    # Dependency Groups
    m = markers.parse("'dev' in dependency_groups")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    m = markers.parse("'docs' in dependency_groups")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(False)

    # Extras plural
    m = markers.parse("'foo' in extras")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    m = markers.parse("'bar' in extras")  # Should match 'Bar' due to normalization
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    m = markers.parse("'baz' in extras")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(False)

    # Normalization tests
    m = markers.parse("'dev-group' in dependency_groups")
    env_vars_norm = dict(env_vars)
    env_vars_norm["dependency_groups"] = ["dev_group"]  # Underscore should match hyphen
    env.expect.that_bool(markers.evaluate(m, env_vars_norm)).equals(True)

    # Extra singular
    m = markers.parse("extra == 'dev'")
    env_vars_extra = dict(env_vars)
    env_vars_extra["extra"] = "dev"
    env.expect.that_bool(markers.evaluate(m, env_vars_extra)).equals(True)

    # Extra missing (treated as empty string)
    m = markers.parse("extra == ''")
    env_vars_no_extra = dict(env_vars)

    # Don't set "extra"
    env.expect.that_bool(markers.evaluate(m, env_vars_no_extra)).equals(True)

    # Extra normalization
    m = markers.parse("extra == 'dev-group'")
    env_vars_extra_norm = dict(env_vars)
    env_vars_extra_norm["extra"] = "dev_group"
    env.expect.that_bool(markers.evaluate(m, env_vars_extra_norm)).equals(True)

    # Extra as list (multiple active extras / uv conflict tokens)
    env_vars_extra_list = dict(env_vars)
    env_vars_extra_list["extra"] = ["cudart", "group_18_native_torch_probe_cuda"]
    env.expect.that_bool(markers.evaluate(markers.parse("extra == 'cudart'"), env_vars_extra_list)).equals(True)
    env.expect.that_bool(markers.evaluate(markers.parse("'cudart' == extra"), env_vars_extra_list)).equals(True)
    env.expect.that_bool(markers.evaluate(markers.parse("extra == 'group-18-native-torch-probe-cuda'"), env_vars_extra_list)).equals(True)
    env.expect.that_bool(markers.evaluate(markers.parse("extra == 'group-18-native-torch-probe-cpu'"), env_vars_extra_list)).equals(False)
    env.expect.that_bool(markers.evaluate(markers.parse("extra != 'group-18-native-torch-probe-cpu'"), env_vars_extra_list)).equals(True)
    env.expect.that_bool(markers.evaluate(markers.parse("extra != 'cudart'"), env_vars_extra_list)).equals(False)
    env.expect.that_bool(markers.evaluate(markers.parse("'cudart' != extra"), env_vars_extra_list)).equals(False)

    # Large marker (>1000 tokens) parses and evaluates without truncation
    large_clauses = ["extra == 'tok-{}'".format(i) for i in range(600)]
    large_marker_str = " or ".join(large_clauses)
    large_parsed = markers.parse(large_marker_str)
    env.expect.that_int(len(large_parsed)).equals(1199)
    env.expect.that_bool(markers.evaluate(large_parsed, {"extra": ["tok-599"]})).equals(True)
    env.expect.that_bool(markers.evaluate(large_parsed, {"extra": ["tok-600"]})).equals(False)

    # Simple True
    m = markers.parse("python_version >= '3.6'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # Simple False
    m = markers.parse("python_version < '3.6'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(False)

    # AND True
    m = markers.parse("python_version >= '3.6' and os_name == 'posix'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # AND False
    m = markers.parse("python_version >= '3.6' and os_name == 'nt'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(False)

    # OR True
    m = markers.parse("python_version < '3.6' or os_name == 'posix'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # Nested
    m = markers.parse("python_version < '3.6' or (os_name == 'posix' and sys_platform == 'linux')")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # In
    m = markers.parse("python_version in '3.6 3.7'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # Not In
    m = markers.parse("python_version not in '3.6 3.7'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(False)

    # Version marker with 'in' (should be treated as string containment)
    m = markers.parse("python_version in '3.7.1 3.7.2'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # Precedence test vars
    env_vars_prec = {
        "python_version": "3.5",  # python_version < '3.6' is True
        "os_name": "nt",  # os_name == 'posix' is False
        "sys_platform": "win32",  # sys_platform == 'linux' is False
    }

    # Standard precedence: A or B and C -> True or (False and False) -> True
    m = markers.parse("python_version < '3.6' or os_name == 'posix' and sys_platform == 'linux'")
    env.expect.that_bool(markers.evaluate(m, env_vars_prec)).equals(True)

    # Explicit precedence: (A or B) and C -> (True or False) and False -> False
    m = markers.parse("(python_version < '3.6' or os_name == 'posix') and sys_platform == 'linux'")
    env.expect.that_bool(markers.evaluate(m, env_vars_prec)).equals(False)

def _test_marker_evaluation(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_evaluation_impl)

def _test_version_marker_fallback_impl(env, _target):
    # Upstream `_eval_op`: an invalid environment version makes the comparison
    # False instead of failing.
    env.expect.that_bool(_eval("platform_release >= '5'")).equals(False)
    env.expect.that_bool(_eval("platform_release >= '5'", platform_release = "6.8.0-1015-gcp")).equals(False)
    env.expect.that_bool(_eval("python_version >= '3.8'", python_version = "")).equals(False)
    env.expect.that_bool(_eval("'3.*' == python_version")).equals(False)
    env.expect.that_bool(_eval("platform_release != '5'", platform_release = "6.8.0-1015-gcp")).equals(False)

    # An invalid specifier falls back to the string operator table.
    env.expect.that_bool(_eval("platform_release == '6.8.0-1015-gcp'", platform_release = "6.8.0-1015-gcp")).equals(True)
    env.expect.that_bool(_eval("platform_release == ''")).equals(True)
    env.expect.that_bool(_eval("platform_release != ''")).equals(False)
    env.expect.that_bool(_eval("python_version > '3.10.*'")).equals(False)
    env.expect.that_bool(_eval("python_version >= '3.12.*'")).equals(False)
    env.expect.that_bool(_eval("python_version <= '3.12.*'")).equals(False)
    env.expect.that_bool(_eval("python_version != 'abc'")).equals(True)
    env.expect.that_bool(_eval("python_version < 'abc'")).equals(False)

    # `===` compares strings (case-insensitively), even for invalid versions.
    env.expect.that_bool(_eval("platform_release === '6.8.0-1015-GCP'", platform_release = "6.8.0-1015-gcp")).equals(True)
    env.expect.that_bool(_eval("python_version === '3.12.0'")).equals(False)
    env.expect.that_bool(_eval("python_version === ' 3.12'")).equals(True)

    # Unicode whitespace around versions is ignored, like Python's str.strip().
    env.expect.that_bool(_eval("python_version == '\302\2403.12'")).equals(True)
    env.expect.that_bool(_eval("python_version == '3.12'", python_version = "3.12\302\240")).equals(True)
    env.expect.that_bool(_eval("python_version >= '3.8'", python_version = " 3.9 ")).equals(True)
    env.expect.that_bool(_eval("python_version > '\302\240x'")).equals(False)

    # The value is appended to the operator before parsing, like upstream.
    env.expect.that_bool(_eval("python_version < '=3.12'")).equals(True)
    env.expect.that_bool(_eval("python_version == '=3.12'")).equals(True)

    # Valid versions keep PEP 440 semantics; pre-releases always match.
    env.expect.that_bool(_eval("python_version == '3.12.0'")).equals(True)
    env.expect.that_bool(_eval("python_version == '3.12.*'")).equals(True)
    env.expect.that_bool(_eval("python_version != '3.11.*'")).equals(True)
    env.expect.that_bool(_eval("python_full_version > '3.12'", python_full_version = "3.13.0rc1")).equals(True)
    env.expect.that_bool(_eval("python_full_version < '3.13'", python_full_version = "3.13.0rc1")).equals(False)
    env.expect.that_bool(_eval("'3.12' < python_version", python_version = "3.13")).equals(True)

    # `in` / `not in` are substring tests, never version comparisons.
    env.expect.that_bool(_eval("'6.8' in platform_release", platform_release = "6.8.0-1015-gcp")).equals(True)
    env.expect.that_bool(_eval("python_version not in '3.10 3.11'")).equals(True)

    # `_repair_python_full_version` applies to the environment value for every operator.
    env.expect.that_bool(_eval("python_full_version >= '3.12.1'", python_full_version = "3.12.1+")).equals(True)
    env.expect.that_bool(_eval("python_full_version == '3.12.1+local'", python_full_version = "3.12.1+")).equals(True)
    env.expect.that_bool(_eval("python_full_version === '3.12.1+'", python_full_version = "3.12.1+")).equals(False)
    env.expect.that_bool(_eval("'local' in python_full_version", python_full_version = "3.12.1+")).equals(True)

def _test_version_marker_fallback(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_version_marker_fallback_impl)

def _test_string_operator_table_impl(env, _target):
    # Upstream `_operators`: `<`/`>` are always False, `<=`/`>=` mean equality.
    env.expect.that_bool(_eval("platform_machine < 'z'")).equals(False)
    env.expect.that_bool(_eval("platform_machine > 'a'")).equals(False)
    env.expect.that_bool(_eval("sys_platform >= 'darwin'")).equals(False)
    env.expect.that_bool(_eval("sys_platform >= 'linux'")).equals(True)
    env.expect.that_bool(_eval("sys_platform <= 'linux'")).equals(True)
    env.expect.that_bool(_eval("'3.11' < os_name")).equals(False)
    env.expect.that_bool(_eval("'lin' in sys_platform")).equals(True)
    env.expect.that_bool(_eval("sys_platform not in 'linux2'")).equals(False)
    env.expect.that_bool(_eval("sys_platform != 'linux'")).equals(False)

    # Both operands may be strings; the right-hand one names the environment key.
    env.expect.that_bool(_eval("'posix' == 'os_name'")).equals(True)

    # Variable-vs-variable compares against the right-hand variable's name.
    env.expect.that_bool(_eval("os_name == python_version", os_name = "python_version")).equals(True)

def _test_string_operator_table(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_string_operator_table_impl)

def _test_list_valued_extra_impl(env, _target):
    active = ["Foo.Bar", "baz", "extra-5-mypkg-cpu"]
    env.expect.that_bool(_eval("extra == 'foo-bar'", extra = active)).equals(True)
    env.expect.that_bool(_eval("extra == 'FOO_bar'", extra = active)).equals(True)
    env.expect.that_bool(_eval("'Baz' == extra", extra = active)).equals(True)
    env.expect.that_bool(_eval("extra == 'x'", extra = active)).equals(False)
    env.expect.that_bool(_eval("extra != 'x'", extra = active)).equals(True)
    env.expect.that_bool(_eval("extra != 'baz'", extra = active)).equals(False)
    env.expect.that_bool(_eval("'baz' != extra", extra = active)).equals(False)

    # Mixed real extra + synthetic uv conflict token.
    m = "extra == 'extra-5-mypkg-cpu' and extra != 'extra-5-mypkg-gpu'"
    env.expect.that_bool(_eval(m, extra = active)).equals(True)
    env.expect.that_bool(_eval(m, extra = ["foo", "extra-5-mypkg-gpu", "extra-5-mypkg-cpu"])).equals(False)
    env.expect.that_bool(_eval("(extra == 'foo-bar' or extra == 'nope') and os_name == 'posix'", extra = active)).equals(True)

    # Tuples behave like lists.
    env.expect.that_bool(_eval("extra == 'baz'", extra = ("baz",))).equals(True)
    env.expect.that_bool(_eval("extra != 'baz'", extra = ("baz",))).equals(False)

    # An empty list: `==` is False, `!=` is True.
    env.expect.that_bool(_eval("extra == 'baz'", extra = [])).equals(False)
    env.expect.that_bool(_eval("extra == ''", extra = [])).equals(False)
    env.expect.that_bool(_eval("extra != 'baz'", extra = [])).equals(True)

    # Scalar `extra` keeps upstream semantics (missing / None / "" all mean "").
    env.expect.that_bool(_eval("extra == ''")).equals(True)
    env.expect.that_bool(_eval("extra == ''", extra = None)).equals(True)
    env.expect.that_bool(_eval("extra == 'foo-bar'", extra = "Foo.Bar")).equals(True)
    env.expect.that_bool(_eval("extra in 'foo-bar'", extra = "Foo.Bar")).equals(True)
    env.expect.that_bool(_eval("extra < 'z'", extra = "Foo.Bar")).equals(False)
    env.expect.that_bool(_eval("extra <= 'foo-bar'", extra = "Foo.Bar")).equals(True)

def _test_list_valued_extra(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_list_valued_extra_impl)

def _test_marker_aliases_impl(env, _target):
    # `python_implementation` is an alias for `platform_python_implementation`.
    env.expect.that_bool(_eval("python_implementation == 'CPython'")).equals(True)
    env.expect.that_bool(_eval("platform.python_implementation == 'CPython'")).equals(True)
    m = markers.parse("python_implementation == 'CPython'")
    env.expect.that_str(m[0][0].value).equals("platform_python_implementation")

    # Dotted names map to the underscore form.
    env.expect.that_bool(_eval("os.name == 'posix' and sys.platform == 'linux'")).equals(True)
    env.expect.that_bool(_eval("platform.machine == 'x86_64' and platform.version == ''")).equals(True)

def _test_marker_aliases(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_aliases_impl)

def _test_marker_string_literals_impl(env, _target):
    # Quoted strings are decoded like Python string literals (ast.literal_eval).
    env.expect.that_bool(_eval("os_name == 'po\\x73ix'")).equals(True)
    env.expect.that_bool(_eval("os_name == 'p\\u006fsix'")).equals(True)
    env.expect.that_bool(_eval("os_name == 'p\\U0000006fsix'")).equals(True)
    env.expect.that_bool(_eval("os_name == '\\160osix'")).equals(True)
    env.expect.that_bool(_eval("os_name == 'po\\\nsix'")).equals(True)
    env.expect.that_bool(_eval("os_name == '\\u00e9'", os_name = "\303\251")).equals(True)
    env.expect.that_bool(_eval("os_name == '\\xe9'", os_name = "\303\251")).equals(True)
    env.expect.that_bool(_eval("os_name == '\303\251'", os_name = "\303\251")).equals(True)
    env.expect.that_bool(_eval("os_name == '\\U0001F600'", os_name = "\360\237\230\200")).equals(True)
    env.expect.that_str(markers.parse("os_name == 'a\\\\b'")[0][2].value).equals("a\\b")
    env.expect.that_str(markers.parse("os_name == \"a\\'b\"")[0][2].value).equals("a'b")
    env.expect.that_str(markers.parse("os_name == 'a\\tb\\n'")[0][2].value).equals("a\tb\n")

    # Unknown escapes are kept verbatim.
    env.expect.that_str(markers.parse("os_name == '\\q\\8'")[0][2].value).equals("\\q\\8")

def _test_marker_string_literals(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_string_literals_impl)

def _test_marker_grammar_impl(env, _target):
    # The empty string is accepted (always true); upstream rejects it.
    env.expect.that_collection(markers.parse("")).has_size(0)

    # Whitespace-only input is treated like "" (upstream rejects both).
    for s in [" ", "\t", "\n", " \t\r\n", "\302\240"]:
        env.expect.where(marker = s).that_collection(markers.parse(s)).has_size(0)
        env.expect.where(marker = s).that_bool(markers.evaluate(markers.parse(s), {})).equals(True)
    env.expect.that_bool(markers.evaluate([], {})).equals(True)

    # Surrounding whitespace and a single trailing newline (regex `$`).
    env.expect.that_bool(_eval(" \tos_name == 'posix' \t")).equals(True)
    env.expect.that_bool(_eval("os_name == 'posix'\n")).equals(True)

    # No whitespace is needed around quoted strings or parentheses.
    env.expect.that_bool(_eval("os_name=='nt'or(os_name=='posix')")).equals(True)
    env.expect.that_bool(_eval("'po'in os_name")).equals(True)
    env.expect.that_bool(_eval("'z' not\tin os_name")).equals(True)

    # Deep nesting and long inputs.
    env.expect.that_bool(_eval("(" * 500 + "os_name == 'posix'" + ")" * 500)).equals(True)
    env.expect.that_bool(_eval(" and ".join(["os_name == 'posix'"] * 3000))).equals(True)

    # Extra values are normalized at every nesting level (upstream only does
    # this at the top level).
    env.expect.that_bool(_eval("os_name == 'nt' or (extra == 'Foo_Bar')", extra = "foo-bar")).equals(True)
    m = markers.parse("(extra == 'Foo_Bar')")
    env.expect.that_str(m[0][0][2].value).equals("foo-bar")

def _test_marker_grammar(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_grammar_impl)

def _test_marker_to_string_impl(env, _target):
    cases = [
        ("os_name=='posix'", "os_name == \"posix\""),
        ("python_version >= '3.8' and(os_name=='nt' or sys_platform  ==  'linux')", "python_version >= \"3.8\" and (os_name == \"nt\" or sys_platform == \"linux\")"),
        ("((os_name == 'nt' or os_name == 'posix'))", "os_name == \"nt\" or os_name == \"posix\""),
        ("(os_name == 'nt') and (os_name == 'posix' or os_name == 'x')", "os_name == \"nt\" and (os_name == \"posix\" or os_name == \"x\")"),
        ("python_implementation == 'CPython' and platform.machine == 'x'", "platform_python_implementation == \"CPython\" and platform_machine == \"x\""),
        ("extra == 'Foo_Bar'", "extra == \"foo-bar\""),
        ("'Foo_Bar' == extra", "\"foo-bar\" == extra"),
        ("extra == os_name", "extra == \"os-name\""),
        ("os_name not  in 'x'", "os_name not in \"x\""),
        ("'a' in extras", "\"a\" in extras"),
        # Divergence: upstream would print `a and b or c` here.
        ("os_name == 'a' and ((os_name == 'b' or os_name == 'c'))", "os_name == \"a\" and (os_name == \"b\" or os_name == \"c\")"),
    ]
    for src, expected in cases:
        env.expect.where(marker = src).that_str(markers.to_string(markers.parse(src))).equals(expected)
    env.expect.that_str(markers.to_string([])).equals("")

def _test_marker_to_string(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_to_string_impl)

# Failure cases: (marker, environment overrides or None to only parse, expected
# message fragments).
_FAILURES = [
    # Dangling boolean operators and other grammar holes.
    ("os_name == 'nt' or", None, ["Invalid marker: Expected a marker variable or quoted string", "    os_name == 'nt' or\n                      ^"]),
    ("os_name == 'nt' and", None, ["Expected a marker variable or quoted string"]),
    ("(os_name == 'nt' or)", None, ["Expected a marker variable or quoted string"]),
    ("and os_name == 'nt'", None, ["Expected a marker variable or quoted string"]),
    ("()", None, ["Expected a marker variable or quoted string"]),
    ("os_name == 'posix'\n\n", None, ["Expected end of marker expression"]),
    ("\nos_name == 'posix'", None, ["Expected a marker variable or quoted string"]),
    ("os_name == 'posix';", None, ["Expected end of marker expression"]),
    ("os_name == 'a')", None, ["Expected end of marker expression", "    os_name == 'a')\n                  ^"]),
    ("(os_name == 'a'", None, ["Expected matching RIGHT_PARENTHESIS for LEFT_PARENTHESIS, after marker expression", "    (os_name == 'a'\n    ~~~~~~~~~~~~~~~^"]),
    ("os_name ~ 'a'", None, ["Expected marker operator, one of <=, <, !=, ==, >=, >, ~=, ===, in, not in", "    os_name ~ 'a'\n            ^"]),
    ("os_name notin 'a'", None, ["Expected marker operator"]),
    ("os_name not'a'", None, ["Expected whitespace after 'not'"]),
    ("os_name not  is 'a'", None, ["Expected 'in' after 'not'"]),
    ("os_name == 'a'andos_name == 'b'", None, ["Expected end of marker expression"]),
    ("platform.release == ''", None, ["Expected a marker variable or quoted string"]),
    ("os_namex == 'a'", None, ["Expected a marker variable or quoted string"]),
    ("os_name == 'a", None, ["Expected a marker variable or quoted string"]),
    # String literals that `ast.literal_eval` rejects.
    ("os_name == '\\'", None, ["Invalid string literal"]),
    ("os_name == 'a\\'", None, ["Invalid string literal"]),
    ("os_name == 'a\nb'", None, ["Invalid string literal"]),
    ("os_name == '\\x4'", None, ["truncated \\x escape"]),
    ("os_name == '\\u12'", None, ["truncated \\u escape"]),
    ("os_name == '\\U00110000'", None, ["illegal Unicode character"]),
    ("os_name == '\\N{LATIN SMALL LETTER A}'", None, ["\\N{...} escapes are not supported"]),
    # Undefined comparisons on non-version keys.
    ("sys_platform ~= 'linux'", {}, ["Undefined comparison", "sys_platform ~= \"linux\""]),
    ("sys_platform === 'linux'", {}, ["Undefined comparison"]),
    ("python_version ~= 'abc'", {}, ["Undefined comparison"]),
    # Missing environment keys.
    ("os_name == 'a'", {"os_name": None}, ["Undefined environment variable 'os_name' in marker `os_name == \"a\"`"]),
    ("'a' in extras", {"extras": None}, ["Undefined environment variable 'extras'"]),
    # Collections on the left-hand side.
    ("extras == 'a'", {"extras": ["a"]}, ["the left-hand side must be a string"]),
    # List-valued extra with unsupported operators.
    ("extra in 'baz,foo'", {"extra": ["foo"]}, ["Operator 'in' is not supported when 'extra' is a list of extras", "extra in \"baz,foo\""]),
    ("extra not in 'baz,foo'", {"extra": ["foo"]}, ["Operator 'not in' is not supported"]),
    ("'foo' in extra", {"extra": ["foo"]}, ["Operator 'in' is not supported"]),
    ("extra < 'z'", {"extra": ["foo"]}, ["Operator '<' is not supported"]),
    ("extra ~= 'z'", {"extra": ("foo",)}, ["Operator '~=' is not supported"]),
    ("extra >= 'z'", {"extra": []}, ["Operator '>=' is not supported"]),
    ("extra === 'foo'", {"extra": ["foo"]}, ["Operator '===' is not supported", "only == and != are"]),
    # Bad environment value types.
    ("extra == 'a'", {"extra": 1}, ["must be a string or a list/tuple of strings"]),
    ("extra == 'a'", {"extra": ["a", 1]}, ["must be a string or a list/tuple of strings"]),
    ("os_name == 'a'", {"os_name": 1}, ["the left-hand side must be a string"]),
    ("'a' in extras", {"extras": ["a", 1]}, ["must contain only strings"]),
]

def _failure_subject_impl(ctx):
    m = markers.parse(ctx.attr.marker)
    if ctx.attr.env_overrides:
        env = dict(_ENV)
        for k, v in json.decode(ctx.attr.env_overrides).items():
            if v == None:
                env.pop(k, None)
            elif k == "extra" and type(v) == "dict":
                env[k] = tuple(v["tuple"])
            else:
                env[k] = v
        markers.evaluate(m, env)
    return []

_failure_subject = rule(
    implementation = _failure_subject_impl,
    attrs = {
        "env_overrides": attr.string(),
        "marker": attr.string(mandatory = True),
    },
)

def _make_failure_test_impl(fragments):
    def _impl(env, target):
        for fragment in fragments:
            env.expect.that_target(target).failures().contains_predicate(matching.contains(fragment))

    return _impl

def _failure_tests(name):
    names = []

    # buildifier: disable=enumerate
    for i, (marker, overrides, fragments) in enumerate(_FAILURES):
        test_name = "{}_{}".format(name, i)
        env_overrides = ""
        if overrides != None:
            encoded = {}
            for k, v in overrides.items():
                encoded[k] = {"tuple": list(v)} if type(v) == "tuple" else v
            env_overrides = json.encode(encoded) if encoded else "{}"
        util.helper_target(
            _failure_subject,
            name = test_name + "_subject",
            marker = marker,
            env_overrides = env_overrides,
        )
        analysis_test(
            name = test_name,
            target = test_name + "_subject",
            expect_failure = True,
            impl = _make_failure_test_impl(fragments),
        )
        names.append(test_name)
    return names

def markers_test_suite(name):
    """Sets up the marker tests.

    Args:
        name: the name of the test suite
    """
    test_suite(
        name = name + "_standard",
        tests = [
            _test_marker_parser,
            _test_marker_evaluation,
            _test_version_marker_fallback,
            _test_string_operator_table,
            _test_list_valued_extra,
            _test_marker_aliases,
            _test_marker_string_literals,
            _test_marker_grammar,
            _test_marker_to_string,
        ],
    )

    failure_tests = _failure_tests(name + "_failure")
    native.test_suite(
        name = name,
        tests = [":" + name + "_standard"] + [":" + n for n in failure_tests],
    )
