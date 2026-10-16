"""Tests for tags.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/tags:cpython.bzl", "cpython_tags")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/tags:manylinux.bzl", "manylinux_platforms")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/tags:tags.bzl", "get_supported", "parse_tag", "priority_map", "select_compatible", "tag_str", "tags_internal")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/tags:utils.bzl", "get_python_version")
load(":get_supported_fixtures.bzl", "GET_SUPPORTED_FIXTURES")

def _parse_tag_subject_impl(ctx):
    parse_tag(ctx.attr.tag, validate_order = ctx.attr.validate_order)
    return []

_parse_tag_subject = rule(
    implementation = _parse_tag_subject_impl,
    attrs = {
        "tag": attr.string(),
        "validate_order": attr.bool(),
    },
)

def _tag_strs(tags):
    return [tag_str(t) for t in tags]

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

def _test_manylinux_glibc_major_3_impl(env, _target):
    platforms = manylinux_platforms((3, 1), "x86_64")
    expected = ["manylinux_3_1_x86_64", "manylinux_3_0_x86_64"]
    for minor in range(50, 4, -1):
        expected.append("manylinux_2_{}_x86_64".format(minor))
        if minor == 17:
            expected.append("manylinux2014_x86_64")
        elif minor == 12:
            expected.append("manylinux2010_x86_64")
        elif minor == 5:
            expected.append("manylinux1_x86_64")
    env.expect.that_collection(platforms).contains_exactly(expected).in_order()

    platforms = manylinux_platforms((4, 0), "aarch64")
    env.expect.that_str(platforms[0]).equals("manylinux_4_0_aarch64")
    env.expect.that_str(platforms[1]).equals("manylinux_3_50_aarch64")
    env.expect.that_str(platforms[51]).equals("manylinux_3_0_aarch64")
    env.expect.that_str(platforms[52]).equals("manylinux_2_50_aarch64")
    env.expect.that_str(platforms[-1]).equals("manylinux2014_aarch64")
    env.expect.that_int(len(platforms)).equals(1 + 51 + 34 + 1)

    tags = get_supported(version = "311", platforms = ["manylinux_3_0_x86_64"], impl = "cp", abis = ["cp311"])
    env.expect.that_str(tags[0]).equals("cp311-cp311-manylinux_3_0_x86_64")
    env.expect.that_str(tags[1]).equals("cp311-cp311-manylinux_2_50_x86_64")
    env.expect.that_int(tags.index("cp311-cp311-linux_x86_64")).equals(50)

def _test_manylinux_glibc_major_3(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_manylinux_glibc_major_3_impl)

def _test_parse_tag_impl(env, _target):
    env.expect.that_collection(_tag_strs(parse_tag("py3-none-any"))).contains_exactly(["py3-none-any"])

    # Compressed tag sets expand in component order; tags are lowercased.
    env.expect.that_collection(_tag_strs(parse_tag("CP311.cp312-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64"))).contains_exactly([
        "cp311-abi3-manylinux_2_17_x86_64",
        "cp311-abi3-manylinux2014_x86_64",
        "cp312-abi3-manylinux_2_17_x86_64",
        "cp312-abi3-manylinux2014_x86_64",
    ]).in_order()

    # Tag structs compare by value.
    env.expect.that_bool(parse_tag("PY3-None-ANY")[0] == parse_tag("py3-none-any")[0]).equals(True)

    # validate_order accepts sorted components.
    env.expect.that_collection(_tag_strs(parse_tag("py2.py3-none-any", validate_order = True))).contains_exactly([
        "py2-none-any",
        "py3-none-any",
    ]).in_order()

def _test_parse_tag(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_tag_impl)

def _test_parse_tag_dedupe_impl(env, _target):
    # packaging returns a frozenset; duplicates are dropped, first occurrence kept.
    env.expect.that_collection(_tag_strs(parse_tag("py3.py3-none-any"))).contains_exactly(["py3-none-any"])
    env.expect.that_collection(_tag_strs(parse_tag("py3-none-any.any"))).contains_exactly(["py3-none-any"])
    env.expect.that_collection(_tag_strs(parse_tag("PY3.py3.py2-none-any"))).contains_exactly([
        "py3-none-any",
        "py2-none-any",
    ]).in_order()

def _test_parse_tag_dedupe(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_tag_dedupe_impl)

def _test_parse_tag_empty_components_impl(env, _target):
    # Like packaging, empty components are accepted.
    env.expect.that_collection(_tag_strs(parse_tag("py3--any"))).contains_exactly(["py3--any"])
    env.expect.that_collection(_tag_strs(parse_tag("-none-any"))).contains_exactly(["-none-any"])
    env.expect.that_collection(_tag_strs(parse_tag("py3-none-any."))).contains_exactly([
        "py3-none-any",
        "py3-none-",
    ]).in_order()
    env.expect.that_collection(_tag_strs(parse_tag("--"))).contains_exactly(["--"])

def _test_parse_tag_empty_components(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_tag_empty_components_impl)

def _test_parse_tag_wrong_parts_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(matching.contains("Invalid tag"))

def _test_parse_tag_wrong_parts(name):
    util.helper_target(_parse_tag_subject, name = name + "_subject", tag = "py3-none")
    analysis_test(name = name, target = name + "_subject", expect_failure = True, impl = _test_parse_tag_wrong_parts_impl)

def _test_parse_tag_unsorted_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(matching.contains("not in sorted order"))

def _test_parse_tag_unsorted(name):
    util.helper_target(_parse_tag_subject, name = name + "_subject", tag = "py3.py2-none-any", validate_order = True)
    analysis_test(name = name, target = name + "_subject", expect_failure = True, impl = _test_parse_tag_unsorted_impl)

def _test_expand_apple_custom_prefix_impl(env, _target):
    # Like pip, a custom "macosx*" prefix is kept during expansion.
    platforms = tags_internal.expand_allowed_platforms(["macosxcustom_10_9_x86_64"])
    env.expect.that_collection(platforms[:6]).contains_exactly([
        "macosxcustom_10_9_x86_64",
        "macosxcustom_10_9_intel",
        "macosxcustom_10_9_fat64",
        "macosxcustom_10_9_fat32",
        "macosxcustom_10_9_universal2",
        "macosxcustom_10_9_universal",
    ]).in_order()
    env.expect.that_str(platforms[-1]).equals("macosxcustom_10_4_universal")

    platforms = tags_internal.expand_allowed_platforms(["ioscustom_12_1_arm64_iphoneos"])
    env.expect.that_collection(platforms).contains_exactly([
        "ioscustom_12_1_arm64_iphoneos",
        "ioscustom_12_0_arm64_iphoneos",
    ]).in_order()

    # Unparsable platforms are passed through.
    env.expect.that_collection(tags_internal.expand_allowed_platforms(["macosx_x_y_arm64"])).contains_exactly(["macosx_x_y_arm64"])
    env.expect.that_collection(tags_internal.expand_allowed_platforms(["android_21_"])).contains_exactly(["android_21_"])

def _test_expand_apple_custom_prefix(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_apple_custom_prefix_impl)

def _test_expand_hyphen_normalization_impl(env, _target):
    # Like packaging, hyphens in the Android ABI and iOS multiarch become underscores.
    platforms = tags_internal.expand_allowed_platforms(["android_18_arm64-v8a"])
    env.expect.that_collection(platforms).contains_exactly([
        "android_18_arm64_v8a",
        "android_17_arm64_v8a",
        "android_16_arm64_v8a",
    ]).in_order()

    platforms = tags_internal.expand_allowed_platforms(["ios_13_1_arm64-iphoneos"])
    env.expect.that_collection(platforms[:3]).contains_exactly([
        "ios_13_1_arm64_iphoneos",
        "ios_13_0_arm64_iphoneos",
        "ios_12_9_arm64_iphoneos",
    ]).in_order()

def _test_expand_hyphen_normalization(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_hyphen_normalization_impl)

def _test_priority_map_impl(env, _target):
    supported = ["cp311-cp311-manylinux_2_17_x86_64", "CP311-abi3-manylinux_2_17_x86_64", "py3-none-any", "cp311-cp311-manylinux_2_17_x86_64"]
    ranks = priority_map(supported)
    env.expect.that_dict(ranks).contains_exactly({
        "cp311-cp311-manylinux_2_17_x86_64": 0,
        "cp311-abi3-manylinux_2_17_x86_64": 1,
        "py3-none-any": 2,
    })

    # Tag structs work too.
    env.expect.that_dict(priority_map(parse_tag("py2.py3-none-any"))).contains_exactly({
        "py2-none-any": 0,
        "py3-none-any": 1,
    })

    env.expect.that_str(tag_str(parse_tag("PY3-NONE-ANY")[0])).equals("py3-none-any")

def _test_priority_map(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_priority_map_impl)

def _test_select_compatible_impl(env, _target):
    supported = get_supported(version = "311", platforms = ["manylinux_2_28_x86_64"], impl = "cp", abis = ["cp311"])
    filenames = [
        "foo-1.0-py2-none-any.whl",
        "foo-1.0-py3-none-any.whl",
        "foo-1.0-cp311-cp311-linux_x86_64.whl",
        "foo-1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        "foo-1.0-cp311-cp311-win_amd64.whl",
        "foo-1.0-cp311-abi3-manylinux_2_28_x86_64.whl",
        "foo-1.0-py2.py3-none-any.whl",
    ]
    tagged = [(f, parse_tag(f[len("foo-1.0-"):-len(".whl")])) for f in filenames]
    expected = [
        "foo-1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        "foo-1.0-cp311-cp311-linux_x86_64.whl",
        "foo-1.0-cp311-abi3-manylinux_2_28_x86_64.whl",
        "foo-1.0-py3-none-any.whl",
        "foo-1.0-py2.py3-none-any.whl",
    ]
    env.expect.that_collection(select_compatible(supported, tagged)).contains_exactly(expected).in_order()
    env.expect.that_collection(select_compatible(priority_map(supported), tagged)).contains_exactly(expected).in_order()

    # Tag strings are accepted as well; nothing compatible gives an empty list.
    env.expect.that_collection(select_compatible(["py3-none-any"], [("a", ["py2-none-any"]), ("b", ["PY3-none-any"])])).contains_exactly(["b"])
    env.expect.that_collection(select_compatible(supported, [("a", ["cp311-cp311-win_amd64"])])).contains_exactly([])

    # Compressed tag strings are expanded.
    env.expect.that_collection(select_compatible(["py3-none-any"], [("a", ["py2.py3-none-any"])])).contains_exactly(["a"])

def _test_select_compatible(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_select_compatible_impl)

def _test_get_python_version_impl(env, _target):
    env.expect.that_bool(get_python_version("311") == (3, 11)).equals(True)
    env.expect.that_bool(get_python_version("27") == (2, 7)).equals(True)
    env.expect.that_bool(get_python_version("3") == (3,)).equals(True)
    env.expect.that_bool(get_python_version("3100") == (3, 100)).equals(True)

    # A major-only version gets only user ABIs, none, and py3 tags.
    tags = get_supported(version = "3", platforms = ["any"], impl = "cp", abis = ["cp3"])
    env.expect.that_collection(tags).contains_exactly([
        "cp3-cp3-any",
        "cp3-none-any",
        "py3-none-any",
        "cp3-none-any",
        "py3-none-any",
    ]).in_order()

def _test_get_python_version(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_get_python_version_impl)

def _test_get_supported_no_platforms_impl(env, _target):
    expected = get_supported(version = "311", platforms = ["any"], impl = "cp", abis = ["cp311"])
    env.expect.that_str(expected[0]).equals("cp311-cp311-any")
    for platforms in [None, [], ["macosx_9_0_x86_64"]]:
        env.expect.where(platforms = platforms).that_collection(
            get_supported(version = "311", platforms = platforms, impl = "cp", abis = ["cp311"]),
        ).contains_exactly(expected).in_order()

def _test_get_supported_no_platforms(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_get_supported_no_platforms_impl)

def _test_get_supported_fixtures_impl(env, _target):
    # Expected values come from packaging 26.2 with pip 25.2's get_supported
    # wrapper (and packaging's own linux expansion for manylinux/musllinux).
    for f in GET_SUPPORTED_FIXTURES:
        supported = get_supported(version = f.version, platforms = f.platforms, impl = f.impl, abis = f.abis)
        env.expect.where(case = f.name).that_int(len(supported)).equals(f.count)
        env.expect.where(case = f.name).that_collection(supported[:len(f.head)]).contains_exactly(f.head).in_order()
        env.expect.where(case = f.name).that_int(hash(" ".join(supported))).equals(f.hash)

def _test_get_supported_fixtures(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_get_supported_fixtures_impl)

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
            _test_manylinux_glibc_major_3,
            _test_parse_tag,
            _test_parse_tag_dedupe,
            _test_parse_tag_empty_components,
            _test_parse_tag_wrong_parts,
            _test_parse_tag_unsorted,
            _test_expand_apple_custom_prefix,
            _test_expand_hyphen_normalization,
            _test_priority_map,
            _test_select_compatible,
            _test_get_python_version,
            _test_get_supported_no_platforms,
            _test_get_supported_fixtures,
        ],
    )
