"""Smoke test for pypackaging.bzl."""

load("@pypackaging.bzl//:pypackaging.bzl", "pypackaging")

def _smoke_test_impl(ctx):
    # Test version parsing
    v = pypackaging.version.parse("1.2.3")
    if v.release != (1, 2, 3):
        fail("version.parse failed")

    # Test utils
    normalized = pypackaging.utils.canonicalize_name("Foo_Bar")
    if normalized != "foo-bar":
        fail("utils.canonicalize_name failed")

    out = ctx.actions.declare_file(ctx.label.name + ".passed")
    ctx.actions.write(out, "passed")

    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows[platform_common.ConstraintValueInfo])
    if is_windows:
        script = ctx.actions.declare_file(ctx.label.name + ".bat")
        ctx.actions.write(script, "@echo off\r\necho passed", is_executable = True)
    else:
        script = ctx.actions.declare_file(ctx.label.name + ".sh")
        ctx.actions.write(script, "echo passed", is_executable = True)

    return [DefaultInfo(files = depset([out]), executable = script)]

smoke_test = rule(
    implementation = _smoke_test_impl,
    test = True,
    attrs = {
        "_windows": attr.label(default = "@platforms//os:windows"),
    },
)
