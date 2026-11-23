"""Tests for markers.bzl."""

load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/markers:markers.bzl", "markers")
load(":test_helpers.bzl", "expect_failure_test", "unit_test_suite")

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
    env.expect.that_bool(_eval("python_version === 'v3.12'", python_version = "v3.12")).equals(True)
    env.expect.that_bool(_eval("python_version === '3.12'", python_version = "v3.12")).equals(False)
    env.expect.that_bool(_eval("python_version == '3.12'", python_version = "v3.12")).equals(True)

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

    # An empty list/tuple behaves like "" (no extra selected, matching packaging#1438).
    env.expect.that_bool(_eval("extra == 'baz'", extra = [])).equals(False)
    env.expect.that_bool(_eval("extra == ''", extra = [])).equals(True)
    env.expect.that_bool(_eval("extra == ''", extra = ())).equals(True)
    env.expect.that_bool(_eval("extra != 'baz'", extra = [])).equals(True)
    env.expect.that_bool(_eval("extra != ''", extra = [])).equals(False)
    env.expect.that_bool(_eval("extra >= 'z'", extra = [])).equals(False)

    # Scalar `extra` keeps upstream semantics (missing / None / "" all mean "").
    env.expect.that_bool(_eval("extra == ''")).equals(True)
    env.expect.that_bool(_eval("extra == ''", extra = None)).equals(True)
    env.expect.that_bool(_eval("extra == 'foo-bar'", extra = "Foo.Bar")).equals(True)
    env.expect.that_bool(_eval("extra in 'foo-bar'", extra = "Foo.Bar")).equals(True)
    env.expect.that_bool(_eval("extra < 'z'", extra = "Foo.Bar")).equals(False)
    env.expect.that_bool(_eval("extra <= 'foo-bar'", extra = "Foo.Bar")).equals(True)

def _test_marker_aliases_impl(env, _target):
    # `python_implementation` is an alias for `platform_python_implementation`.
    env.expect.that_bool(_eval("python_implementation == 'CPython'")).equals(True)
    env.expect.that_bool(_eval("platform.python_implementation == 'CPython'")).equals(True)
    m = markers.parse("python_implementation == 'CPython'")
    env.expect.that_str(m[0][0].value).equals("platform_python_implementation")

    # Dotted names map to the underscore form.
    env.expect.that_bool(_eval("os.name == 'posix' and sys.platform == 'linux'")).equals(True)
    env.expect.that_bool(_eval("platform.machine == 'x86_64' and platform.version == ''")).equals(True)

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

def _test_marker_grammar_impl(env, _target):
    # The empty string is accepted (always true); upstream rejects it.
    env.expect.that_collection(markers.parse("")).has_size(0)

    # Whitespace-only input is treated like "" (upstream rejects both).
    for s in [" ", "\t", "\n", " \t\r\n", "\302\240"]:
        env.expect.where(marker = s).that_collection(markers.parse(s)).has_size(0)
        env.expect.where(marker = s).that_bool(markers.evaluate(markers.parse(s), {})).equals(True)
    env.expect.that_bool(markers.evaluate([], {})).equals(True)

    # Surrounding whitespace (spaces/tabs).
    env.expect.that_bool(_eval(" \tos_name == 'posix' \t")).equals(True)

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
        ("'S_P__A_M' in extras", "\"s-p-a-m\" in extras"),
        ("'Foo_Bar' not in dependency_groups", "\"foo-bar\" not in dependency_groups"),
        # Uses single quotes when the value contains double quotes (packaging 26.3).
        ("os_name == 'a\"b'", "os_name == 'a\"b'"),
        ("os_name == 'a' and ((os_name == 'b' or os_name == 'c'))", "os_name == \"a\" and (os_name == \"b\" or os_name == \"c\")"),
    ]
    for src, expected in cases:
        env.expect.where(marker = src).that_str(markers.to_string(markers.parse(src))).equals(expected)
    env.expect.that_str(markers.to_string([])).equals("")

def _partial(marker, environment):
    result = markers.evaluate_partial(markers.parse(marker), environment)
    if type(result) == "bool":
        return result
    return markers.to_string(result)

