"""Conformance tests that use the cases from the `packaging` project.

The cases in `//pypackaging/tests/packaging_cases` are generated from the
test-suite of `packaging` and the expected values are computed by `packaging`
itself, see `conformance/README.md`.
"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("//pypackaging/private/markers:markers.bzl", "markers")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/specifiers:specifiers.bzl", "specifiers", "try_parse_specifier")
load("//pypackaging/private/tags:tags.bzl", "tags")
load("//pypackaging/private/version:version.bzl", "version")
load(
    "//pypackaging/tests/packaging_cases:marker_cases.bzl",
    "EVALUATE_CASES",
    "INVALID_MARKERS",
    "LOGIC_CASES",
    "MARKER_ENV",
    "MARKER_TABLE",
    "SET_ENV_VALUE",
    "SET_TABLE",
    "STR_CASES",
)
load("//pypackaging/tests/packaging_cases:tags_cases.bzl", "GET_SUPPORTED_CASES")
load(
    "//pypackaging/tests/packaging_cases:version_cases.bzl",
    "CONTAINS_CASES",
    "FILTER_CASES",
    "INVALID_SPECIFIERS",
    "INVALID_VERSIONS",
    "MATRIX",
    "MATRIX_VERSIONS",
    "NORMALIZED_VERSIONS",
    "ORDERED_VERSIONS",
    "SET_CONTAINS_CASES",
    "SET_FILTER_CASES",
    "SPECIFIER_CASES",
)

_tests = []

def _expect_no_failures(env, failures):
    env.expect.that_collection(failures).contains_exactly([])

# Versions

def _conformance_invalid_versions(env):
    _expect_no_failures(env, [v for v in INVALID_VERSIONS if version.try_parse(v) != None])

_tests.append(_conformance_invalid_versions)

def _conformance_normalized_versions(env):
    failures = []
    for input, want in NORMALIZED_VERSIONS:
        got = version.to_string(version.parse(input))
        if got != want:
            failures.append("{}: got {}, want {}".format(input, got, want))

    _expect_no_failures(env, failures)

_tests.append(_conformance_normalized_versions)

def _conformance_ordering(env):
    keys = [version.parse(v).key for v in ORDERED_VERSIONS]
    failures = []
    for i, lower in enumerate(keys):
        for j in range(i + 1, len(keys)):
            if not lower < keys[j]:
                failures.append("{} < {}".format(ORDERED_VERSIONS[i], ORDERED_VERSIONS[j]))

    _expect_no_failures(env, failures)

_tests.append(_conformance_ordering)

# Specifiers

def _conformance_invalid_specifiers(env):
    _expect_no_failures(env, [s for s in INVALID_SPECIFIERS if try_parse_specifier(s) != None])

_tests.append(_conformance_invalid_specifiers)

def _conformance_specifiers(env):
    failures = []
    for candidate, spec, want in SPECIFIER_CASES:
        if specifiers.contains(specifiers.parse(spec), candidate, prereleases = True) != want:
            failures.append("{} in {}: want {}".format(candidate, spec, want))

    _expect_no_failures(env, failures)

_tests.append(_conformance_specifiers)

def _conformance_specifier_matrix(env):
    failures = []
    for spec, row in MATRIX:
        parsed = specifiers.parse(spec)
        for i, candidate in enumerate(MATRIX_VERSIONS):
            want = row[i] == "T"
            if specifiers.contains(parsed, candidate, prereleases = True) != want:
                failures.append("{} in {}: want {}".format(candidate, spec, want))

    _expect_no_failures(env, failures)

_tests.append(_conformance_specifier_matrix)

def _contains_failures(cases, parse, contains):
    failures = []
    for spec, candidate, prereleases, installed, want in cases:
        kwargs = {} if installed == None else {"installed": installed}
        got = contains(parse(spec), candidate, prereleases = prereleases, **kwargs)
        if got != want:
            failures.append("{} in '{}' with prereleases={}, installed={}: want {}".format(
                candidate,
                spec,
                prereleases,
                installed,
                want,
            ))
    return failures

def _conformance_specifier_contains(env):
    _expect_no_failures(env, _contains_failures(CONTAINS_CASES, specifiers.parse, specifiers.contains))

_tests.append(_conformance_specifier_contains)

def _conformance_specifier_set_contains(env):
    _expect_no_failures(env, _contains_failures(SET_CONTAINS_CASES, specifiers.parse_set, specifiers.set_contains))

_tests.append(_conformance_specifier_set_contains)

def _filter_failures(cases, parse, filter):
    failures = []
    for spec, prereleases, candidates, want in cases:
        got = filter(parse(spec), candidates, prereleases = prereleases)
        if got != want:
            failures.append("filter {} with '{}' and prereleases={}: got {}, want {}".format(
                candidates,
                spec,
                prereleases,
                got,
                want,
            ))
    return failures

def _conformance_specifier_filter(env):
    _expect_no_failures(env, _filter_failures(FILTER_CASES, specifiers.parse, specifiers.filter))

_tests.append(_conformance_specifier_filter)

def _conformance_specifier_set_filter(env):
    _expect_no_failures(env, _filter_failures(SET_FILTER_CASES, specifiers.parse_set, specifiers.set_filter))

_tests.append(_conformance_specifier_set_filter)

# Markers

def _evaluate(marker, overrides = {}):
    return markers.evaluate(markers.parse(marker), dict(MARKER_ENV) | overrides)

def _conformance_marker_evaluate(env):
    failures = []
    for marker, overrides, want in EVALUATE_CASES:
        got = _evaluate(marker, json.decode(overrides))
        if got != want:
            failures.append("{} with {}: got {}, want {}".format(marker, overrides, got, want))

    _expect_no_failures(env, failures)

_tests.append(_conformance_marker_evaluate)

def _conformance_marker_str(env):
    failures = []
    for marker, want in STR_CASES:
        got = markers.to_string(markers.parse(marker))
        if got != want:
            failures.append("{}: got {}, want {}".format(marker, got, want))

    _expect_no_failures(env, failures)

_tests.append(_conformance_marker_str)

def _table_failures(table, overrides = {}):
    failures = []
    for variable, op, value, results in table:
        for marker, result in [
            ("{} {} \"{}\"".format(variable, op, value), results[0]),
            ("\"{}\" {} {}".format(value, op, variable), results[1]),
        ]:
            if result == "E":
                # It would fail and that cannot be caught.
                continue

            want = result == "T"
            got = _evaluate(marker, overrides)
            if got != want:
                failures.append("{}: got {}, want {}".format(marker, got, want))
    return failures

def _conformance_marker_table(env):
    _expect_no_failures(env, _table_failures(MARKER_TABLE))

_tests.append(_conformance_marker_table)

def _conformance_marker_set_table(env):
    _expect_no_failures(env, _table_failures(
        SET_TABLE,
        overrides = {
            "dependency_groups": SET_ENV_VALUE,
            "extras": SET_ENV_VALUE,
        },
    ))

_tests.append(_conformance_marker_set_table)

def _conformance_marker_logic(env):
    failures = []
    for marker, want in LOGIC_CASES:
        got = _evaluate(marker)
        if got != want:
            failures.append("{}: got {}, want {}".format(marker, got, want))

    _expect_no_failures(env, failures)

_tests.append(_conformance_marker_logic)

def _conformance_marker_evaluate_partial(env):
    # `packaging` does not have it, but what it has to be is defined by the
    # full evaluation: the result for a part of the environment is either the
    # same or it is a marker that evaluates to the same.
    failures = []
    cases = [(marker, json.decode(overrides), want) for marker, overrides, want in EVALUATE_CASES]
    cases.extend([(marker, {}, want) for marker, want in LOGIC_CASES])
    for marker, overrides, want in cases:
        full = dict(MARKER_ENV) | overrides
        parsed = markers.parse(marker)
        for name in full:
            for known in [
                {name: full[name]},
                {k: v for k, v in full.items() if k != name},
            ]:
                got = markers.evaluate_partial(parsed, known)
                if type(got) != "bool":
                    left = markers.to_string(got)
                    if markers.to_string(markers.parse(left)) != left:
                        failures.append("{} with {}: got {}, which is not normalized".format(marker, known, left))
                    got = markers.evaluate(got, full)
                if got != want:
                    failures.append("{} with {}: got {}, want {}".format(marker, known, got, want))
        if markers.evaluate_partial(parsed, full) != want:
            failures.append("{} with everything: want {}".format(marker, want))

    _expect_no_failures(env, failures)

_tests.append(_conformance_marker_evaluate_partial)

# Tags

def _conformance_get_supported(env):
    failures = []
    for version_, platforms, impl, abis, count, hash_, head in GET_SUPPORTED_CASES:
        case = "get_supported({}, {}, {}, {})".format(version_, platforms, impl, abis)
        got = tags.get_supported(version = version_, platforms = platforms, impl = impl, abis = abis)
        if got[:len(head)] != head:
            failures.append("{}: got the first tags {}, want {}".format(case, got[:len(head)], head))
        elif len(got) != count:
            failures.append("{}: got {} tags, want {}".format(case, len(got), count))
        elif hash(" ".join(got)) != hash_:
            failures.append("{}: the tags after the first {} are different".format(case, len(head)))

    _expect_no_failures(env, failures)

_tests.append(_conformance_get_supported)

def _parse_marker_subject_impl(ctx):
    markers.parse(ctx.attr.marker)
    return []

_parse_marker_subject = rule(
    implementation = _parse_marker_subject_impl,
    attrs = {"marker": attr.string()},
)

def _invalid_marker_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(matching.contains("Invalid marker"))

def packaging_conformance_test_suite(name):
    """Sets up the conformance tests.

    Args:
        name: the name of the test suite
    """
    test_suite(
        name = name + "_standard",
        basic_tests = _tests,
    )

    # A failure cannot be caught, so every invalid marker needs a target.
    invalid_test_names = []
    for i, marker in enumerate(INVALID_MARKERS):
        test_name = "{}_invalid_marker_{}".format(name, i)
        util.helper_target(_parse_marker_subject, name = test_name + "_subject", marker = marker)
        analysis_test(
            name = test_name,
            target = test_name + "_subject",
            expect_failure = True,
            impl = _invalid_marker_test_impl,
        )
        invalid_test_names.append(test_name)

    native.test_suite(
        name = name,
        tests = [":" + name + "_standard"] + [":" + n for n in invalid_test_names],
    )
