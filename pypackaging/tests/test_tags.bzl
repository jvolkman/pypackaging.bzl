"""Tests for platform_tags.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/tags:cpython.bzl", "cpython_tags")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/tags:tags.bzl", "get_supported", "tags_internal")

def _test_get_supported_basic_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["any"], impl = "cp", abis = ["none"])

    # Let's check some specific ones are present.
    env.expect.that_collection(tags).contains("cp311-none-any")
    env.expect.that_collection(tags).contains("cp311-abi3-any")
    env.expect.that_collection(tags).contains("cp32-abi3-any")
    env.expect.that_collection(tags).contains("py311-none-any")
    env.expect.that_collection(tags).contains("py3-none-any")

def _test_get_supported_basic(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_get_supported_basic_impl,
    )

def _test_get_supported_pypy_impl(env, _target):
    tags = get_supported(version = "39", platforms = ["any"], impl = "pp", abis = ["none"])
    env.expect.that_collection(tags).contains("pp39-none-any")
    env.expect.that_collection(tags).contains("py39-none-any")
    env.expect.that_collection(tags).contains("py3-none-any")
    env.expect.that_collection(tags).not_contains("cp39-abi3-any")

def _test_get_supported_pypy(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_get_supported_pypy_impl,
    )

def _test_expand_macosx_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["macosx_11_0_arm64"], impl = "cp", abis = ["none"])

    # Should contain the exact one
    env.expect.that_collection(tags).contains("cp311-none-macosx_11_0_arm64")

    # Should contain universal2 fallback
    env.expect.that_collection(tags).contains("cp311-none-macosx_11_0_universal2")

    # Should contain 10.16 fallback
    env.expect.that_collection(tags).contains("cp311-none-macosx_10_16_universal2")

    # Should contain older compatible versions (e.g. 10.15 universal2)
    env.expect.that_collection(tags).contains("cp311-none-macosx_10_15_universal2")

def _test_expand_macosx(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_macosx_impl)

def _test_expand_manylinux_pep600_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["manylinux_2_17_x86_64"], impl = "cp", abis = ["none"])
    env.expect.that_collection(tags).contains("cp311-none-linux_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-manylinux_2_17_x86_64")

    # Should contain legacy alias
    env.expect.that_collection(tags).contains("cp311-none-manylinux2014_x86_64")

    # Should contain older compatible versions
    env.expect.that_collection(tags).contains("cp311-none-manylinux_2_5_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-manylinux1_x86_64")

def _test_expand_manylinux_pep600(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_manylinux_pep600_impl)

def _test_expand_manylinux_legacy_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["manylinux2014_x86_64"], impl = "cp", abis = ["none"])
    env.expect.that_collection(tags).contains("cp311-none-linux_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-manylinux_2_17_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-manylinux2014_x86_64")

def _test_expand_manylinux_legacy(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_manylinux_legacy_impl)

def _test_expand_musllinux_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["musllinux_1_2_x86_64"], impl = "cp", abis = ["none"])
    env.expect.that_collection(tags).contains("cp311-none-linux_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-musllinux_1_2_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-musllinux_1_1_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-musllinux_1_0_x86_64")

def _test_expand_musllinux(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_musllinux_impl)

def _test_expand_android_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["android_30_arm64_v8a"], impl = "cp", abis = ["none"])
    env.expect.that_collection(tags).contains("cp311-none-android_30_arm64_v8a")
    env.expect.that_collection(tags).contains("cp311-none-android_29_arm64_v8a")

    # Should stop at 16
    env.expect.that_collection(tags).contains("cp311-none-android_16_arm64_v8a")
    env.expect.that_collection(tags).not_contains("cp311-none-android_15_arm64_v8a")

def _test_expand_android(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_android_impl)

def _test_expand_ios_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["ios_14_0_arm64"], impl = "cp", abis = ["none"])
    env.expect.that_collection(tags).contains("cp311-none-ios_14_0_arm64")
    env.expect.that_collection(tags).contains("cp311-none-ios_13_0_arm64")
    env.expect.that_collection(tags).contains("cp311-none-ios_12_0_arm64")

    # Should not contain < 12
    env.expect.that_collection(tags).not_contains("cp311-none-ios_11_0_arm64")

def _test_expand_ios(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_ios_impl)

def _test_freethreaded_impl(env, _target):
    tags = get_supported(version = "313", platforms = ["any"], impl = "cp", abis = ["cp313t"])
    env.expect.that_collection(tags).contains("cp313-cp313t-any")

    # Should use abi3t, not abi3
    env.expect.that_collection(tags).contains("cp313-abi3t-any")
    env.expect.that_collection(tags).not_contains("cp313-abi3-any")

    # Older versions should also have abi3t
    env.expect.that_collection(tags).contains("cp312-abi3t-any")
    env.expect.that_collection(tags).not_contains("cp312-abi3-any")

def _test_freethreaded(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_freethreaded_impl)

def _test_expand_allowed_platforms_manylinux_impl(env, _target):
    platforms = tags_internal.expand_allowed_platforms(["manylinux_2_17_x86_64"])
    env.expect.that_collection(platforms).contains_exactly([
        "manylinux_2_17_x86_64",
        "manylinux2014_x86_64",
        "manylinux_2_16_x86_64",
        "manylinux_2_15_x86_64",
        "manylinux_2_14_x86_64",
        "manylinux_2_13_x86_64",
        "manylinux_2_12_x86_64",
        "manylinux2010_x86_64",
        "manylinux_2_11_x86_64",
        "manylinux_2_10_x86_64",
        "manylinux_2_9_x86_64",
        "manylinux_2_8_x86_64",
        "manylinux_2_7_x86_64",
        "manylinux_2_6_x86_64",
        "manylinux_2_5_x86_64",
        "manylinux1_x86_64",
        "linux_x86_64",
    ]).in_order()

def _test_expand_allowed_platforms_manylinux(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_allowed_platforms_manylinux_impl)

def _test_expand_allowed_platforms_armv8l_impl(env, _target):
    platforms = tags_internal.expand_allowed_platforms(["manylinux_2_17_armv8l"])
    env.expect.that_collection(platforms).contains_exactly([
        "manylinux_2_17_armv8l",
        "manylinux2014_armv8l",
        "manylinux_2_17_armv7l",
        "manylinux2014_armv7l",
        "linux_armv8l",
        "linux_armv7l",
    ]).in_order()

def _test_expand_allowed_platforms_armv8l(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_allowed_platforms_armv8l_impl)

def _test_expand_allowed_platforms_musllinux_order_impl(env, _target):
    platforms = tags_internal.expand_allowed_platforms(["musllinux_1_2_x86_64"])
    env.expect.that_collection(platforms).contains_exactly([
        "musllinux_1_2_x86_64",
        "musllinux_1_1_x86_64",
        "musllinux_1_0_x86_64",
        "linux_x86_64",
    ]).in_order()

def _test_expand_allowed_platforms_musllinux_order(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_allowed_platforms_musllinux_order_impl)

def _test_expand_allowed_platforms_legacy_order_impl(env, _target):
    platforms = tags_internal.expand_allowed_platforms(["manylinux2014_aarch64"])
    env.expect.that_collection(platforms).contains_exactly([
        "manylinux_2_17_aarch64",
        "manylinux2014_aarch64",
        "linux_aarch64",
    ]).in_order()

def _test_expand_allowed_platforms_legacy_order(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_allowed_platforms_legacy_order_impl)

def _test_expand_allowed_platforms_many_and_musl_order_impl(env, _target):
    # Matches packaging's _linux_platforms(): manylinux, then musllinux, then linux.
    platforms = tags_internal.expand_allowed_platforms(["manylinux_2_17_aarch64", "musllinux_1_1_aarch64"])
    env.expect.that_collection(platforms).contains_exactly([
        "manylinux_2_17_aarch64",
        "manylinux2014_aarch64",
        "musllinux_1_1_aarch64",
        "musllinux_1_0_aarch64",
        "linux_aarch64",
    ]).in_order()

    # An explicitly requested linux_<arch> keeps its position.
    platforms = tags_internal.expand_allowed_platforms(["linux_aarch64", "manylinux_2_17_aarch64"])
    env.expect.that_collection(platforms).contains_exactly([
        "linux_aarch64",
        "manylinux_2_17_aarch64",
        "manylinux2014_aarch64",
    ]).in_order()

def _test_expand_allowed_platforms_many_and_musl_order(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_allowed_platforms_many_and_musl_order_impl)

def _test_get_supported_linux_priority_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["manylinux_2_28_x86_64"], impl = "cp", abis = ["cp311"])

    # Same priority as packaging 26.2: the newest manylinux tag first and the
    # generic linux tag after all manylinux tags for a given ABI.
    env.expect.that_str(tags[0]).equals("cp311-cp311-manylinux_2_28_x86_64")
    env.expect.that_int(tags.index("cp311-cp311-linux_x86_64")).equals(27)
    env.expect.that_str(tags[26]).equals("cp311-cp311-manylinux1_x86_64")
    env.expect.that_str(tags[28]).equals("cp311-abi3-manylinux_2_28_x86_64")

    tags = get_supported(version = "312", platforms = ["musllinux_1_2_x86_64"], impl = "cp", abis = ["cp312"])
    env.expect.that_collection(tags[:5]).contains_exactly([
        "cp312-cp312-musllinux_1_2_x86_64",
        "cp312-cp312-musllinux_1_1_x86_64",
        "cp312-cp312-musllinux_1_0_x86_64",
        "cp312-cp312-linux_x86_64",
        "cp312-abi3-musllinux_1_2_x86_64",
    ]).in_order()

def _test_get_supported_linux_priority(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_get_supported_linux_priority_impl)

def _test_freethreaded_filtered_abis_impl(env, _target):
    # abi3/none are removed before checking the first ABI, like packaging.
    tags = cpython_tags((3, 13), ["abi3", "cp313t"], ["any"])
    env.expect.that_collection(tags).contains_exactly([
        "cp313-cp313t-any",
        "cp313-abi3t-any",
        "cp313-none-any",
    ] + ["cp3{}-abi3t-any".format(m) for m in range(12, 1, -1)]).in_order()

    tags = cpython_tags((3, 13), ["none", "cp313t"], ["any"])
    env.expect.that_collection(tags).contains("cp313-abi3t-any")
    env.expect.that_collection(tags).not_contains("cp313-abi3-any")

    # "cp" must be followed by digits for the ABI to count as free-threaded.
    tags = cpython_tags((3, 13), ["cpt"], ["any"])
    env.expect.that_collection(tags).contains("cp313-abi3-any")
    env.expect.that_collection(tags).not_contains("cp313-abi3t-any")

    # A free-threaded ABI that isn't first doesn't count.
    tags = cpython_tags((3, 13), ["cp313", "cp313t"], ["any"])
    env.expect.that_collection(tags).contains("cp313-abi3-any")
    env.expect.that_collection(tags).not_contains("cp313-abi3t-any")

def _test_freethreaded_filtered_abis(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_freethreaded_filtered_abis_impl)

def _test_get_supported_lowercase_impl(env, _target):
    # Like packaging's Tag, generated tags are lowercase. Free-threading
    # detection is case-sensitive, also like packaging.
    tags = get_supported(version = "313", platforms = ["Linux_X86_64"], impl = "cp", abis = ["CP313T"])
    env.expect.that_collection(tags[:4]).contains_exactly([
        "cp313-cp313t-linux_x86_64",
        "cp313-abi3-linux_x86_64",
        "cp313-none-linux_x86_64",
        "cp312-abi3-linux_x86_64",
    ]).in_order()
    env.expect.that_collection(tags).contains("py313-none-linux_x86_64")

    tags = get_supported(version = "310", platforms = ["Any"], impl = "PP", abis = ["PyPy310_PP73"])
    env.expect.that_collection(tags).contains_exactly([
        "pp310-pypy310_pp73-any",
        "pp310-none-any",
        "py310-none-any",
        "py3-none-any",
    ] + ["py3{}-none-any".format(m) for m in range(9, -1, -1)] + [
        "pp310-none-any",
        "py310-none-any",
        "py3-none-any",
    ] + ["py3{}-none-any".format(m) for m in range(9, -1, -1)]).in_order()

def _test_get_supported_lowercase(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_get_supported_lowercase_impl)

def tags_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_get_supported_basic,
            _test_get_supported_pypy,
            _test_expand_macosx,
            _test_expand_manylinux_pep600,
            _test_expand_manylinux_legacy,
            _test_expand_musllinux,
            _test_expand_android,
            _test_expand_ios,
            _test_freethreaded,
            _test_expand_allowed_platforms_manylinux,
            _test_expand_allowed_platforms_armv8l,
            _test_expand_allowed_platforms_musllinux_order,
            _test_expand_allowed_platforms_legacy_order,
            _test_expand_allowed_platforms_many_and_musl_order,
            _test_get_supported_linux_priority,
            _test_freethreaded_filtered_abis,
            _test_get_supported_lowercase,
        ],
    )
