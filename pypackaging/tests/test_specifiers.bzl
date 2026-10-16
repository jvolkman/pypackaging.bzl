"""Tests for specifiers.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/specifiers:specifiers.bzl", "specifiers")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/version:version.bzl", version_mod = "version")

def _test_specifier_basic_impl(env, _target):
    spec = specifiers.parse(">=1.0")
    env.expect.that_str(spec.operator).equals(">=")
    env.expect.that_str(spec.version).equals("1.0")

def _test_specifier_basic(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_specifier_basic_impl)

def _test_specifier_contains_impl(env, _target):
    # >=
    spec = specifiers.parse(">=1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "0.9")).equals(False)

    # <=
    spec = specifiers.parse("<=1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "0.9")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(False)

    # ==
    spec = specifiers.parse("==1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.0.0")).equals(True)  # Normalized
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(False)

    # == with wildcard
    spec = specifiers.parse("==1.*")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.9.1")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "2.0")).equals(False)

    spec = specifiers.parse("==1.2.*")
    env.expect.that_bool(specifiers.contains(spec, "1.2.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.2.3")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.3.0")).equals(False)

    # !=
    spec = specifiers.parse("!=1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(True)

    # != with wildcard
    spec = specifiers.parse("!=1.*")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "2.0")).equals(True)

    # >
    spec = specifiers.parse(">1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(False)

    # >V MUST NOT allow a post-release of the specified version unless the specified version is itself a post-release.
    env.expect.that_bool(specifiers.contains(spec, "1.0.post1")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "1.1.post1")).equals(True)

    # <
    spec = specifiers.parse("<1.0")
    env.expect.that_bool(specifiers.contains(spec, "0.9")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(False)

    # <V MUST NOT allow a pre-release of the specified version unless the specified version is itself a pre-release.
    env.expect.that_bool(specifiers.contains(spec, "1.0a1")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "0.9a1")).equals(True)

    # ~=
    spec = specifiers.parse("~=2.2")
    env.expect.that_bool(specifiers.contains(spec, "2.2")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "2.7")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "3.0")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "2.1")).equals(False)

    spec = specifiers.parse("~=1.4.5")
    env.expect.that_bool(specifiers.contains(spec, "1.4.5")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.4.6")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.5.0")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "1.4.4")).equals(False)

    # ===
    spec = specifiers.parse("===1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.0.0")).equals(False)  # Exact string match
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(False)

    spec = specifiers.parse("===abc")
    env.expect.that_bool(specifiers.contains(spec, "abc")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "ABC")).equals(True)  # Case-insensitive

_UPSTREAM_SPECIFIERS_PASS = [
    # Test the equality operation
    ("2.0", "==2"),
    ("2.0", "==2.0"),
    ("2.0", "==2.0.0"),
    ("2.0+deadbeef", "==2"),
    ("2.0+deadbeef", "==2.0"),
    ("2.0+deadbeef", "==2.0.0"),
    ("2.0+deadbeef", "==2+deadbeef"),
    ("2.0+deadbeef", "==2.0+deadbeef"),
    ("2.0+deadbeef", "==2.0.0+deadbeef"),
    ("2.0+deadbeef.0", "==2.0.0+deadbeef.00"),
    # Test the equality operation with a prefix
    ("2.dev1", "==2.*"),
    ("2a1", "==2.*"),
    ("2a1.post1", "==2.*"),
    ("2b1", "==2.*"),
    ("2b1.dev1", "==2.*"),
    ("2c1", "==2.*"),
    ("2c1.post1.dev1", "==2.*"),
    ("2c1.post1.dev1", "==2.0.*"),
    ("2rc1", "==2.*"),
    ("2rc1", "==2.0.*"),
    ("2", "==2.*"),
    ("2", "==2.0.*"),
    ("2", "==2.0.0.*"),
    ("2", "==0!2.*"),
    ("0!2", "==2.*"),
    ("2.0", "==2.*"),
    ("2.0.0", "==2.*"),
    ("2.0.0.0", "==2.0.*"),
    ("2.1+local.version", "==2.1.*"),
    # Test the in-equality operation
    ("2.1", "!=2"),
    ("2.1", "!=2.0"),
    ("2.0.1", "!=2"),
    ("2.0.1", "!=2.0"),
    ("2.0.1", "!=2.0.0"),
    ("2.0", "!=2.0+deadbeef"),
    # Test the in-equality operation with a prefix
    ("2.0", "!=3.*"),
    ("2.1", "!=2.0.*"),
    ("3", "!=2.0.0.*"),
    ("2.1.0.0", "!=2.0.*"),
    # Test the greater than equal operation
    ("2.0", ">=2"),
    ("2.0", ">=2.0"),
    ("2.0", ">=2.0.0"),
    ("2.0.post1", ">=2"),
    ("2.0.post1.dev1", ">=2"),
    ("3", ">=2"),
    ("3.0.0a8", ">=3.0.0a7"),
    # Test the less than equal operation
    ("2.0", "<=2"),
    ("2.0", "<=2.0"),
    ("2.0", "<=2.0.0"),
    ("2.0.dev1", "<=2"),
    ("2.0a1", "<=2"),
    ("2.0a1.dev1", "<=2"),
    ("2.0b1", "<=2"),
    ("2.0b1.post1", "<=2"),
    ("2.0c1", "<=2"),
    ("2.0c1.post1.dev1", "<=2"),
    ("2.0rc1", "<=2"),
    ("1", "<=2"),
    ("3.0.0a7", "<=3.0.0a8"),
    # Test the greater than operation
    ("3", ">2"),
    ("2.1", ">2.0"),
    ("2.0.1", ">2"),
    ("2.1.post1", ">2"),
    ("2.1+local.version", ">2"),
    ("3.0.0a8", ">3.0.0a7"),
    # Test the less than operation
    ("1", "<2"),
    ("2.0", "<2.1"),
    ("2.0.dev0", "<2.1"),
    ("3.0.0a7", "<3.0.0a8"),
    # Test the compatibility operation
    ("1", "~=1.0"),
    ("1.0.1", "~=1.0"),
    ("1.1", "~=1.0"),
    ("1.9999999", "~=1.0"),
    ("1.1", "~=1.0a1"),
    # Test that epochs are handled sanely
    ("2!1.0", "~=2!1.0"),
    ("2!1.0", "==2!1.*"),
    ("2!1.0", "==2!1.0"),
    ("2!1.0", "!=1.0"),
    ("2!1.0.0", "==2!1.0.0.0.*"),
    ("2!1.0.0", "==2!1.0.*"),
    ("2!1.0.0", "==2!1.*"),
    ("1.0", "!=2!1.0"),
    ("1.0", "<=2!0.1"),
    ("2!1.0", ">=2.0"),
    ("1.0", "<2!0.1"),
    ("2!1.0", ">2.0"),
    # Test some normalization rules
    ("2.0.5", ">2.0dev"),
    # Test local versions with pre/dev/post segments and >
    ("1.0+local", ">1.0.dev1"),
    ("4.1.0a2.dev1235+local", ">4.1.0a2.dev1234"),
    ("1.0a2+local", ">1.0a1"),
    ("1.0b2+local", ">1.0b1"),
    ("1.0rc2+local", ">1.0rc1"),
    ("1.0.post2+local", ">1.0.post1"),
    ("1.0.dev2+local", ">1.0.dev1"),
    ("1.0a1.dev2+local", ">1.0a1.dev1"),
    ("1.0.post1.dev2+local", ">1.0.post1.dev1"),
]

_UPSTREAM_SPECIFIERS_FAIL = [
    # Test the equality operation
    ("2.1", "==2"),
    ("2.1", "==2.0"),
    ("2.1", "==2.0.0"),
    ("2.0", "==2.0+deadbeef"),
    # Test the equality operation with a prefix
    ("2.0", "==3.*"),
    ("2.1", "==2.0.*"),
    ("3", "==2.0.0.*"),
    ("2.1.0.0", "==2.0.*"),
    # Test the in-equality operation
    ("2.0", "!=2"),
    ("2.0", "!=2.0"),
    ("2.0", "!=2.0.0"),
    ("2.0+deadbeef", "!=2"),
    ("2.0+deadbeef", "!=2.0"),
    ("2.0+deadbeef", "!=2.0.0"),
    ("2.0+deadbeef", "!=2+deadbeef"),
    ("2.0+deadbeef", "!=2.0+deadbeef"),
    ("2.0+deadbeef", "!=2.0.0+deadbeef"),
    ("2.0+deadbeef.0", "!=2.0.0+deadbeef.00"),
    # Test the in-equality operation with a prefix
    ("2.dev1", "!=2.*"),
    ("2a1", "!=2.*"),
    ("2a1.post1", "!=2.*"),
    ("2b1", "!=2.*"),
    ("2b1.dev1", "!=2.*"),
    ("2c1", "!=2.*"),
    ("2c1.post1.dev1", "!=2.*"),
    ("2c1.post1.dev1", "!=2.0.*"),
    ("2rc1", "!=2.*"),
    ("2rc1", "!=2.0.*"),
    ("2", "!=2.*"),
    ("2", "!=2.0.*"),
    ("2", "!=2.0.0.*"),
    ("2.0", "!=2.*"),
    ("2.0.0", "!=2.*"),
    ("2.0.0.0", "!=2.0.*"),
    # Test the greater than equal operation
    ("2.0.dev1", ">=2"),
    ("2.0a1", ">=2"),
    ("2.0a1.dev1", ">=2"),
    ("2.0b1", ">=2"),
    ("2.0b1.post1", ">=2"),
    ("2.0c1", ">=2"),
    ("2.0c1.post1.dev1", ">=2"),
    ("2.0rc1", ">=2"),
    ("1", ">=2"),
    # Test the less than equal operation
    ("2.0.post1", "<=2"),
    ("2.0.post1.dev1", "<=2"),
    ("3", "<=2"),
    # Test the greater than operation
    ("1", ">2"),
    ("2.0.dev1", ">2"),
    ("2.0a1", ">2"),
    ("2.0a1.post1", ">2"),
    ("2.0b1", ">2"),
    ("2.0b1.dev1", ">2"),
    ("2.0c1", ">2"),
    ("2.0c1.post1.dev1", ">2"),
    ("2.0rc1", ">2"),
    ("2.0", ">2"),
    ("2.0.post1", ">2"),
    ("2.0.post1.dev1", ">2"),
    ("2.0+local.version", ">2"),
    ("4.1.0a2.dev1234+local", ">4.1.0a2.dev1234"),
    # Test local versions with pre/dev/post segments and >
    # (local variant of the exact spec version must not match)
    ("1.0a1+local", ">1.0a1"),
    ("1.0b1+local", ">1.0b1"),
    ("1.0rc1+local", ">1.0rc1"),
    ("1.0.post1+local", ">1.0.post1"),
    ("1.0.dev1+local", ">1.0.dev1"),
    ("1.0a1.dev1+local", ">1.0a1.dev1"),
    ("1.0.post1.dev1+local", ">1.0.post1.dev1"),
    # Test the less than operation
    ("2.0.dev1", "<2"),
    ("2.0a1", "<2"),
    ("2.0a1.post1", "<2"),
    ("2.0b1", "<2"),
    ("2.0b2.dev1", "<2"),
    ("2.0c1", "<2"),
    ("2.0c1.post1.dev1", "<2"),
    ("2.0rc1", "<2"),
    ("2.0", "<2"),
    ("2.post1", "<2"),
    ("2.post1.dev1", "<2"),
    ("3", "<2"),
    # Test the compatibility operation
    ("2.0", "~=1.0"),
    ("1.1.0", "~=1.0.0"),
    ("1.1.post1", "~=1.0.0"),
    # Test that epochs are handled sanely
    ("1.0", "~=2!1.0"),
    ("2!1.0", "~=1.0"),
    ("2!1.0", "==1.0"),
    ("1.0", "==2!1.0"),
    ("2!1.0", "==1.0.0.*"),
    ("1.0", "==2!1.0.0.*"),
    ("2!1.0", "==1.*"),
    ("1.0", "==2!1.*"),
    ("2!1.0", "!=2!1.0"),
]

def _test_specifier_contains_upstream_impl(env, _target):
    for version, spec_str in _UPSTREAM_SPECIFIERS_PASS:
        spec = specifiers.parse(spec_str)
        env.expect.that_bool(specifiers.contains(spec, version)).equals(True)

    for version, spec_str in _UPSTREAM_SPECIFIERS_FAIL:
        spec = specifiers.parse(spec_str)
        env.expect.that_bool(specifiers.contains(spec, version)).equals(False)

def _test_specifier_contains_upstream(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_specifier_contains_upstream_impl)

def _test_specifier_contains(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_specifier_contains_impl)

def _test_specifier_set_contains_impl(env, _target):
    spec_set = specifiers.parse_set(">=1.0, <2.0")
    env.expect.that_bool(specifiers.set_contains(spec_set, "1.5")).equals(True)
    env.expect.that_bool(specifiers.set_contains(spec_set, "0.9")).equals(False)
    env.expect.that_bool(specifiers.set_contains(spec_set, "2.0")).equals(False)

def _test_specifier_set_contains(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_specifier_set_contains_impl)

def _test_contains_invalid_version_impl(env, _target):
    # packaging returns False (instead of raising) for candidates that are not
    # valid PEP 440 versions. Only === can match them, as a plain string.
    for spec_str in [">=1.0", "==1.0", "==1.*", "!=1.0", "!=1.*", "~=1.0", "<1.0", ">0", "<=1.0"]:
        spec = specifiers.parse(spec_str)
        spec_set = specifiers.parse_set(spec_str)
        for version in ["foo", "1.0-foo", "", "1.0+", "1.0.*", "1.0 a1", "v"]:
            env.expect.that_bool(specifiers.contains(spec, version)).equals(False)
            env.expect.that_bool(specifiers.set_contains(spec_set, version)).equals(False)

    env.expect.that_bool(specifiers.contains(specifiers.parse("===foo"), "FOO")).equals(True)
    env.expect.that_bool(specifiers.set_contains(specifiers.parse_set("===foo"), "FOO")).equals(True)
    env.expect.that_bool(specifiers.set_contains(specifiers.parse_set("===foo,>=1"), "foo")).equals(False)
    env.expect.that_bool(specifiers.set_contains(specifiers.parse_set(">=1,===foo"), "foo")).equals(False)
    env.expect.that_bool(specifiers.set_contains(specifiers.parse_set(""), "foo")).equals(True)

    # Surrounding whitespace is ignored when parsing the candidate, but === compares the raw string.
    env.expect.that_bool(specifiers.contains(specifiers.parse(">=1.0"), "1.0 ")).equals(True)
    env.expect.that_bool(specifiers.contains(specifiers.parse("==1.0"), "\t1.0\n")).equals(True)
    env.expect.that_bool(specifiers.contains(specifiers.parse("===1.0"), "1.0 ")).equals(False)

def _test_contains_invalid_version(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_contains_invalid_version_impl)

def _test_compatible_release_impl(env, _target):
    # ~=X.Y.Z means >=X.Y.Z, ==X.Y.*, and ==X.Y.* zero-pads shorter candidates.
    for version, spec_str in [
        ("1", "~=1.0.0"),
        ("1.0", "~=1.0.0.0"),
        ("1.0.post1", "~=1.0.0.0"),
        ("1.0+local", "~=1.0.0.0"),
        ("v1.0", "~=1.0.0.0"),
        ("1.00", "~=1.0.0.0"),
        ("1.0.post0.dev0", "~=1.0.0.0"),
        ("2", "~=2.0.0"),
        ("1.0.1", "~=1.0.0"),
    ]:
        env.expect.that_bool(specifiers.contains(specifiers.parse(spec_str), version)).equals(True)
        env.expect.that_bool(specifiers.set_contains(specifiers.parse_set(spec_str), version)).equals(True)
    for version, spec_str in [
        ("1.1", "~=1.0.0"),
        ("0.9", "~=1.0.0"),
        ("1.0.0.dev0", "~=1.0.0.0"),
        ("1!1", "~=1.0.0"),
    ]:
        env.expect.that_bool(specifiers.contains(specifiers.parse(spec_str), version)).equals(False)
        env.expect.that_bool(specifiers.set_contains(specifiers.parse_set(spec_str), version)).equals(False)

    # Intentional divergence: the prefix comes from the normalized spec version,
    # as PEP 440 says. packaging 26.2 derives it from the raw string, so it
    # treats ~=1.0c1 as ==1.0.* and ~=v1.0 as matching nothing.
    for version, spec_str in [
        ("1.1", "~=1.0c1"),
        ("1.5", "~=1.0.c1"),
        ("1.5", "~=1.0.pre1"),
        ("1.5", "~=1.0.preview1"),
        ("1.1", "~=1.0.r1"),
        ("1.1", "~=1.0.rev1"),
        ("1.1", "~=1.0.RC1"),
        ("1.1", "~=1.0.POST1"),
        ("1.1", "~=1.0.DEV1"),
        ("1.1", "~=1.0.A1"),
        ("1.0.5", "~=1.0.0c1"),
        ("1.1", "~=v1.0"),
        ("1.1", "~=V1.0"),
        ("2.2.5", "~=v2.2.0"),
    ]:
        env.expect.that_bool(specifiers.contains(specifiers.parse(spec_str), version)).equals(True)
    env.expect.that_bool(specifiers.contains(specifiers.parse("~=1.0c1"), "2.0")).equals(False)
    env.expect.that_bool(specifiers.contains(specifiers.parse("~=v1.0"), "2.0")).equals(False)

def _test_compatible_release(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_compatible_release_impl)

def _spec_tuples(spec_set):
    return [(s.operator, s.version) for s in spec_set.specs]

def _test_parse_set_empty_items_impl(env, _target):
    # SpecifierSet skips empty and whitespace-only items.
    for spec_set_str, expected in [
        (">=1.0,", [(">=", "1.0")]),
        (",>=1.0", [(">=", "1.0")]),
        (">=1.0,<2,", [(">=", "1.0"), ("<", "2")]),
        (">=1.0,,<2", [(">=", "1.0"), ("<", "2")]),
        (" >=1.0 , <2 ", [(">=", "1.0"), ("<", "2")]),
        ("", []),
        (" ", []),
        ("\t", []),
        (",", []),
        (" , ", []),
        (",,", []),
        ("\302\240,>=1", [(">=", "1")]),
    ]:
        env.expect.that_collection(_spec_tuples(specifiers.parse_set(spec_set_str))).contains_exactly(expected).in_order()

    env.expect.that_bool(specifiers.set_contains(specifiers.parse_set(" , "), "1.0")).equals(True)

def _test_parse_set_empty_items(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_set_empty_items_impl)

def _parse_subject_impl(ctx):
    if ctx.attr.kind == "set":
        specifiers.parse_set(ctx.attr.spec)
    else:
        specifiers.parse(ctx.attr.spec)
    return []

_parse_subject = rule(
    implementation = _parse_subject_impl,
    attrs = {"kind": attr.string(), "spec": attr.string()},
)

def _invalid_specifier_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(matching.contains("Invalid specifier"))

# (kind, input) pairs that packaging rejects with InvalidSpecifier.
_INVALID_SPECIFIERS = [
    ("set", ">=1.0;"),
    ("set", ">=1.0 <2.0"),
    ("set", ">=1.0,foo"),
    ("spec", ""),
    ("spec", "=="),
    ("spec", "=1"),
    ("spec", "~1.0"),
    ("spec", "1.0"),
    ("spec", "~=1"),
    ("spec", "~=1.*"),
    ("spec", "~=1.0.*"),
    ("spec", "~=1.0+local"),
    ("spec", "==1.*.1"),
    ("spec", ">=1.0.*"),
    ("spec", "==1.0a1.*"),
    ("spec", "==1.0+local.*"),
    ("spec", "==1.0.post1.*"),
    ("spec", "==1.0 .*"),
    ("spec", "==1.0\302\240.*"),
    ("spec", "==1.0+"),
    ("spec", "<=1.0+local"),
    ("spec", "<1.0+local"),
    ("spec", ">=1.0+local"),
    ("spec", "> =1.0"),
    ("spec", "<==1"),
    ("spec", ">=foo"),
    ("spec", "===foo bar"),
    ("spec", "===foo\tbar"),
    ("spec", "===foo\034bar"),
    ("spec", "===foo;"),
    ("spec", "===foo)"),
    ("spec", "===foo\302\240bar"),
    ("spec", "===foo\302\205bar"),
    ("spec", "===a\342\200\203b"),
    ("spec", "===a\343\200\200b"),
]

def _test_parse_specifier_edge_cases_impl(env, _target):
    for spec_str, operator, version in [
        ("====1", "===", "=1"),
        ("===", "===", ""),
        ("=== foo", "===", "foo"),
        ("===a\342\200\213b", "===", "a\342\200\213b"),  # U+200B is not whitespace
        ("==\302\2401.0", "==", "1.0"),
        ("\302\240>=1.0\302\240", ">=", "1.0"),
        ("\t~= 1.0\n", "~=", "1.0"),
        ("== v1.0.*", "==", "v1.0.*"),
        ("!=1!1.0.*", "!=", "1!1.0.*"),
        ("==1.0+Local.1", "==", "1.0+Local.1"),
        ("<1.0.post1.dev1", "<", "1.0.post1.dev1"),
    ]:
        spec = specifiers.parse(spec_str)
        env.expect.that_str(spec.operator).equals(operator)
        env.expect.that_str(spec.version).equals(version)

def _test_parse_specifier_edge_cases(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_specifier_edge_cases_impl)

def _test_parsed_version_impl(env, _target):
    spec = specifiers.parse(">=1.0rc1")
    env.expect.that_collection(spec.parsed_version.release).contains_exactly([1, 0]).in_order()
    env.expect.that_collection(spec.parsed_version.pre).contains_exactly(["rc", 1]).in_order()

    spec = specifiers.parse("==1!2.3.*")
    env.expect.that_str(spec.version).equals("1!2.3.*")
    env.expect.that_int(spec.parsed_version.epoch).equals(1)
    env.expect.that_collection(spec.parsed_version.release).contains_exactly([2, 3]).in_order()

    env.expect.that_bool(specifiers.parse("===foo").parsed_version == None).equals(True)

    # Structs that weren't created by parse() still work.
    for spec_str, version, expected in [
        (">=1.0rc1", "1.0", True),
        ("==1.*", "1.5", True),
        ("~=1.4.5", "1.5", False),
        ("===Foo", "foo", True),
    ]:
        parsed = specifiers.parse(spec_str)
        spec = struct(operator = parsed.operator, version = parsed.version)
        env.expect.that_bool(specifiers.contains(spec, version)).equals(expected)
        env.expect.that_bool(specifiers.set_contains(struct(specs = [spec]), version)).equals(expected)

def _test_parsed_version(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parsed_version_impl)

def _test_exclusive_ordered_impl(env, _target):
    for spec_str, version, expected in [
        (">1.0a1", "1.0a1+local", False),
        (">1.0a1", "1.0a2+local", True),
        (">1.0", "1.0.post1", False),
        (">1.0", "1.0.post1+local", False),
        (">1.0", "1.0+local", False),
        (">1.0", "1.0.1+local", True),
        (">1.0.post1", "1.0.post2", True),
        (">1.0.post1", "1.0.post1+local", False),
        (">1.0a1", "1.0a1.post1", False),
        (">1.0a1.post1", "1.0a1.post2", True),
        ("<1.0", "1.0.dev0", False),
        ("<1.0", "1.0a1+local", False),
        ("<1.0", "0.9+local", True),
        ("<1.0", "0.9.dev0", True),
        ("<1.0.post1", "1.0.post1.dev0", False),
        ("<1.0.post1", "1.0", True),
        ("<1.0rc1", "1.0a1", True),
        ("<1.0rc1", "1.0rc1.dev1", True),
        ("<1!1.0", "1.0", True),
    ]:
        env.expect.that_bool(specifiers.contains(specifiers.parse(spec_str), version)).equals(expected)

def _test_exclusive_ordered(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_exclusive_ordered_impl)

# Expected values below come from packaging 26.2.
_PRE_OPTS = [None, True, False]

def _test_prereleases_contains_impl(env, _target):
    for spec_str, version, expected in [
        (">=1.2.3", "1.3.0a1", [True, True, False]),
        ("!=1.0", "1.1a1", [True, True, False]),
        ("===1.0a1", "1.0a1", [True, True, False]),
        ("===foo", "foo", [True, True, True]),
        ("==1.*", "1.5a1", [True, True, False]),
        (">=1.2.3", "1.3.0", [True, True, True]),
        (">=1.2.3", "1.0a1", [False, False, False]),
    ]:
        spec = specifiers.parse(spec_str)
        for p, e in zip(_PRE_OPTS, expected):
            env.expect.that_bool(specifiers.contains(spec, version, prereleases = p)).equals(e)
            env.expect.that_bool(specifiers.contains(spec, version_mod.parse(version) if version != "foo" else version, prereleases = p)).equals(e)

    for spec_set_str, version, expected, installed in [
        (">=1.2.3", "1.3.0a1", [True, True, False], True),
        ("", "2.0a1", [True, True, False], True),
        ("", "foo", [True, True, True], True),
        (">=1.0,!=1.5", "1.6a1", [True, True, False], True),
        ("===foo", "foo", [True, True, True], True),
        ("===1.0a1", "1.0a1", [True, True, False], True),
        (">=1.0,!=1.5", "1.5", [False, False, False], False),
    ]:
        spec_set = specifiers.parse_set(spec_set_str)
        for p, e in zip(_PRE_OPTS, expected):
            env.expect.that_bool(specifiers.set_contains(spec_set, version, prereleases = p)).equals(e)
        env.expect.that_bool(specifiers.set_contains(spec_set, version, prereleases = False, installed = True)).equals(installed)

def _test_prereleases_contains(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_prereleases_contains_impl)

def _test_prereleases_property_impl(env, _target):
    for spec_str, expected in [
        (">=1.0", False),
        (">=1.0a1", True),
        ("!=1.0a1", False),
        ("==1.*", False),
        ("===foo", None),
        ("===1.0a1", True),
        ("===1.0", False),
        ("~=1.0rc1", True),
        ("<2.0.dev1", True),
        ("==1.0+local", False),
    ]:
        env.expect.that_bool(specifiers.prereleases(specifiers.parse(spec_str)) == expected).equals(True)
    for spec_set_str, expected in [
        ("", None),
        (">=1.0", None),
        (">=1.0,<2.0a1", True),
        ("!=1.0a1", None),
    ]:
        env.expect.that_bool(specifiers.set_prereleases(specifiers.parse_set(spec_set_str)) == expected).equals(True)

def _test_prereleases_property(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_prereleases_property_impl)

def _test_filter_impl(env, _target):
    for spec_str, versions, expected in [
        (">=1.2.3", ["1.2", "1.3", "1.5a1"], [["1.3"], ["1.3", "1.5a1"], ["1.3"]]),
        (">=1.2.3", ["1.2", "1.5a1"], [["1.5a1"], ["1.5a1"], []]),
        (">=1.0a1", ["1.0a2", "1.0", "2.0b1"], [["1.0a2", "1.0", "2.0b1"], ["1.0a2", "1.0", "2.0b1"], ["1.0"]]),
        ("!=1.1", ["1.0a1", "1.2a1"], [["1.0a1", "1.2a1"], ["1.0a1", "1.2a1"], []]),
        ("!=1.1", ["1.0a1", "1.2"], [["1.2"], ["1.0a1", "1.2"], ["1.2"]]),
        ("===foo", ["foo", "FOO", "1.0"], [["foo", "FOO"], ["foo", "FOO"], ["foo", "FOO"]]),
        ("===1.0a1", ["1.0a1", "1.0A1"], [["1.0a1", "1.0A1"], ["1.0a1", "1.0A1"], []]),
    ]:
        spec = specifiers.parse(spec_str)
        for p, e in zip(_PRE_OPTS, expected):
            env.expect.that_collection(specifiers.filter(spec, versions, prereleases = p)).contains_exactly(e).in_order()

    for spec_set_str, versions, expected in [
        (">=1.2.3", ["1.2", "1.3", "1.5a1"], [["1.3"], ["1.3", "1.5a1"], ["1.3"]]),
        (">=1.2.3", ["1.2", "1.5a1"], [["1.5a1"], ["1.5a1"], []]),
        ("", ["1.3", "1.5a1"], [["1.3"], ["1.3", "1.5a1"], ["1.3"]]),
        ("", ["1.5a1"], [["1.5a1"], ["1.5a1"], []]),
        ("", ["foo", "1.5a1"], [["foo", "1.5a1"], ["foo", "1.5a1"], ["foo"]]),
        ("", ["1.5a1", "foo", "1.0"], [["foo", "1.0"], ["1.5a1", "foo", "1.0"], ["foo", "1.0"]]),
        (">=1.0,<2.0a1", ["1.5", "2.0a0", "1.9b1"], [["1.5", "2.0a0", "1.9b1"], ["1.5", "2.0a0", "1.9b1"], ["1.5"]]),
        (">=1.0,!=1.5", ["1.5", "1.6a1", "1.4"], [["1.4"], ["1.6a1", "1.4"], ["1.4"]]),
        ("===foo", ["foo", "1.0"], [["foo"], ["foo"], ["foo"]]),
        ("===foo,>=1", ["foo", "1.0"], [[], [], []]),
    ]:
        spec_set = specifiers.parse_set(spec_set_str)
        for p, e in zip(_PRE_OPTS, expected):
            env.expect.that_collection(specifiers.set_filter(spec_set, versions, prereleases = p)).contains_exactly(e).in_order()

    # Parsed versions are accepted too, and returned as given.
    parsed = [version_mod.parse(v) for v in ["1.2", "1.3", "1.5a1"]]
    env.expect.that_collection(specifiers.set_filter(specifiers.parse_set(">=1.2.3"), parsed)).contains_exactly([parsed[1]])
    env.expect.that_collection(specifiers.filter(specifiers.parse("===1.5a1"), parsed)).contains_exactly([parsed[2]])

def _test_filter(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_filter_impl)

def specifiers_test_suite(name):
    """Sets up the specifier tests.

    Args:
        name: the name of the test suite
    """
    test_suite(
        name = name + "_standard",
        tests = [
            _test_specifier_basic,
            _test_specifier_contains,
            _test_specifier_set_contains,
            _test_specifier_contains_upstream,
            _test_contains_invalid_version,
            _test_compatible_release,
            _test_parse_set_empty_items,
            _test_parse_specifier_edge_cases,
            _test_parsed_version,
            _test_exclusive_ordered,
            _test_prereleases_contains,
            _test_prereleases_property,
            _test_filter,
        ],
    )

    invalid_test_names = []

    # buildifier: disable=enumerate
    for i, (kind, spec) in enumerate(_INVALID_SPECIFIERS):
        test_name = name + "_invalid_{}".format(i)
        util.helper_target(_parse_subject, name = test_name + "_subject", kind = kind, spec = spec)
        analysis_test(name = test_name, target = test_name + "_subject", expect_failure = True, impl = _invalid_specifier_test_impl)
        invalid_test_names.append(test_name)

    native.test_suite(
        name = name,
        tests = [":" + name + "_standard"] + [":" + n for n in invalid_test_names],
    )
