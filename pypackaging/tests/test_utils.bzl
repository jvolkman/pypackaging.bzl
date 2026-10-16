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

def _failure_tests(name, fn, cases):
    """Creates one expect_failure test per (arg, expected message) case."""
    names = []

    # buildifier: disable=enumerate
    for i, (arg, expected) in enumerate(cases):
        test_name = "{}_{}".format(name, i)
        util.helper_target(_failing_subject, name = test_name + "_subject", fn = fn, arg = arg)
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

def _test_parse_sdist_filename_impl(env, _target):
    res = utils.parse_sdist_filename("foo-1.0.tar.gz")
    env.expect.that_str(res.name).equals("foo")
    env.expect.that_str(res.version.version_str).equals("1.0")

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

    test_suite(
        name = name + "_standard",
        tests = [
            _test_canonicalize_name,
            _test_is_normalized_name,
            _test_canonicalize_version,
            _test_parse_wheel_filename,
            _test_parse_sdist_filename,
            _test_parse_wheel_filename_tags,
        ],
    )

    native.test_suite(
        name = name,
        tests = [":" + name + "_standard"] + [":" + n for n in failure_tests],
    )
