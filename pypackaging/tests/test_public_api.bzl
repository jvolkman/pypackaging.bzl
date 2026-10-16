"""Tests for the public entrypoint //:pypackaging.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//:pypackaging.bzl", "pypackaging")

# The complete public API of v0.3.0.
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

def _fields(s):
    return [f for f in dir(s) if f not in _STRUCT_METHODS]

def _test_full_public_api_impl(env, _target):
    env.expect.that_collection(_fields(pypackaging)).contains_exactly(
        sorted(_PUBLIC_API.keys()),
    )
    for module_name, functions in _PUBLIC_API.items():
        module = getattr(pypackaging, module_name)
        env.expect.where(module = module_name).that_collection(_fields(module)).contains_exactly(functions)

def _test_full_public_api(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_full_public_api_impl)

def _test_result_structs_impl(env, _target):
    p = pypackaging
    cases = [
        ("version.parse", p.version.parse("1.0"), ["dev", "epoch", "is_devrelease", "is_postrelease", "is_prerelease", "key", "local", "post", "pre", "release", "version_str"]),
        ("specifiers.parse", p.specifiers.parse(">=1.0"), ["operator", "parsed_version", "version"]),
        ("specifiers.parse_set", p.specifiers.parse_set(">=1.0"), ["specs"]),
        ("requirements.parse", p.requirements.parse("foo[x]>=1; os_name == 'nt'"), ["extras", "marker", "marker_str", "name", "raw_extras", "raw_name", "req_str", "specifier", "url"]),
        ("requirements.parse (bare name)", p.requirements.parse("foo"), ["extras", "marker", "marker_str", "name", "raw_extras", "raw_name", "req_str", "specifier", "url"]),
        ("utils.parse_wheel_filename", p.utils.parse_wheel_filename("foo-1.0-py3-none-any.whl"), ["build", "name", "tags", "version"]),
        ("utils.parse_sdist_filename", p.utils.parse_sdist_filename("foo-1.0.tar.gz"), ["name", "version"]),
        ("tags.parse_tag", p.tags.parse_tag("py3-none-any")[0], ["abi", "interpreter", "platform"]),
    ]
    for what, result, fields in cases:
        env.expect.where(result = what).that_collection(_fields(result)).contains_exactly(fields)

def _test_result_structs(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_result_structs_impl)

def _test_keyword_arguments_impl(env, _target):
    p = pypackaging
    v = p.version.parse(version_str = "1.0")
    env.expect.that_bool(p.version.try_parse(version_str = "x") == None).equals(True)
    env.expect.that_str(p.version.to_string(v = v)).equals("1.0")
    env.expect.that_bool(p.version.get_public_key(v = v) == v.key).equals(True)

    spec = p.specifiers.parse(spec_str = ">=1.0")
    spec_set = p.specifiers.parse_set(spec_set_str = ">=1.0")
    env.expect.that_bool(p.specifiers.contains(spec = spec, version = "1.1", prereleases = None)).equals(True)
    env.expect.that_bool(p.specifiers.set_contains(spec_set = spec_set, version = "1.1", prereleases = None, installed = None)).equals(True)
    env.expect.that_collection(p.specifiers.filter(spec = spec, versions = ["1.1"], prereleases = None)).contains_exactly(["1.1"])
    env.expect.that_collection(p.specifiers.set_filter(spec_set = spec_set, versions = ["1.1"], prereleases = None)).contains_exactly(["1.1"])
    env.expect.that_bool(p.specifiers.prereleases(spec = spec)).equals(False)
    env.expect.that_bool(p.specifiers.set_prereleases(spec_set = spec_set) == None).equals(True)

    marker = p.markers.parse(marker_str = "os_name == 'nt'")
    env.expect.that_bool(p.markers.evaluate(markers = marker, environment = {"os_name": "nt"})).equals(True)
    env.expect.that_str(p.markers.to_string(markers = marker)).equals("os_name == \"nt\"")

    req = p.requirements.parse(req_str = "foo>=1")
    env.expect.that_str(p.requirements.to_string(req = req)).equals("foo>=1")

    supported = p.tags.get_supported(version = "312", platforms = ["any"], impl = "cp", abis = ["cp312"])
    tags = p.tags.parse_tag(tag = "py3-none-any", validate_order = False)
    ranks = p.tags.priority_map(supported = supported)
    env.expect.that_collection(p.tags.select_compatible(supported = ranks, tagged = [("a", tags)])).contains_exactly(["a"])
    env.expect.that_str(p.tags.tag_str(tag = tags[0])).equals("py3-none-any")

    env.expect.that_str(p.utils.canonicalize_name(name = "Foo", validate = False)).equals("foo")
    env.expect.that_str(p.utils.canonicalize_version(version_input = "1.0", strip_trailing_zero = True)).equals("1")
    env.expect.that_bool(p.utils.is_normalized_name(name = "foo")).equals(True)
    env.expect.that_str(p.utils.parse_wheel_filename(filename = "foo-1.0-py3-none-any.whl", validate_order = False).name).equals("foo")
    env.expect.that_str(p.utils.parse_sdist_filename(filename = "foo-1.0.tar.gz").name).equals("foo")

def _test_keyword_arguments(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_keyword_arguments_impl)

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
            _test_full_public_api,
            _test_keyword_arguments,
            _test_readme_examples,
            _test_result_structs,
        ],
    )