def _test_marker_evaluate_partial_impl(env, _target):
    # The same cases as in rules_python, where `True` is an empty string.
    for marker, want in [
        ("os_name == 'osx' and extra == 'bar'", False),
        ("os_name == 'osx' and extra == 'foo'", 'os_name == "osx"'),
        ("platform_system == 'aarch64' and os_name == 'osx' and extra == 'foo'", 'platform_system == "aarch64" and os_name == "osx"'),
        ("platform_system == 'aarch64' and extra == 'foo' and os_name == 'osx'", 'platform_system == "aarch64" and os_name == "osx"'),
        ("os_name == 'osx' or extra == 'bar'", 'os_name == "osx"'),
        ("os_name == 'osx' or extra == 'foo'", True),
        ("extra == 'bar' or os_name == 'osx'", 'os_name == "osx"'),
        ("extra == 'foo' or os_name == 'osx'", True),
        ("os_name == 'win' or extra == 'bar' or os_name == 'osx'", 'os_name == "win" or os_name == "osx"'),
        ("os_name == 'win' or extra == 'foo' or os_name == 'osx'", True),
        # Everything is known.
        ("", True),
        ("extra == 'foo'", True),
        ("extra == 'bar'", False),
        ("extra == 'bar' or (extra == 'foo' and extra != 'foo')", False),
        # The parentheses are only kept if they are needed.
        ("(os_name == 'a')", 'os_name == "a"'),
        ("(os_name == 'a' or os_name == 'b') and extra == 'foo'", 'os_name == "a" or os_name == "b"'),
        ("(os_name == 'a' or os_name == 'b') and sys_platform == 'x' and extra == 'foo'", '(os_name == "a" or os_name == "b") and sys_platform == "x"'),
        ("(os_name == 'a' and extra == 'foo') or sys_platform == 'x'", 'os_name == "a" or sys_platform == "x"'),
        ("(os_name == 'a' and sys_platform == 'y' and extra == 'foo') or sys_platform == 'x'", 'os_name == "a" and sys_platform == "y" or sys_platform == "x"'),
        ("(os_name == 'a' or extra == 'bar') and sys_platform == 'x'", 'os_name == "a" and sys_platform == "x"'),
        ("(os_name == 'a' or extra == 'foo') and sys_platform == 'x'", 'sys_platform == "x"'),
        ("(os_name == 'a' and extra == 'bar') or sys_platform == 'x'", 'sys_platform == "x"'),
        ("((os_name == 'a' or os_name == 'b') and extra == 'foo') or sys_platform == 'x'", 'os_name == "a" or os_name == "b" or sys_platform == "x"'),
        ("os_name == 'a' and (sys_platform == 'x' or (extra == 'foo' and python_version >= '3.8'))", 'os_name == "a" and (sys_platform == "x" or python_version >= "3.8")'),
        ("os_name == 'a' and ((sys_platform == 'x' or sys_platform == 'y') and extra == 'foo')", 'os_name == "a" and (sys_platform == "x" or sys_platform == "y")'),
        ("os_name == 'a' and (sys_platform == 'x' and extra == 'foo' and python_version >= '3.8')", 'os_name == "a" and sys_platform == "x" and python_version >= "3.8"'),
        ("os_name == 'a' or (sys_platform == 'x' and (extra == 'foo' and python_version >= '3.8'))", 'os_name == "a" or sys_platform == "x" and python_version >= "3.8"'),
        ("os_name == 'a' and (extra == 'bar' or (extra == 'foo' and extra != 'foo'))", False),
        ("os_name == 'a' or (extra == 'bar' or (extra == 'foo' and extra == 'foo'))", True),
    ]:
        env.expect.where(marker = marker).that_str(str(_partial(marker, {"extra": "foo"}))).equals(str(want))

    # The values are handled like in `evaluate`.
    env.expect.that_str(str(_partial("extra == 'Foo.Bar' and os_name == 'a'", {"extra": "foo_bar"}))).equals('os_name == "a"')
    env.expect.that_str(str(_partial("extra == 'bar' and os_name == 'a'", {"extra": ["foo", "bar"]}))).equals('os_name == "a"')
    env.expect.that_str(str(_partial("extra == 'baz' and os_name == 'a'", {"extra": ["foo", "bar"]}))).equals("False")
    env.expect.that_str(str(_partial("extra == '' or os_name == 'a'", {"extra": None}))).equals("True")
    env.expect.that_str(str(_partial("'foo' in extras and os_name == 'a'", {"extras": ["Foo"]}))).equals('os_name == "a"')

    # Nothing is known, `extra` does not have a default.
    for marker, want in [
        ("extra == 'Foo'", 'extra == "foo"'),
        ("os_name=='a' and(extra=='foo' or sys.platform=='x')", 'os_name == "a" and (extra == "foo" or sys_platform == "x")'),
    ]:
        env.expect.where(marker = marker).that_str(str(_partial(marker, {}))).equals(want)

    # The platform is known and the extra is not.
    for marker, want in [
        ("sys_platform == 'linux' and extra == 'x'", 'extra == "x"'),
        ("sys_platform == 'win32' and extra == 'x'", False),
        ("python_version >= '3.8' or extra == 'x'", True),
        ("python_full_version < '3.8' or extra == 'x'", 'extra == "x"'),
        ("sys_platform == 'linux' and python_version >= '3.8'", True),
    ]:
        env.expect.where(marker = marker).that_str(str(_partial(marker, _ENV))).equals(str(want))

    # What is left is a marker that can be evaluated or evaluated partially.
    left = markers.evaluate_partial(
        markers.parse("extra == 'foo' and (os_name == 'a' or sys_platform == 'x') and python_version >= '3.8'"),
        {"extra": "foo"},
    )
    env.expect.that_str(markers.to_string(left)).equals('(os_name == "a" or sys_platform == "x") and python_version >= "3.8"')
    env.expect.that_bool(markers.evaluate(left, {"os_name": "b", "python_version": "3.9", "sys_platform": "x"})).equals(True)
    env.expect.that_bool(markers.evaluate(left, {"os_name": "b", "python_version": "3.9", "sys_platform": "y"})).equals(False)
    left = markers.evaluate_partial(left, {"python_version": "3.9"})
    env.expect.that_str(markers.to_string(left)).equals('os_name == "a" or sys_platform == "x"')
    env.expect.that_bool(markers.evaluate_partial(left, {"sys_platform": "x"})).equals(True)

    # The input is not changed.
    parsed = markers.parse("(os_name == 'a' or extra == 'foo') and sys_platform == 'x'")
    markers.evaluate_partial(parsed, {"extra": "bar"})
    env.expect.that_str(markers.to_string(parsed)).equals('(os_name == "a" or extra == "foo") and sys_platform == "x"')

