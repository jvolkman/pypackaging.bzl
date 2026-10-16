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

# The complete public API of v0.3.0. Update this (and the changelog) when the
# API changes.
_PUBLIC_API = {
    "markers": ["evaluate", "parse", "to_string"],
    "requirements": ["parse", "to_string"],
    "specifiers": [
        "contains",
        "filter",
        "parse",
        "parse_set",
        "prereleases",
        "set_contains",
        "set_filter",
        "set_prereleases",
    ],
    "tags": ["get_supported", "parse_tag", "priority_map", "select_compatible", "tag_str"],
    "utils": [
        "canonicalize_name",
        "canonicalize_version",
        "is_normalized_name",
        "parse_sdist_filename",
        "parse_wheel_filename",
    ],
    "version": ["get_public_key", "parse", "to_string", "try_parse"],
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

def _test_full_public_api_impl(env, _target):
    for module_name, functions in _PUBLIC_API.items():
        module = getattr(pypackaging, module_name)
        fields = [f for f in dir(module) if f not in _STRUCT_METHODS]
        env.expect.where(module = module_name).that_collection(fields).contains_exactly(functions)

def _test_full_public_api(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_full_public_api_impl)

def _test_readme_examples_impl(env, _target):
    # Keep in sync with the usage example in README.md.
    v = pypackaging.version.parse("1.2.3")
    env.expect.that_bool(pypackaging.version.parse("1.0rc1").key < v.key).equals(True)
    env.expect.that_str(pypackaging.version.to_string(pypackaging.version.parse("1.0-RC1"))).equals("1.0rc1")
    env.expect.that_bool(pypackaging.version.try_parse("not a version") == None).equals(True)

    spec = pypackaging.specifiers.parse_set(">=1.0,<2")
    env.expect.that_bool(pypackaging.specifiers.set_contains(spec, "1.5")).equals(True)
    env.expect.that_collection(pypackaging.specifiers.set_filter(spec, ["0.9", "1.1", "1.2rc1"])).contains_exactly(["1.1"])

    marker = pypackaging.markers.parse("python_version >= '3.8' and sys_platform == 'linux'")
    env.expect.that_bool(pypackaging.markers.evaluate(marker, {"python_version": "3.12", "sys_platform": "linux"})).equals(True)

    req = pypackaging.requirements.parse("requests[socks]>=2.31; python_version >= '3.8'")
    env.expect.that_str(req.name).equals("requests")
    env.expect.that_collection(req.extras).contains_exactly(["socks"])
    env.expect.that_str(req.marker_str).equals("python_version >= '3.8'")

    supported = pypackaging.tags.get_supported(
        version = "312",
        platforms = ["manylinux_2_28_x86_64"],
        impl = "cp",
        abis = ["cp312"],
    )
    ranks = pypackaging.tags.priority_map(supported)
    best = pypackaging.tags.select_compatible(ranks, [
        (f, pypackaging.utils.parse_wheel_filename(f).tags)
        for f in ["foo-1.0-py3-none-any.whl", "foo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"]
    ])[0]
    env.expect.that_str(best).equals("foo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl")

    env.expect.that_str(pypackaging.utils.canonicalize_name("Foo_Bar")).equals("foo-bar")
    env.expect.that_str(pypackaging.utils.parse_wheel_filename("foo-1.0-py3-none-any.whl").name).equals("foo")

def _test_readme_examples(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_readme_examples_impl)

def public_api_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_consumer_contract,
            _test_full_public_api,
            _test_readme_examples,
            _test_top_level_modules,
        ],
    )
