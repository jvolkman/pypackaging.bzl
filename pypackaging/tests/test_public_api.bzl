"""Tests for the public entrypoint //:pypackaging.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//:pypackaging.bzl", "pypackaging")

# Functions that downstream consumers (e.g. rules_pycross) rely on. Removing or
# renaming any of these is a breaking change.
_CONSUMER_CONTRACT = {
    "markers": ["evaluate", "parse"],
    "requirements": ["parse"],
    "specifiers": ["parse_set", "set_contains"],
    "tags": ["get_supported", "parse_tag"],
    "utils": ["canonicalize_name", "parse_sdist_filename", "parse_wheel_filename"],
    "version": ["parse"],
}

# Bazel 7 structs also expose the legacy to_json()/to_proto() methods.
_STRUCT_METHODS = ["to_json", "to_proto"]

def _test_top_level_modules_impl(env, _target):
    fields = [f for f in dir(pypackaging) if f not in _STRUCT_METHODS]
    env.expect.that_collection(fields).contains_exactly(
        sorted(_CONSUMER_CONTRACT.keys()),
    )

def _test_top_level_modules(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_top_level_modules_impl)

def _test_consumer_contract_impl(env, _target):
    for module_name, functions in _CONSUMER_CONTRACT.items():
        module = getattr(pypackaging, module_name)
        env.expect.where(module = module_name).that_collection(dir(module)).contains_at_least(functions)

def _test_consumer_contract(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_consumer_contract_impl)

def public_api_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_consumer_contract,
            _test_top_level_modules,
        ],
    )