def _test_format_full_version_impl(env, _target):
    # Struct inputs (like rules_python PyRuntimeInfo.interpreter_version_info).
    env.expect.that_str(
        markers.format_full_version(struct(major = 3, minor = 14, micro = 2, releaselevel = "final", serial = 0)),
    ).equals("3.14.2")
    env.expect.that_str(
        markers.format_full_version(struct(major = 3, minor = 14, micro = 0, releaselevel = "candidate", serial = 1)),
    ).equals("3.14.0rc1")
    env.expect.that_str(
        markers.format_full_version(struct(major = 3, minor = 15, micro = 0, releaselevel = "alpha", serial = 0)),
    ).equals("3.15.0a0")
    env.expect.that_str(
        markers.format_full_version(struct(major = 3, minor = 14, micro = 0, releaselevel = "beta", serial = 2)),
    ).equals("3.14.0b2")
    env.expect.that_str(
        markers.format_full_version(struct(major = 3, minor = 12, micro = None, releaselevel = None, serial = None)),
    ).equals("3.12.0")
    env.expect.that_str(
        markers.format_full_version(struct(major = 3, minor = 12, micro = 1, releaselevel = "", serial = 5)),
    ).equals("3.12.1")
    env.expect.that_str(
        markers.format_full_version(struct(major = 3, minor = 14, micro = 0, releaselevel = "final", serial = 99)),
    ).equals("3.14.0")
    env.expect.that_str(
        markers.format_full_version(struct(major = 3, minor = 14, micro = 0, releaselevel = "candidate", serial = None)),
    ).equals("3.14.0rc0")

    # Dict inputs and string components.
    env.expect.that_str(
        markers.format_full_version({"major": 3, "minor": 13}),
    ).equals("3.13.0")
    env.expect.that_str(
        markers.format_full_version({"major": "3", "minor": "14", "micro": "0", "releaselevel": "candidate", "serial": "2"}),
    ).equals("3.14.0rc2")
    env.expect.that_str(
        markers.format_full_version({"major": 0, "minor": 0, "micro": 0}),
    ).equals("0.0.0")

