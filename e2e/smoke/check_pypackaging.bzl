"""Smoke test for pypackaging.bzl.

Runs a few checks against every module of the public API at analysis time.
A failed check calls fail(), which fails the build of `//:smoke_test`. The BCR
presubmit runs this module on every supported platform and Bazel version.
"""

load("@pypackaging.bzl", "pypackaging")

_LINUX_CP311_ENV = {
    "extra": "",
    "implementation_name": "cpython",
    "implementation_version": "3.11.9",
    "os_name": "posix",
    "platform_machine": "x86_64",
    "platform_python_implementation": "CPython",
    "platform_release": "6.1.0",
    "platform_system": "Linux",
    "platform_version": "#1 SMP",
    "python_full_version": "3.11.9",
    "python_version": "3.11",
    "sys_platform": "linux",
}

def _check(condition, what):
    if not condition:
        fail("pypackaging.bzl smoke test failed: " + what)

def _check_version():
    version = pypackaging.version
    _check(version.parse("1.2.3").release == (1, 2, 3), "version.parse('1.2.3').release")

    # Ordered PEP 440 versions. All but the plain release go through the
    # regex-based parser rather than the digits-only fast path.
    ordered = ["1.0.dev0", "1.0a1", "1.0rc1", "1.0", "1.0.post1", "1.1", "1!0.1"]
    keys = [version.parse(v).key for v in ordered]
    for i in range(len(keys) - 1):
        _check(keys[i] < keys[i + 1], "version key order: {} < {}".format(ordered[i], ordered[i + 1]))
    _check(version.parse("1.0.0").key == version.parse("1.0").key, "version key: 1.0.0 == 1.0")
    _check(version.parse("1.0RC1").key == version.parse("1.0rc1").key, "version key: 1.0RC1 == 1.0rc1")

def _check_specifiers():
    specifiers = pypackaging.specifiers
    spec_set = specifiers.parse_set(">=1.0,<2")
    _check(specifiers.set_contains(spec_set, "1.5"), "'1.5' in '>=1.0,<2'")
    _check(not specifiers.set_contains(spec_set, "2.0"), "'2.0' not in '>=1.0,<2'")
    _check(not specifiers.set_contains(spec_set, "0.9"), "'0.9' not in '>=1.0,<2'")
    _check(specifiers.set_contains(specifiers.parse_set("~=1.4"), "1.9"), "'1.9' in '~=1.4'")
    _check(not specifiers.set_contains(specifiers.parse_set("~=1.4"), "2.0"), "'2.0' not in '~=1.4'")
    _check(specifiers.set_contains(specifiers.parse_set("==1.*"), "1.3"), "'1.3' in '==1.*'")

def _check_markers():
    markers = pypackaging.markers
    parsed = markers.parse("python_version >= '3.8' and (sys_platform == 'linux' or os_name == 'nt')")
    _check(markers.evaluate(parsed, _LINUX_CP311_ENV), "marker evaluates to True")
    _check(
        not markers.evaluate(markers.parse("python_version < '3.8'"), _LINUX_CP311_ENV),
        "marker evaluates to False",
    )
    _check(
        markers.evaluate(markers.parse("extra == 'test'"), dict(_LINUX_CP311_ENV, extra = "test")),
        "extra == 'test' with extra = 'test'",
    )

    # Non-standard extension: a list-valued "extra" tests membership.
    _check(
        markers.evaluate(markers.parse("extra == 'b'"), dict(_LINUX_CP311_ENV, extra = ["a", "b"])),
        "extra == 'b' with extra = ['a', 'b']",
    )

def _check_requirements():
    req = pypackaging.requirements.parse("Foo_Bar[baz,qux]>=1.0,<2; python_version >= '3.8'")
    _check(pypackaging.utils.canonicalize_name(req.name) == "foo-bar", "requirement name")
    _check(sorted(req.extras) == ["baz", "qux"], "requirement extras")
    specs = sorted([(s.operator, s.version) for s in req.specifier.specs])
    _check(specs == [("<", "2"), (">=", "1.0")], "requirement specifiers: {}".format(specs))
    _check(pypackaging.markers.evaluate(req.marker, _LINUX_CP311_ENV), "requirement marker")

def _check_tags():
    tags = pypackaging.tags
    supported = tags.get_supported(
        version = "311",
        platforms = ["manylinux_2_17_x86_64"],
        impl = "cp",
        abis = ["cp311"],
    )
    for tag in ["cp311-cp311-manylinux_2_17_x86_64", "cp311-abi3-manylinux_2_17_x86_64", "py3-none-any"]:
        _check(tag in supported, "{} in get_supported(...)".format(tag))
    _check(
        supported.index("cp311-cp311-manylinux_2_17_x86_64") < supported.index("py3-none-any"),
        "get_supported(...) priority order",
    )
    parsed = tags.parse_tag("cp311-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64")
    _check(len(parsed) == 2, "parse_tag expands compressed tag sets")

def _check_utils():
    utils = pypackaging.utils
    _check(utils.canonicalize_name("Foo_Bar") == "foo-bar", "canonicalize_name")
    _check(utils.canonicalize_version("1.0.0") == "1", "canonicalize_version")

    wheel = utils.parse_wheel_filename("Foo_Bar-1.0-cp311-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl")
    _check(wheel.name == "foo-bar", "wheel name")
    _check(wheel.version.key == pypackaging.version.parse("1.0").key, "wheel version")
    _check(len(wheel.tags) == 2, "wheel tags")

    # Tags compare by value, so tags from parse_tag can be looked up in a
    # parsed wheel's tags.
    for tag in pypackaging.tags.parse_tag("cp311-abi3-manylinux2014_x86_64"):
        _check(tag in wheel.tags, "parse_tag result in wheel tags")

    sdist = utils.parse_sdist_filename("Foo_Bar-1.0.tar.gz")
    _check(sdist.name == "foo-bar", "sdist name")
    _check(sdist.version.key == pypackaging.version.parse("1.0").key, "sdist version")

def _smoke_test_impl(ctx):
    _check_version()
    _check_specifiers()
    _check_markers()
    _check_requirements()
    _check_tags()
    _check_utils()

    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows[platform_common.ConstraintValueInfo])
    if is_windows:
        script = ctx.actions.declare_file(ctx.label.name + ".bat")
        ctx.actions.write(script, "@echo off\r\necho passed", is_executable = True)
    else:
        script = ctx.actions.declare_file(ctx.label.name + ".sh")
        ctx.actions.write(script, "echo passed", is_executable = True)

    return [DefaultInfo(executable = script)]

smoke_test = rule(
    implementation = _smoke_test_impl,
    test = True,
    attrs = {
        "_windows": attr.label(default = "@platforms//os:windows"),
    },
)
