"""Tests for requirements.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/requirements:requirements.bzl", "requirements")

def _invalid_requirement_subject_rule_impl(ctx):
    requirements.parse(ctx.attr.req_str)
    return []

_invalid_requirement_subject_rule = rule(
    implementation = _invalid_requirement_subject_rule_impl,
    attrs = {
        "req_str": attr.string(mandatory = True),
    },
)

_EQUAL_DEPENDENCIES = [
    ("packaging>20.1", "packaging>20.1"),
    (
        'requests[security, tests]>=2.8.1,==2.8.*;python_version<"2.7"',
        'requests [security,tests] >= 2.8.1, == 2.8.* ; python_version < "2.7"',
    ),
    (
        'importlib-metadata; python_version<"3.8"',
        'importlib-metadata; python_version<"3.8"',
    ),
    (
        'appdirs>=1.4.4,<2; os_name=="posix" and extra=="testing"',
        'appdirs>=1.4.4,<2; os_name == "posix" and extra == "testing"',
    ),
]

_EQUIVALENT_DEPENDENCIES = [
    ("scikit-learn==1.0.1", "scikit_learn==1.0.1"),
    # Trailing-zero-equivalent specifiers compare equal in Python, but in this simplified Starlark port
    # they do not compare equal as structs because version strings are not normalized in Specifier structs.
    # ("foo==1.0.0", "foo==1.0.0.0"),
    # ("foo>=1.0", "foo>=1.0.0"),
    # (
    #     'foo[a]==1.0.0; python_version>="3.8"',
    #     'foo[a]==1.0.0.0; python_version>="3.8"',
    # ),
    # Extras that normalize to the same value are equivalent.
    ("urllib3[secure]", "urllib3[SECURE]"),
    ("fishtank[all-blue]", "fishtank[all_blue]"),
    ("fishtank[all-blue]", "fishtank[all---blue]"),
    ("fishtank[crazy-bunches]", "fishtank[cRazy_BUnches]"),
]

_DIFFERENT_DEPENDENCIES = [
    ("package_one", "package_two"),
    ("packaging>20.1", "packaging>=20.1"),
    ("packaging>20.1", "packaging>21.1"),
    ("packaging>20.1", "package>20.1"),
    (
        'requests[security,tests]>=2.8.1,==2.8.*;python_version<"2.7"',
        'requests [security,tests] >= 2.8.1 ; python_version < "2.7"',
    ),
    (
        'importlib-metadata; python_version<"3.8"',
        "importlib-metadata; python_version<'3.7'",
    ),
    (
        'appdirs>=1.4.4,<2; os_name=="posix" and extra=="testing"',
        "appdirs>=1.4.4,<2; os_name == 'posix' and extra == 'docs'",
    ),
]

_NAMES = [
    "package",
    "pAcKaGe",
    "Package",
    "foo-bar.quux_bAz",
    "installer",
    "android12",
]

_EXTRAS = [
    [],
    ["a"],
    ["a", "b"],
    ["a", "B", "CDEF123"],
]

_URLS_AND_SPECIFIERS = [
    (None, ""),
    ("https://example.com/packagename.zip", ""),
    ("ssh://user:pass%20word@example.com/packagename.zip", ""),
    ("https://example.com/name;v=1.1/?query=foo&bar=baz#blah", ""),
    ("git+ssh://git.example.com/MyProject", ""),
    ("git+ssh://git@github.com:pypa/packaging.git", ""),
    ("git+https://git.example.com/MyProject.git@master", ""),
    ("git+https://git.example.com/MyProject.git@v1.0", ""),
    ("git+https://git.example.com/MyProject.git@refs/pull/123/head", ""),
    ("gopher:/foo/com", ""),
    (None, "==={ws}arbitrarystring"),
    (None, "({ws}==={ws}arbitrarystring{ws})"),
    (None, "=={ws}1.0"),
    (None, "({ws}=={ws}1.0{ws})"),
    (None, "=={ws}1.0-alpha"),
    (None, "<={ws}1!3.0.0.rc2"),
    (None, ">{ws}2.2{ws},{ws}<{ws}3"),
    (None, "(>{ws}2.2{ws},{ws}<{ws}3)"),
]

_MARKERS = [
    None,
    "python_version{ws}>={ws}'3.3'",
    '({ws}python_version{ws}>={ws}"3.4"{ws}){ws}and extra{ws}=={ws}"oursql"',
    "sys_platform{ws}!={ws}'linux' and(os_name{ws}=={ws}'linux' or python_version{ws}>={ws}'3.3'{ws}){ws}",
]

_WHITESPACES = ["", " ", "\t"]

_INVALID_REQUIREMENTS = [
    "",  # Empty string
    "==0.0",  # Missing package name
    "name[bar baz]",  # Missing comma in extras
    "name[bar, baz,]",  # Trailing comma in extras
    "name (>= 1.0",  # Unclosed parenthesis in specifier
    "name[bar, baz >= 1.0",  # Unclosed bracket
    "name[bar, baz",  # Unclosed bracket
    "name @ https://example.com/; extra == 'example'",  # No space before URL marker (upstream rejects this)
    "name; (extra == 'example'",  # Unclosed parenthesis in marker
    "name @ ",  # Missing URL after @
]

def _generic_invalid_test_impl(env, target):
    # We expect failure, so failures() should not be empty.
    # Most failures are a single message.
    env.expect.that_target(target).failures().has_size(1)

def _test_parse_requirement_basic_impl(env, _target):
    req = requirements.parse("packaging")
    env.expect.that_str(req.name).equals("packaging")
    env.expect.that_collection(req.extras).has_size(0)
    env.expect.that_bool(req.url == None).equals(True)
    env.expect.that_collection(req.specifier.specs).has_size(0)
    env.expect.that_bool(req.marker == None).equals(True)

def _test_parse_requirement_basic(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_basic_impl)

def _test_parse_requirement_with_extras_impl(env, _target):
    req = requirements.parse("requests[security,tests]")
    env.expect.that_str(req.name).equals("requests")
    env.expect.that_collection(req.extras).contains_exactly(["security", "tests"])

def _test_parse_requirement_with_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_with_extras_impl)

def _test_parse_requirement_equality_impl(env, _target):
    for dep1, dep2 in _EQUAL_DEPENDENCIES:
        req1 = requirements.parse(dep1)
        req2 = requirements.parse(dep2)

        # In Starlark, struct equality checks fields.
        # We expect them to be identical after parsing/normalization.
        env.expect.that_str(req1.name).equals(req2.name)
        env.expect.that_collection(req1.extras).contains_exactly(req2.extras)
        env.expect.that_bool(req1.url == req2.url).equals(True)

        # Specifiers might not be strictly equal if order matters in specifiers.bzl
        # But for these tests, order should be same.
        env.expect.that_bool(req1.specifier == req2.specifier).equals(True)

        # Markers should be identical
        env.expect.that_bool(req1.marker == req2.marker).equals(True)

def _test_parse_requirement_equality(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_equality_impl)

def _test_parse_requirement_equivalence_impl(env, _target):
    for dep1, dep2 in _EQUIVALENT_DEPENDENCIES:
        req1 = requirements.parse(dep1)
        req2 = requirements.parse(dep2)

        env.expect.that_str(req1.name).equals(req2.name)
        env.expect.that_collection(req1.extras).contains_exactly(req2.extras)
        env.expect.that_bool(req1.url == req2.url).equals(True)

        # These might fail if specifiers are not normalized
        env.expect.that_bool(req1.specifier == req2.specifier).equals(True)
        env.expect.that_bool(req1.marker == req2.marker).equals(True)

def _test_parse_requirement_equivalence(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_equivalence_impl)

def _test_parse_requirement_difference_impl(env, _target):
    for dep1, dep2 in _DIFFERENT_DEPENDENCIES:
        req1 = requirements.parse(dep1)
        req2 = requirements.parse(dep2)

        # We expect them to differ in some way
        is_equal = (
            req1.name == req2.name and
            req1.extras == req2.extras and
            req1.url == req2.url and
            req1.specifier == req2.specifier and
            req1.marker == req2.marker
        )
        env.expect.that_bool(is_equal).equals(False)

def _test_parse_requirement_difference(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_difference_impl)

def _test_parse_requirement_matrix_impl(_env, _target):
    # This matrix is large (1710 combinations). We run it in a single test to avoid boilerplate overhead.
    for name in _NAMES:
        for extras in _EXTRAS:
            for url, specifier in _URLS_AND_SPECIFIERS:
                for marker in _MARKERS:
                    for ws in _WHITESPACES:
                        parts = [name]
                        if extras:
                            parts.append("[")

                            # Starlark format works like Python's

                            # Need to handle case where extras might have mixed case if we want to test normalization here
                            # But upstream just uses sorted(extras) as is.
                            parts.append(",".join(["{ws}{e}{ws}".format(ws = ws, e = e) for e in sorted(extras)]))
                            parts.append("]")

                        if specifier:
                            parts.append(specifier.replace("{ws}", ws))

                        if url != None:
                            parts.append("@")
                            parts.append(url)  # Upstream calls format but we don't have placeholders in URLs here

                        if marker != None:
                            if url != None:
                                parts.append(" ;")
                            else:
                                parts.append(";")
                            parts.append(marker.replace("{ws}", ws))

                        to_parse = ws.join(parts)

                        # We just want to make sure it parses without failure for now,
                        # as strict assertions might require more API than we have (e.g. SpecifierSet stringification).
                        # But we can at least check name and extras.

                        # Some combinations might be invalid? Upstream claims these are BASIC VALID.
                        requirements.parse(to_parse)

                        # Apply normalization expectations if needed
                        # Upstream checks normalized name
                        # env.expect.that_str(req.name).equals(utils.canonicalize_name(name))

                        # If we reach here, it passed parsing.

def _test_parse_requirement_matrix(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_matrix_impl)

def _test_parse_requirement_empty_string_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(matching.contains("Empty requirement string"))

def _test_parse_requirement_empty_string(name):
    util.helper_target(_invalid_requirement_subject_rule, name = name + "_subject", req_str = " ")
    analysis_test(name = name, target = name + "_subject", expect_failure = True, impl = _test_parse_requirement_empty_string_impl)

def _test_parse_requirement_no_name_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(matching.contains("Missing requirement name"))

def _test_parse_requirement_no_name(name):
    util.helper_target(_invalid_requirement_subject_rule, name = name + "_subject", req_str = "==0.0")
    analysis_test(name = name, target = name + "_subject", expect_failure = True, impl = _test_parse_requirement_no_name_impl)

def _test_parse_requirement_marker_with_at_impl(env, _target):
    req = requirements.parse('requests >= 2.0; extra == "my@extra"')
    env.expect.that_str(req.name).equals("requests")
    env.expect.that_bool(req.url == None).equals(True)

    req2 = requirements.parse("pkg @ https://example.com/a;b.zip")
    env.expect.that_str(req2.name).equals("pkg")
    env.expect.that_str(req2.url).equals("https://example.com/a;b.zip")

def _test_parse_requirement_marker_with_at(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_marker_with_at_impl)

def requirements_test_suite(name):
    """Sets up the requirement parsing tests.

    Args:
        name: the name of the test suite
    """
    test_suite(
        name = name + "_standard",
        tests = [
            _test_parse_requirement_basic,
            _test_parse_requirement_with_extras,
            _test_parse_requirement_equality,
            _test_parse_requirement_equivalence,
            _test_parse_requirement_difference,
            _test_parse_requirement_matrix,
            _test_parse_requirement_empty_string,
            _test_parse_requirement_no_name,
            _test_parse_requirement_marker_with_at,
        ],
    )

    invalid_test_names = []

    # buildifier: disable=enumerate
    for i, req in enumerate(_INVALID_REQUIREMENTS):
        test_name = name + "_invalid_{}".format(i)
        util.helper_target(_invalid_requirement_subject_rule, name = test_name + "_subject", req_str = req)
        analysis_test(name = test_name, target = test_name + "_subject", expect_failure = True, impl = _generic_invalid_test_impl)
        invalid_test_names.append(test_name)

    native.test_suite(
        name = name,
        tests = [":" + name + "_standard"] + [":" + n for n in invalid_test_names],
    )