def _test_marker_variables_impl(env, _target):
    cases = [
        ("", []),
        ("os_name == 'posix'", ["os_name"]),
        ("'posix' == os_name", ["os_name"]),
        ("python_version >= '3.8' and sys_platform == 'linux'", ["python_version", "sys_platform"]),
        ("sys_platform == 'linux' or sys_platform == 'darwin'", ["sys_platform"]),
        # Dotted and legacy aliases are returned in canonical underscore form.
        ("os.name == 'posix' and sys.platform == 'linux' and python_implementation == 'CPython'", [
            "os_name",
            "platform_python_implementation",
            "sys_platform",
        ]),
        # String literals containing variable names are ignored.
        ("sys_platform == 'extra' and platform_version == 'python_version'", [
            "platform_version",
            "sys_platform",
        ]),
        ("'extra' in extras", ["extras"]),
        ("'dev' in dependency_groups and extra == 'foo'", ["dependency_groups", "extra"]),
        # Comparing two variables collects both (except `extra == os_name`,
        # where parse_marker converts the rhs to a normalized string literal).
        ("os_name == sys_platform", ["os_name", "sys_platform"]),
        ("extra == os_name", ["extra"]),
        # String-to-string comparisons have no variables.
        ("'a' == 'b'", []),
        # Nested groups.
        ("((python_full_version >= '3.12' and (platform_machine == 'aarch64' or extra == 'gpu')) or os_name == 'nt')", [
            "extra",
            "os_name",
            "platform_machine",
            "python_full_version",
        ]),
    ]
    for src, expected in cases:
        env.expect.where(marker = src).that_collection(
            markers.variables(markers.parse(src)),
        ).contains_exactly(expected).in_order()

    # Deep nesting is handled iteratively.
    deep = "(" * 500 + "extra == 'foo'" + ")" * 500
    env.expect.that_collection(markers.variables(markers.parse(deep))).contains_exactly(["extra"])

# Failure cases: (marker, environment overrides or None to only parse, expected
# message fragments).
_FAILURES = [
    # The caret position counts code points, not UTF-8 bytes.
    ("os_name == '\303\251' and", None, ["Invalid marker: Expected a marker variable or quoted string\n    os_name == '\303\251' and\n" + " " * 22 + "^"]),
    # Dangling boolean operators and other grammar holes.
    ("os_name == 'nt' or", None, ["Invalid marker: Expected a marker variable or quoted string", "    os_name == 'nt' or\n                      ^"]),
    ("os_name == 'nt' and", None, ["Expected a marker variable or quoted string"]),
    ("(os_name == 'nt' or)", None, ["Expected a marker variable or quoted string"]),
    ("and os_name == 'nt'", None, ["Expected a marker variable or quoted string"]),
    ("()", None, ["Expected a marker variable or quoted string"]),
    ("os_name == 'posix'\n", None, ["Expected end of marker expression"]),
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
    # Collection-valued extra with unsupported operators.
    ("extra in 'baz,foo'", {"extra": ["foo"]}, ["Operator 'in' is not supported when 'extra' is a collection of extras", "extra in \"baz,foo\""]),
    ("extra not in 'baz,foo'", {"extra": ["foo"]}, ["Operator 'not in' is not supported"]),
    ("'foo' in extra", {"extra": ["foo"]}, ["Operator 'in' is not supported"]),
    ("extra < 'z'", {"extra": ["foo"]}, ["Operator '<' is not supported"]),
    ("extra ~= 'z'", {"extra": ("foo",)}, ["Operator '~=' is not supported"]),
    ("extra >= 'z'", {"extra": ["foo"]}, ["Operator '>=' is not supported"]),
    ("extra === 'foo'", {"extra": ["foo"]}, ["Operator '===' is not supported", "only == and != are"]),
    # Bad environment value types.
    ("extra == 'a'", {"extra": 1}, ["must be a string or a list/tuple/set of strings"]),
    ("extra == 'a'", {"extra": ["a", 1]}, ["must be a string or a list/tuple/set of strings"]),
    ("os_name == 'a'", {"os_name": 1}, ["the left-hand side must be a string"]),
    ("'a' in extras", {"extras": ["a", 1]}, ["must contain only strings"]),
    # Serialization failure when a marker string contains both quote characters.
    ("os_name == 'a\\x27b\"c'", "to_string", ["Cannot serialize marker value containing both quote characters"]),
]

