"""Shared helpers for pypackaging Starlark analysis tests."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

def _expect_failure_impl(env, target):
    for fragment in env.ctx.attr.expected_failures:
        env.expect.that_target(target).failures().contains_predicate(matching.contains(fragment))

def expect_failure_test(name, target, expected_failures):
    """Creates an expect_failure analysis_test checking expected message fragments.

    Args:
        name: The test target name.
        target: The failing subject target.
        expected_failures: A substring or list of substrings expected in the failure message.
    """
    if type(expected_failures) == "string":
        expected_failures = [expected_failures]
    analysis_test(
        name = name,
        target = target,
        expect_failure = True,
        impl = _expect_failure_impl,
        attrs = {"expected_failures": attr.string_list(default = expected_failures)},
    )

def unit_test_suite(name, tests, extra_tests = []):
    """Registers analysis_tests from `{test_name: impl}` and groups them into a test_suite.

    Args:
        name: The test_suite target name.
        tests: Dict mapping test target names to `impl(env, target)` functions.
        extra_tests: Additional test target names (without leading `:`) to include.
    """
    target_names = []
    for test_name, impl in tests.items():
        util.helper_target(native.filegroup, name = test_name + "_subject")
        analysis_test(name = test_name, target = test_name + "_subject", impl = impl)
        target_names.append(":" + test_name)

    native.test_suite(
        name = name,
        tests = target_names + [":" + t for t in extra_tests],
    )
