"""Tests for utils.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/utils:utils.bzl", "utils")

def _failing_subject_impl(ctx):
    arg = ctx.attr.arg
    if ctx.attr.fn == "canonicalize_name_validate":
        utils.canonicalize_name(arg, validate = True)
    elif ctx.attr.fn == "parse_wheel_filename":
        utils.parse_wheel_filename(arg, validate_order = ctx.attr.validate_order)
    elif ctx.attr.fn == "parse_sdist_filename":
        utils.parse_sdist_filename(arg)
    else:
        fail("unknown fn: " + ctx.attr.fn)
    return []

_failing_subject = rule(
    implementation = _failing_subject_impl,
    attrs = {
        "arg": attr.string(),
        "fn": attr.string(),
        "validate_order": attr.bool(),
    },
)

def _failure_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(matching.contains(env.ctx.attr.expected_failure))

def _failure_tests(name, fn, cases, validate_order = False):
    """Creates one expect_failure test per (arg, expected message) case."""
    names = []

    # buildifier: disable=enumerate
    for i, (arg, expected) in enumerate(cases):
        test_name = "{}_{}".format(name, i)
        util.helper_target(_failing_subject, name = test_name + "_subject", fn = fn, arg = arg, validate_order = validate_order)
        analysis_test(
            name = test_name,
            target = test_name + "_subject",
            expect_failure = True,
            impl = _failure_test_impl,
            attrs = {"expected_failure": attr.string(default = expected)},
        )
        names.append(test_name)
    return names

def _test_canonicalize_name_impl(env, _target):
    cases = {
        "Django": "django",
        "oslo.concurrency": "oslo-concurrency",
        "requests": "requests",
        "Foo__Bar": "foo-bar",
        "FOO.Bar_baz": "foo-bar-baz",
        "foo-_.-bar": "foo-bar",
        "a..b": "a-b",
        "-foo-": "-foo-",
        "": "",
        "_": "-",
        "ruamel.yaml.clib": "ruamel-yaml-clib",
    }
    for name, expected in cases.items():
        env.expect.where(name = name).that_str(utils.canonicalize_name(name)).equals(expected)

    # Valid names pass validation.
    for name in ["Django", "A", "1", "a-b_c.d", "zope.interface", "foo--bar"]:
        env.expect.where(name = name).that_str(utils.canonicalize_name(name, validate = True)).equals(utils.canonicalize_name(name))

    # Starlark's lower() is ASCII-only: non-ASCII letters are kept as-is.
    env.expect.that_str(utils.canonicalize_name("Café_Bar")).equals("café-bar")

def _test_canonicalize_name(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_canonicalize_name_impl)

def _test_is_normalized_name_impl(env, _target):
    for name in ["foo", "foo-bar", "a", "1", "a1-b2", "requests"]:
        env.expect.where(name = name).that_bool(utils.is_normalized_name(name)).equals(True)
    for name in ["", "Django", "foo--bar", "-foo", "foo-", "foo_bar", "foo.bar", "ab-", "foo bar", "café"]:
        env.expect.where(name = name).that_bool(utils.is_normalized_name(name)).equals(False)

def _test_is_normalized_name(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_is_normalized_name_impl)

def _test_canonicalize_version_impl(env, _target):
    env.expect.that_str(utils.canonicalize_version("1.0.0")).equals("1")
    env.expect.that_str(utils.canonicalize_version("1.0.0", strip_trailing_zero = False)).equals("1.0.0")
    env.expect.that_str(utils.canonicalize_version("1.4.0.0.0")).equals("1.4")

    # (input, strip_trailing_zero=True, strip_trailing_zero=False), from packaging 26.2.
    cases = [
        ("1.0.1", "1.0.1", "1.0.1"),
        ("0.0.0", "0", "0.0.0"),
        ("1!0.0", "1!0", "1!0.0"),
        ("v1.0", "1", "1.0"),
        ("1.0-1", "1.post1", "1.0.post1"),
        ("1.0c1", "1rc1", "1.0rc1"),
        ("1.0.0.0.post1.dev0", "1.post1.dev0", "1.0.0.0.post1.dev0"),
        ("1.0+UBUNTU.1", "1+ubuntu.1", "1.0+ubuntu.1"),
        ("1.0+ubuntu-1", "1+ubuntu.1", "1.0+ubuntu.1"),
        ("2.0.0-rc.1", "2rc1", "2.0.0rc1"),
        ("01!1.0", "1!1", "1!1.0"),
        ("10.0.00", "10", "10.0.0"),
        ("1.0.0b0.post0.dev0+x", "1b0.post0.dev0+x", "1.0.0b0.post0.dev0+x"),
        # Leading and trailing whitespace is ignored.
        ("  1.0  ", "1", "1.0"),
        ("\t1.0.0\n", "1", "1.0.0"),
        ("\302\2401.0\342\200\203", "1", "1.0"),  # U+00A0, U+2003
        # Invalid versions are returned unchanged.
        ("invalid", "invalid", "invalid"),
        ("foo bar baz", "foo bar baz", "foo bar baz"),
        ("1.0.", "1.0.", "1.0."),
        ("  1.0-foo ", "  1.0-foo ", "  1.0-foo "),
        ("", "", ""),
    ]
    for version_str, stripped, unstripped in cases:
        env.expect.where(version = version_str).that_str(utils.canonicalize_version(version_str)).equals(stripped)
        env.expect.where(version = version_str).that_str(utils.canonicalize_version(version_str, strip_trailing_zero = False)).equals(unstripped)

def _test_canonicalize_version(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_canonicalize_version_impl)

def _test_parse_wheel_filename_impl(env, _target):
    res = utils.parse_wheel_filename("foo-1.0-py3-none-any.whl")
    env.expect.that_str(res.name).equals("foo")
    env.expect.that_str(res.version.version_str).equals("1.0")
    env.expect.that_collection(res.build).contains_exactly([])
    env.expect.that_int(len(res.tags)).equals(1)

    tag = res.tags[0]
    env.expect.that_str(tag.interpreter).equals("py3")
    env.expect.that_str(tag.abi).equals("none")
    env.expect.that_str(tag.platform).equals("any")

def _test_parse_wheel_filename(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wheel_filename_impl)

def _test_parse_wheel_filename_names_impl(env, _target):
    # (filename, expected name), from packaging 26.2.
    cases = [
        ("Foo_Bar-1.0-py3-none-any.whl", "foo-bar"),
        ("foo.bar-1.0-py3-none-any.whl", "foo-bar"),
        ("foo_-1.0-py3-none-any.whl", "foo-"),
        ("_foo-1.0-py3-none-any.whl", "-foo"),
        ("foo..bar-1.0-py3-none-any.whl", "foo-bar"),
        ("FOO-1.0-cp311-cp311-MACOSX_10_9_X86_64.whl", "foo"),
        # Non-ASCII names are accepted like packaging.
        ("café-1.0-py3-none-any.whl", "café"),
        ("Ünïcode-1.0-py3-none-any.whl", "Ünïcode"),
    ]
    for filename, expected in cases:
        env.expect.where(filename = filename).that_str(utils.parse_wheel_filename(filename).name).equals(expected)

def _test_parse_wheel_filename_names(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wheel_filename_names_impl)

def _test_parse_wheel_filename_build_impl(env, _target):
    cases = [
        ("foo-1.0-1-py3-none-any.whl", (1, "")),
        ("foo-1.0-1abc-py3-none-any.whl", (1, "abc")),
        ("foo-1.0-01-py3-none-any.whl", (1, "")),
        ("foo-1.0-007_x-py3-none-any.whl", (7, "_x")),
        ("foo-1.0-99999999999999999999-py3-none-any.whl", (99999999999999999999, "")),
        ("foo-1.0-py3-none-any.whl", ()),
    ]
    for filename, expected in cases:
        env.expect.where(filename = filename).that_bool(utils.parse_wheel_filename(filename).build == expected).equals(True)

def _test_parse_wheel_filename_build(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wheel_filename_build_impl)

def _test_parse_wheel_filename_version_impl(env, _target):
    # version.version_str is the raw filename text; canonicalize_version gives
    # packaging's str(version).
    cases = [
        ("foo-1.0.0.RC1-py3-none-any.whl", "1.0.0.RC1", "1.0.0rc1"),
        ("foo-01.0_post1-py3-none-any.whl", "01.0_post1", "1.0.post1"),
        ("foo-1!2.0-py3-none-any.whl", "1!2.0", "1!2.0"),
        ("foo-v1.0+Local-py3-none-any.whl", "v1.0+Local", "1.0+local"),
    ]
    for filename, raw, normalized in cases:
        v = utils.parse_wheel_filename(filename).version
        env.expect.where(filename = filename).that_str(v.version_str).equals(raw)
        env.expect.where(filename = filename).that_str(utils.canonicalize_version(v, strip_trailing_zero = False)).equals(normalized)

    v = utils.parse_sdist_filename("Foo.Bar-1.0.0.RC1.tar.gz").version
    env.expect.that_str(v.version_str).equals("1.0.0.RC1")
    env.expect.that_str(utils.canonicalize_version(v, strip_trailing_zero = False)).equals("1.0.0rc1")

    # validate_order accepts sorted compressed tag sets.
    res = utils.parse_wheel_filename("foo-1.0-py2.py3-none-any.whl", validate_order = True)
    env.expect.that_int(len(res.tags)).equals(2)

def _test_parse_wheel_filename_version(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wheel_filename_version_impl)

def _test_parse_sdist_filename_impl(env, _target):
    res = utils.parse_sdist_filename("foo-1.0.tar.gz")
    env.expect.that_str(res.name).equals("foo")
    env.expect.that_str(res.version.version_str).equals("1.0")

    # (filename, name, normalized version), from packaging 26.2.
    cases = [
        ("Foo_Bar-1.0.zip", "foo-bar", "1.0"),
        ("foo-bar-1.0.tar.gz", "foo-bar", "1.0"),
        ("foo-1.0-1.tar.gz", "foo-1-0", "1"),
        ("-1.0.tar.gz", "", "1.0"),
        ("foo-1.0+local.tar.gz", "foo", "1.0+local"),
        ("foo-v1.0.zip", "foo", "1.0"),
        ("café-1.0.tar.gz", "café", "1.0"),
    ]
    for filename, name, version in cases:
        res = utils.parse_sdist_filename(filename)
        env.expect.where(filename = filename).that_str(res.name).equals(name)
        env.expect.where(filename = filename).that_str(utils.canonicalize_version(res.version, strip_trailing_zero = False)).equals(version)

def _test_parse_sdist_filename(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_sdist_filename_impl)

def _test_parse_wheel_filename_tags_impl(env, _target):
    # Empty tag components are accepted like packaging.
    res = utils.parse_wheel_filename("foo-1.0-py3--any.whl")
    env.expect.that_collection(["{}-{}-{}".format(t.interpreter, t.abi, t.platform) for t in res.tags]).contains_exactly(["py3--any"])

    # Repeated compressed components don't produce duplicate tags.
    res = utils.parse_wheel_filename("foo-1.0-py3-none-any.any.whl")
    env.expect.that_int(len(res.tags)).equals(1)

def _test_parse_wheel_filename_tags(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wheel_filename_tags_impl)

_INVALID_WHEEL_FILENAMES = [
    ("foo-1.0-py3-none-any.zip", "extension must be '.whl'"),
    ("foo-1.0-py3-none-any.WHL", "extension must be '.whl'"),
    ("foo-py3-none-any.whl", "wrong number of parts"),
    ("foo-1.0-1-2-py3-none-any.whl", "wrong number of parts"),
    ("foo__bar-1.0-py3-none-any.whl", "Invalid project name"),
    ("foo bar-1.0-py3-none-any.whl", "Invalid project name"),
    ("foo+bar-1.0-py3-none-any.whl", "Invalid project name"),
    ("foo\001-1.0-py3-none-any.whl", "Invalid project name"),
    ("foo-1.0--py3-none-any.whl", "Invalid build number"),
    ("foo-1.0-abc-py3-none-any.whl", "Invalid build number"),
    ("foo-notaversion-py3-none-any.whl", "Invalid wheel filename (invalid version)"),
    ("foo-1.0.-py3-none-any.whl", "Invalid wheel filename (invalid version)"),
]

_INVALID_SDIST_FILENAMES = [
    ("foo-1.0.tgz", "extension must be '.tar.gz' or '.zip'"),
    ("foo-1.0.TAR.GZ", "extension must be '.tar.gz' or '.zip'"),
    ("foo.tar.gz", "Invalid sdist filename"),
    ("foo-bar.tar.gz", "Invalid sdist filename (invalid version)"),
    ("foo-.tar.gz", "Invalid sdist filename (invalid version)"),
]

_INVALID_NAMES = [
    ("-foo-", "name is invalid"),
    ("foo bar!", "name is invalid"),
    ("", "name is invalid"),
    ("foo-", "name is invalid"),
    ("_", "name is invalid"),
    ("café", "name is invalid"),
]

def utils_test_suite(name):
    """Sets up the utils tests.

    Args:
        name: the name of the test suite
    """
    failure_tests = []
    failure_tests += _failure_tests(name + "_canonicalize_name_invalid", "canonicalize_name_validate", _INVALID_NAMES)
    failure_tests += _failure_tests(name + "_parse_wheel_filename_invalid", "parse_wheel_filename", _INVALID_WHEEL_FILENAMES)
    failure_tests += _failure_tests(name + "_parse_sdist_filename_invalid", "parse_sdist_filename", _INVALID_SDIST_FILENAMES)
    failure_tests += _failure_tests(
        name + "_parse_wheel_filename_unsorted",
        "parse_wheel_filename",
        [("foo-1.0-py3.py2-none-any.whl", "must be in sorted order per PEP 425")],
        validate_order = True,
    )

    test_suite(
        name = name + "_standard",
        tests = [
            _test_canonicalize_name,
            _test_is_normalized_name,
            _test_canonicalize_version,
            _test_parse_wheel_filename,
            _test_parse_sdist_filename,
            _test_parse_wheel_filename_tags,
            _test_parse_wheel_filename_names,
            _test_parse_wheel_filename_build,
            _test_parse_wheel_filename_version,
        ],
    )

    native.test_suite(
        name = name,
        tests = [":" + name + "_standard"] + [":" + n for n in failure_tests],
    )