def _failure_subject_impl(ctx):
    m = markers.parse(ctx.attr.marker)
    if ctx.attr.to_string:
        markers.to_string(m)
    elif ctx.attr.env_overrides:
        env = dict(_ENV)
        for k, v in json.decode(ctx.attr.env_overrides).items():
            if v == None:
                env.pop(k, None)
            elif k == "extra" and type(v) == "dict":
                env[k] = tuple(v["tuple"])
            else:
                env[k] = v
        if ctx.attr.partial:
            markers.evaluate_partial(m, env)
        else:
            markers.evaluate(m, env)
    return []

_failure_subject = rule(
    implementation = _failure_subject_impl,
    attrs = {
        "env_overrides": attr.string(),
        "marker": attr.string(mandatory = True),
        "partial": attr.bool(),
        "to_string": attr.bool(),
    },
)

def _failure_tests(name):
    names = []

    # buildifier: disable=enumerate
    for i, (marker, overrides, fragments) in enumerate(_FAILURES):
        test_name = "{}_{}".format(name, i)
        env_overrides = ""
        to_string = overrides == "to_string"
        if overrides != None and not to_string:
            encoded = {}
            for k, v in overrides.items():
                encoded[k] = {"tuple": list(v)} if type(v) == "tuple" else v
            env_overrides = json.encode(encoded) if encoded else "{}"
        util.helper_target(
            _failure_subject,
            name = test_name + "_subject",
            marker = marker,
            env_overrides = env_overrides,
            to_string = to_string,
        )
        expect_failure_test(test_name, test_name + "_subject", fragments)
        names.append(test_name)

    # The known variables are evaluated like in `evaluate`.
    test_name = name + "_partial"
    util.helper_target(
        _failure_subject,
        name = test_name + "_subject",
        marker = "os_name ~= 'a' or extra == 'foo'",
        env_overrides = "{}",
        partial = True,
    )
    expect_failure_test(test_name, test_name + "_subject", ["Undefined comparison"])
    names.append(test_name)

    for i, (info_json, fragments) in enumerate([
        (json.encode({"major": 3}), ["version_info must provide 'major' and 'minor'"]),
        (json.encode({"minor": 14}), ["version_info must provide 'major' and 'minor'"]),
        (json.encode({"major": 3, "minor": 14, "micro": 0, "releaselevel": "dev", "serial": 0}), ["Invalid releaselevel: \"dev\""]),
    ]):
        test_name = "{}_format_full_version_{}".format(name, i)
        util.helper_target(
            _format_full_version_failure_subject,
            name = test_name + "_subject",
            version_info_json = info_json,
        )
        expect_failure_test(test_name, test_name + "_subject", fragments)
        names.append(test_name)
    return names

def _format_full_version_failure_subject_impl(ctx):
    markers.format_full_version(json.decode(ctx.attr.version_info_json))
    return []

_format_full_version_failure_subject = rule(
    implementation = _format_full_version_failure_subject_impl,
    attrs = {
        "version_info_json": attr.string(mandatory = True),
    },
)

def markers_test_suite(name):
    """Sets up the marker tests.

    Args:
        name: the name of the test suite
    """
    failure_tests = _failure_tests(name + "_failure")
    unit_test_suite(
        name = name,
        tests = {
            "test_marker_parser": _test_marker_parser_impl,
            "test_marker_evaluation": _test_marker_evaluation_impl,
            "test_version_marker_fallback": _test_version_marker_fallback_impl,
            "test_string_operator_table": _test_string_operator_table_impl,
            "test_list_valued_extra": _test_list_valued_extra_impl,
            "test_marker_aliases": _test_marker_aliases_impl,
            "test_marker_string_literals": _test_marker_string_literals_impl,
            "test_marker_grammar": _test_marker_grammar_impl,
            "test_marker_to_string": _test_marker_to_string_impl,
            "test_marker_evaluate_partial": _test_marker_evaluate_partial_impl,
            "test_format_full_version": _test_format_full_version_impl,
            "test_marker_variables": _test_marker_variables_impl,
        },
        extra_tests = failure_tests,
    )
