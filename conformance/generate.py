"""Generate Starlark conformance test cases from the `pypa/packaging` project.

The test inputs are harvested from the `packaging` test-suite and the expected
values are computed with (or taken from) the very same `packaging` release, so
that the Starlark implementations are compared with the reference
implementation of the PyPA specifications.

Update the checked-in files by running this in the `conformance` directory:

    bazel run //:update

See the README.md for details.
"""

import argparse
import ast
import itertools
import json
import operator
import os
import pathlib
import random
import re
import sys
import types
import typing
from unittest import mock

import packaging
from packaging import _manylinux, _musllinux, tags
from packaging.markers import InvalidMarker, Marker, UndefinedComparison
from packaging.specifiers import InvalidSpecifier, Specifier, SpecifierSet
from packaging.version import InvalidVersion, Version

_HEADER = '''"""Conformance test cases generated from `packaging=={version}`.

GENERATED FILE, DO NOT EDIT. Update with:

    cd conformance && bazel run //:update
"""
'''

_VERSION_OPERATORS = ["==", "!=", "<", "<=", ">", ">=", "~="]

# Versions used to exercise every operator against every specifier below. The
# packaging test-suite has examples for each operator, but this gives us an
# exhaustive table for the edge cases: zero padding, pre/post/dev releases,
# local versions and epochs.
_MATRIX_VERSIONS = [
    "3",
    "3.0",
    "3.0.0",
    "3.0.1",
    "3.1",
    "3.9",
    "3.10",
    "3.10.0",
    "3.10.1",
    "3.13.dev1",
    "3.13.0.dev1",
    "3.13.0a1.dev1",
    "3.13.0a1",
    "3.13.0a1.post2",
    "3.13.0a2",
    "3.13.0b1",
    "3.13.0rc1.dev1",
    "3.13.0rc1",
    "3.13rc2",
    "3.13",
    "3.13.0",
    "3.13.0+local",
    "3.13.0+local.2",
    "3.13.0+3",
    "3.13.post1.dev2",
    "3.13.post1",
    "3.13.0.post1",
    "3.13.0.post1+local",
    "3.13.0.post2",
    "3.13.1.dev0",
    "3.13.1",
    "3.14",
    "4.dev0",
    "4",
    "1!3.0",
    "1!3.13",
]

# The `.*` suffix is only valid with the `==` and `!=` operators and the local
# versions cannot be used with the ordered comparisons, the invalid
# combinations are skipped.
_MATRIX_SPECS = _MATRIX_VERSIONS + [
    "3.*",
    "3.0.*",
    "3.1.*",
    "3.10.*",
    "3.13.*",
    "3.13.0.*",
    "1!3.*",
]


# The inputs that the `packaging` test-suite does not have, these are the edge
# cases that were found in the Starlark implementations.
_EXTRA_NORMALIZED_VERSIONS = [
    "V1.0",
    "1.0+001.a.002",
    "1.0+A.B",
    "00!01.02",
]
_EXTRA_INVALID_VERSIONS = [
    "",
    "1!",
    "!1",
    "1. 2",
    "*",
    ".*",
    "1.*",
    "1.0.*",
    "1.*.*",
    "1.0+",
    "1.0+local.",
    "{VERSION}",
    "1.0+{BUILD_USER}",
]
_EXTRA_INVALID_SPECIFIERS = [
    "",
    "==",
    "==*",
    "==.*",
    "==1.*.*",
    "==1.0 .*",
    "==1. 0",
    # The prefix matching is only for the versions without the suffixes.
    "==1.0a1.*",
    "==1.0.post1.*",
    "==1.0.dev1.*",
    "==1.0+local.*",
    "!=1.0+local.*",
    # The prefix matching is only for the equality operators.
    "~=1.0.*",
    ">=1.0.*",
    "<1.0.*",
    # The compatible release needs at least 2 release segments.
    "~=1",
    "~=1!1",
]

# (version, specifier), the pre-releases are allowed.
_EXTRA_SPECIFIER_CASES = [
    # The prefix of the compatible release operator comes from the normalized
    # version. `packaging` used to get it from the string before 26.3.
    ("1.1", "~=1.0c1"),
    ("2.0", "~=1.0c1"),
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
    ("1.1", "~=1.0.0c1"),
    ("1.1", "~=v1.0"),
    ("2.0", "~=v1.0"),
    ("1.1", "~=V1.0"),
    ("2.2.5", "~=v2.2.0"),
    ("1.5", "~=1.0RC1"),
    ("1.5", "~=1.0-c1"),
    ("1.5", "~=1.0_c1"),
    ("1.5", "~=1.0alpha1"),
    ("1.5", "~=1.0.post1"),
    ("1.5", "~=1!1.0"),
    ("1!1.5", "~=1!1.0"),
    ("1!2.0", "~=1!1.0"),
]

# (specifier, version, prereleases, installed)
_EXTRA_CONTAINS_CASES = [
    # The release of the version is shorter than the one of the specifier.
    ("!=1.2.3", "2", None, None),
    ("<=1.2.3", "2", None, None),
    ("===1.0a1", "1.0a1", False, None),
    ("===1.0a1", "1.0a1", None, None),
]
_EXTRA_SET_CONTAINS_CASES = [
    # `>V` excludes all of the post-releases of V.
    (">1.0,!=1.0.post1", "1.0.post2", True, None),
    (">1.0,!=1.0.post1", "1.0.post2.dev3", True, None),
    (">1.0,!=1.0.post1", "1.0.post1", True, None),
    (">1.0,!=1.0.post1", "1.1", True, None),
    (">1.0,!=1.0.post1", "1.0.post2", None, None),
    (">2.3,!=2.3.post1", "2.3.post2", True, None),
    (">1!1.0,!=1!1.0.post1", "1!1.0.post2", True, None),
]

# (specifier, prereleases, versions)
_EXTRA_FILTER_CASES = [
    ("===1.0a1", False, ["1.0a1", "0.9"]),
    ("===1.0a1", None, ["1.0a1"]),
    ("===wat", None, ["wat", "wat"]),
    ("===wat", None, ["wat", "WAT", "else"]),
    ("!=1.2.3", True, ["2"]),
    ("<=1.2.3", True, ["2"]),
]
_EXTRA_SET_FILTER_CASES = [
    (">1.0,!=1.0.post1", True, ["1.0.post2", "1.0.post3", "1.1"]),
    # The pre-releases are only used if there are no final releases.
    ("!=1.5", None, ["1.4", "1.6a1"]),
    ("!=1.5", None, ["1.6a1", "1.4"]),
    ("!=1.5", None, ["1.6a1", "1.5"]),
]

# The arguments of `get_supported`: (version, platforms, impl, abis). There is
# a single platform for each case, because how the Linux platforms of the
# different libc implementations are combined is specific to the library.
_GET_SUPPORTED_ARGS = [
    ("312", ["manylinux_2_28_x86_64"], "cp", ["cp312"]),
    ("311", ["manylinux2014_aarch64"], "cp", ["cp311"]),
    ("310", ["manylinux_2_31_armv8l"], "cp", ["cp310"]),
    ("311", ["musllinux_1_2_aarch64"], "cp", ["cp311"]),
    ("313", ["macosx_14_0_arm64"], "cp", ["cp313"]),
    ("39", ["macosx_10_15_x86_64"], "cp", ["cp39"]),
    ("311", ["macosxcustom_1_2_10_9_x86_64"], "cp", ["cp311"]),
    ("312", ["win_amd64"], "cp", ["cp312"]),
    ("313", ["ios_13_0_arm64_iphoneos"], "cp", ["cp313"]),
    ("313", ["android_24_arm64_v8a"], "cp", ["cp313"]),
    ("313", ["manylinux_2_28_x86_64"], "cp", ["cp313t"]),
    ("314", ["win_amd64"], "cp", ["cp314t", "abi3t", "abi3", "none"]),
    ("310", ["manylinux_2_28_x86_64"], "pp", ["pypy310_pp73"]),
    ("3", ["any"], "py", []),
]

# The number of the first tags that are checked one by one, the rest of them
# are only checked with a hash.
_GET_SUPPORTED_HEAD = 30

_LEGACY_MANYLINUX = {
    "manylinux1": (2, 5),
    "manylinux2010": (2, 12),
    "manylinux2014": (2, 17),
}

# The environment that is used to evaluate the markers, unless the test case
# overrides the values.
_MARKER_ENV = {
    "extra": "foo",
    "implementation_name": "cpython",
    "implementation_version": "3.11.4",
    "os_name": "posix",
    "platform_machine": "x86_64",
    "platform_python_implementation": "CPython",
    "platform_release": "6.1.0",
    "platform_system": "Linux",
    "platform_version": "#1 SMP PREEMPT_DYNAMIC Debian 6.1.55-1 (2023-09-29)",
    "python_full_version": "3.11.4",
    "python_version": "3.11",
    "sys_platform": "linux",
}

# The variables that are sets, their value in the environment and the values
# to test the membership of.
_SET_VARIABLES = ["extras", "dependency_groups"]
_SET_ENV_VALUE = ["foo", "bar-baz"]
_SET_VALUES = ["foo", "Foo", "f", "bar-baz", "Bar_Baz", "bar.baz", "bar", ""]

# The expressions that are combined with `and`, `or` and parenthesis to test
# the precedence and the grouping.
_MARKER_ATOMS = [
    'os_name == "posix"',
    'os_name == "nt"',
    "sys_platform != 'linux'",
    'python_version >= "3.8"',
    'python_full_version < "3.11.4"',
    'platform_machine in "x86_64 amd64"',
    '"arm" in platform_machine',
    '"posix" == os_name',
    'extra == "foo"',
]


def _pytest_stub():
    """A minimal stand-in so that the test modules do not need pytest."""
    return types.SimpleNamespace(param=lambda *args, **kwargs: args)


class _TestModule:
    """Extracts constants and `pytest.mark.parametrize` values of a test file."""

    def __init__(self, path, **namespace):
        self._tree = ast.parse(pathlib.Path(path).read_text(encoding="utf-8"))
        self.namespace: dict[str, typing.Any] = {
            "itertools": itertools,
            "operator": operator,
            "os": os,
            "pytest": _pytest_stub(),
            "Specifier": Specifier,
            "SpecifierSet": SpecifierSet,
            "Version": Version,
        }
        self.namespace.update(namespace)

        # Only the upper case constants are evaluated, they are used by the
        # parametrize expressions.
        for node in self._tree.body:
            if (
                isinstance(node, ast.Assign)
                and len(node.targets) == 1
                and isinstance(node.targets[0], ast.Name)
                and node.targets[0].id.isupper()
            ):
                try:
                    self.namespace[node.targets[0].id] = self._eval(node.value)
                except NameError:
                    # Depends on helpers of the test module, not needed.
                    pass

    def _eval(self, node):
        code = compile(ast.Expression(node), "<packaging tests>", "eval")
        return eval(code, self.namespace)  # pylint: disable=eval-used

    def parametrize(self, test_name, *, optional=False):
        """Returns the values of the parametrize decorator of the given test.

        Args:
            test_name: the name of the test function, or `Class.function` if
                there are many functions with the same name.
            optional: return an empty list if there is no such test, for the
                tests that not all of the supported `packaging` versions have.
        """
        class_name, _, function_name = test_name.rpartition(".")
        scopes = [
            node
            for node in self._tree.body
            if not class_name
            or (isinstance(node, ast.ClassDef) and node.name == class_name)
        ]
        for node in itertools.chain.from_iterable(ast.walk(s) for s in scopes):
            if not isinstance(node, ast.FunctionDef) or node.name != function_name:
                continue
            for decorator in node.decorator_list:
                if (
                    isinstance(decorator, ast.Call)
                    and ast.unparse(decorator.func) == "pytest.mark.parametrize"
                ):
                    return list(self._eval(decorator.args[1]))
        if optional:
            return []
        raise ValueError("no parametrized test named: " + test_name)


def _literal(value):
    """Format the value as a Starlark literal."""
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, tuple):
        if len(value) == 1:
            return "({},)".format(_literal(value[0]))
        return "({})".format(", ".join([_literal(v) for v in value]))
    if isinstance(value, list):
        return "[{}]".format(", ".join([_literal(v) for v in value]))
    assert value is None or isinstance(value, (bool, int)), value
    return repr(value)


def _list(name, values, comment):
    lines = ["", "# " + comment, name + " = ["]
    lines += ["    {},".format(_literal(value)) for value in values]
    lines.append("]")
    return "\n".join(lines) + "\n"


def _unique(values):
    return list(dict.fromkeys(values))


def _matrix():
    rows = []
    for op in _VERSION_OPERATORS:
        for spec in _MATRIX_SPECS:
            try:
                specifier = Specifier(op + spec)
            except InvalidSpecifier:
                continue
            row = "".join(
                [
                    "T" if specifier.contains(v, prereleases=True) else "F"
                    for v in _MATRIX_VERSIONS
                ]
            )
            rows.append((op + spec, row))
    return rows


def _prereleases(specifier_prereleases, prereleases):
    """Return the `prereleases` argument that has the same effect.

    The Starlark specifiers are immutable structs without the `prereleases`
    override, which is only used if the argument of the method is `None`.
    """
    return specifier_prereleases if prereleases is None else prereleases


def _contains_cases(cls, cases):
    """Return the `(specifier, version, prereleases, installed, expected)`."""
    rows = []
    for spec, version, prereleases, installed in _unique(cases):
        kwargs = {} if installed is None else {"installed": installed}
        expected = cls(spec).contains(version, prereleases=prereleases, **kwargs)
        rows.append((spec, version, prereleases, installed, expected))
    return rows


def _filter_cases(cls, cases):
    """Return the `(specifier, prereleases, versions, expected)`."""
    rows = []
    for spec, prereleases, versions in cases:
        versions = [str(v) for v in versions]
        expected = list(cls(spec).filter(versions, prereleases=prereleases))
        row = (spec, prereleases, versions, expected)
        if row not in rows:
            rows.append(row)
    return rows


def version_cases(test_version, test_specifiers):
    """Generate the test cases for the versions and the version specifiers."""
    versions = _TestModule(test_version)
    specifiers = _TestModule(test_specifiers, VERSIONS=versions.namespace["VERSIONS"])

    specifier_cases = []
    for version, spec in [
        (version, spec)
        for version, spec, _ in specifiers.parametrize("TestSpecifier.test_specifiers")
    ] + _EXTRA_SPECIFIER_CASES:
        expected = Specifier(spec).contains(version, prereleases=True)
        specifier_cases.append((version, spec, expected))

    invalid_versions = _unique(
        versions.parametrize("test_invalid_versions") + _EXTRA_INVALID_VERSIONS
    )
    for version in invalid_versions:
        try:
            Version(version)
        except InvalidVersion:
            continue
        raise ValueError("expected an invalid version: " + version)

    invalid_specifiers = _unique(
        specifiers.parametrize("TestSpecifier.test_specifiers_invalid")
        + _EXTRA_INVALID_SPECIFIERS
    )
    for spec in invalid_specifiers:
        try:
            Specifier(spec)
        except InvalidSpecifier:
            continue
        raise ValueError("expected an invalid specifier: " + spec)

    contains_cases = _contains_cases(
        Specifier,
        [
            (spec, version, _prereleases(spec_pre, contains_pre), None)
            for spec, version, spec_pre, contains_pre, _ in specifiers.parametrize(
                "TestSpecifier.test_specifiers_prereleases"
            )
        ]
        + _EXTRA_CONTAINS_CASES,
    )
    set_contains_cases = _contains_cases(
        SpecifierSet,
        [
            (spec, version, _prereleases(spec_pre, contains_pre), installed)
            for (
                spec,
                version,
                spec_pre,
                contains_pre,
                installed,
                _,
            ) in specifiers.parametrize(
                "TestSpecifierSet.test_specifier_contains_installed_prereleases"
            )
        ]
        + [
            (spec, version, prereleases, None)
            for spec, prereleases, version, _ in specifiers.parametrize(
                "TestSpecifierSet.test_contains_exclusionary_bridges"
            )
        ]
        + _EXTRA_SET_CONTAINS_CASES,
    )
    filter_cases = _filter_cases(
        Specifier,
        [
            (spec, _prereleases(spec_pre, prereleases), versions)
            for spec, spec_pre, prereleases, versions, _ in specifiers.parametrize(
                "TestSpecifier.test_specifier_filter"
            )
        ]
        + _EXTRA_FILTER_CASES,
    )
    set_filter_cases = _filter_cases(
        SpecifierSet,
        [
            (spec, _prereleases(spec_pre, prereleases), versions)
            for spec, spec_pre, prereleases, versions, _ in specifiers.parametrize(
                "TestSpecifierSet.test_specifier_filter"
            )
        ]
        + [
            (spec, prereleases, versions)
            for spec, prereleases, versions, _ in specifiers.parametrize(
                "TestSpecifierSet.test_filter_exclusionary_bridges"
            )
        ]
        + _EXTRA_SET_FILTER_CASES,
    )

    return "".join(
        [
            _HEADER.format(version=packaging.__version__),
            _list(
                "ORDERED_VERSIONS",
                versions.namespace["VERSIONS"],
                "Valid versions in the ascending order.",
            ),
            _list(
                "INVALID_VERSIONS",
                invalid_versions,
                "Strings that are not valid versions.",
            ),
            _list(
                "NORMALIZED_VERSIONS",
                [
                    (version, str(Version(version)))
                    for version in _unique(
                        [v for v, _ in versions.parametrize("test_normalized_versions")]
                        + _EXTRA_NORMALIZED_VERSIONS
                    )
                ],
                "(version, normalized)",
            ),
            _list(
                "SPECIFIER_CASES",
                specifier_cases,
                "(version, specifier, expected), the pre-releases are allowed.",
            ),
            _list(
                "INVALID_SPECIFIERS",
                invalid_specifiers,
                "Strings that are not valid specifiers.",
            ),
            _list(
                "MATRIX_VERSIONS",
                _MATRIX_VERSIONS,
                "The versions that the columns of MATRIX correspond to.",
            ),
            _list(
                "MATRIX",
                _matrix(),
                "(specifier, T/F for each of MATRIX_VERSIONS), the pre-releases are\n"
                "# allowed.",
            ),
            _list(
                "CONTAINS_CASES",
                contains_cases,
                "(specifier, version, prereleases, installed, expected)",
            ),
            _list(
                "SET_CONTAINS_CASES",
                set_contains_cases,
                "(specifier set, version, prereleases, installed, expected)",
            ),
            _list(
                "FILTER_CASES",
                filter_cases,
                "(specifier, prereleases, versions, expected)",
            ),
            _list(
                "SET_FILTER_CASES",
                set_filter_cases,
                "(specifier set, prereleases, versions, expected)",
            ),
        ]
    )


def _evaluate_marker(marker, env):
    """Return the result or `None` if it is an error to evaluate the marker."""
    try:
        return Marker(marker).evaluate(env)
    except (InvalidMarker, UndefinedComparison, KeyError, AssertionError):
        # The older `packaging` versions fail with an `AssertionError` if the
        # variables that are sets are not used for the membership tests.
        return None


def _is_valid_marker(marker):
    try:
        Marker(marker)
    except InvalidMarker:
        return False
    return True


def _random_marker(rng, depth):
    if depth == 0 or rng.random() < 0.3:
        return rng.choice(_MARKER_ATOMS)

    marker = _random_marker(rng, depth - 1)
    for _ in range(rng.randint(1, 3)):
        marker += rng.choice([" and ", " or "]) + _random_marker(rng, depth - 1)

    return "({})".format(marker) if rng.random() < 0.5 else marker


def _marker_table(env, variables, operators, values):
    rows = []
    for variable, op, value in itertools.product(variables, operators, values):
        # The test builds the markers the same way.
        assert '"' not in value, value
        result = ""
        for marker in [
            '{} {} "{}"'.format(variable, op, value),
            '"{}" {} {}'.format(value, op, variable),
        ]:
            got = _evaluate_marker(marker, env)
            # "E" means that it is an error to evaluate the marker.
            result += "E" if got is None else "T" if got else "F"
        rows.append((variable, op, value, result))
    return rows


def marker_cases(test_markers):
    """Generate the test cases for the environment markers."""
    markers = _TestModule(test_markers)

    evaluate_cases = []
    for test_name in [
        "test_evaluates",
        "test_evaluate_pep345_markers",
        "test_version_like_equality",
    ]:
        for marker, env, expected in markers.parametrize(test_name):
            if env is None:
                # These depend on the interpreter that runs the tests.
                continue

            got = _evaluate_marker(marker, _MARKER_ENV | env)
            if got != expected:
                raise ValueError(
                    "The default environment changes the result of: " + marker
                )
            evaluate_cases.append((marker, json.dumps(env, sort_keys=True), expected))

    # Not all of these are invalid for the older `packaging` versions.
    invalid = [
        marker
        for marker in markers.parametrize("test_parses_invalid")
        + [
            'python_version >= "3"' + line_break
            for line_break in markers.parametrize(
                "test_parses_invalid_trailing_line_break", optional=True
            )
        ]
        if not _is_valid_marker(marker)
    ]

    str_cases = [
        (marker, str(Marker(marker)))
        for marker, _ in markers.parametrize("test_str_repr_eq_hash")
    ]

    rng = random.Random(508)
    logic = {}
    for _ in range(100):
        marker = _random_marker(rng, 3)
        logic[marker] = _evaluate_marker(marker, _MARKER_ENV)

    ns = markers.namespace
    return "".join(
        [
            _HEADER.format(version=packaging.__version__),
            _list(
                "MARKER_ENV",
                sorted(_MARKER_ENV.items()),
                "The (name, value) of the default environment for the cases below.",
            ),
            _list(
                "EVALUATE_CASES",
                evaluate_cases,
                "(marker, JSON of the environment overrides, expected)",
            ),
            _list(
                "INVALID_MARKERS",
                invalid,
                "Strings that are not valid markers.",
            ),
            _list(
                "STR_CASES",
                str_cases,
                "(marker, normalized)",
            ),
            _list(
                "MARKER_TABLE",
                _marker_table(
                    _MARKER_ENV,
                    ns["VARIABLES"]
                    + ns["PEP_345_VARIABLES"]
                    + ns["SETUPTOOLS_VARIABLES"],
                    ns["OPERATORS"],
                    ns["VALUES"],
                ),
                "(variable, operator, value, results); the results are T/F/E(rror) for\n"
                "# `<variable> <operator> <value>` and `<value> <operator> <variable>`.",
            ),
            _list(
                "SET_ENV_VALUE",
                _SET_ENV_VALUE,
                "The value of the variables that are sets for the cases below.",
            ),
            _list(
                "SET_TABLE",
                _marker_table(
                    _MARKER_ENV
                    | {v: frozenset(_SET_ENV_VALUE) for v in _SET_VARIABLES},
                    _SET_VARIABLES,
                    ["in", "not in", "==", "!=", ">=", "<", "~=", "==="],
                    _SET_VALUES,
                ),
                "The same as the `MARKER_TABLE`, but for the variables that are sets.",
            ),
            _list(
                "LOGIC_CASES",
                sorted(logic.items()),
                "(marker, expected)",
            ),
        ]
    )


def _linux_platforms(arch, *, glibc=None, musl=None):
    """Return what `packaging` yields on a Linux host with the given libc."""
    with (
        mock.patch.object(_manylinux, "_get_glibc_version", lambda: glibc or (-1, -1)),
        mock.patch.object(_manylinux, "_have_compatible_abi", lambda *_: True),
        mock.patch.object(_manylinux, "_is_compatible", lambda *_: True),
        mock.patch.object(
            _musllinux,
            "_get_musl_version",
            lambda *_: _musllinux._MuslVersion(*musl) if musl else None,
        ),
        mock.patch("sysconfig.get_platform", lambda: "linux-" + arch),
    ):
        return list(tags._linux_platforms(is_32bit=False))


def _expand_platform(platform):
    """Expand the platform to the compatible ones.

    This is what `pip` does for `--platform`, except that the manylinux and
    musllinux platforms are expanded like `packaging` does for the host, see
    the documentation of `tags.get_supported`.
    """
    if match := re.fullmatch(r"manylinux_(\d+)_(\d+)_(.+)", platform):
        major, minor, arch = match.groups()
        return _linux_platforms(arch, glibc=(int(major), int(minor)))
    if match := re.fullmatch(r"(manylinux\d+)_(.+)", platform):
        legacy, arch = match.groups()
        return _linux_platforms(arch, glibc=_LEGACY_MANYLINUX[legacy])
    if match := re.fullmatch(r"musllinux_(\d+)_(\d+)_(.+)", platform):
        major, minor, arch = match.groups()
        return _linux_platforms(arch, musl=(int(major), int(minor)))
    if match := re.fullmatch(r"android_(\d+)_(.+)", platform):
        api_level, abi = match.groups()
        return list(tags.android_platforms(int(api_level), abi))

    match = re.match(r"(.+)_(\d+)_(\d+)_(.+)", platform)
    if match and platform.startswith("macosx"):
        name, major, minor, arch = match.groups()
        return [
            name + p[len("macosx") :]
            for p in tags.mac_platforms((int(major), int(minor)), arch)
        ]
    if match and platform.startswith("ios"):
        name, major, minor, multiarch = match.groups()
        return [
            name + p[len("ios") :]
            for p in tags.ios_platforms((int(major), int(minor)), multiarch)
        ]
    return [platform]


def _get_supported(version, platforms, impl, abis):
    """The `get_supported` of `pip` on top of the given `packaging`."""
    python_version = (int(version[0]),)
    if len(version) > 1:
        python_version += (int(version[1:]),)
    interpreter = impl + version
    platforms = _unique(itertools.chain.from_iterable(map(_expand_platform, platforms)))

    if impl == "cp":
        supported = list(tags.cpython_tags(python_version, abis, platforms))
    else:
        supported = list(tags.generic_tags(interpreter, abis, platforms))
    supported.extend(tags.compatible_tags(python_version, interpreter, platforms))
    return [str(tag) for tag in supported]


def _starlark_hash(value):
    """The `hash` of a Starlark string, which is the same as in Java."""
    result = 0
    for char in value.encode("utf-16-be")[1::2]:
        result = (31 * result + char) & 0xFFFFFFFF
    return result - (1 << 32) if result & (1 << 31) else result


def tags_cases():
    """Generate the test cases for the tags."""
    get_supported_cases = []
    for version, platforms, impl, abis in _GET_SUPPORTED_ARGS:
        supported = _get_supported(version, platforms, impl, abis)
        assert all(tag.isascii() for tag in supported), supported
        get_supported_cases.append(
            (
                version,
                platforms,
                impl,
                abis,
                len(supported),
                _starlark_hash(" ".join(supported)),
                supported[:_GET_SUPPORTED_HEAD],
            )
        )

    return "".join(
        [
            _HEADER.format(version=packaging.__version__),
            _list(
                "GET_SUPPORTED_CASES",
                get_supported_cases,
                "(version, platforms, impl, abis, the number of the tags, the hash of the\n"
                "# tags that are joined with a space, the first tags)",
            ),
        ]
    )


def _resolve(path):
    """Resolve a path that may be a runfiles path."""
    if os.path.exists(path):
        return path

    from python.runfiles import runfiles

    rfiles = runfiles.Create()
    assert rfiles is not None, "Failed to create runfiles"
    resolved = rfiles.Rlocation(path)
    if not resolved or not os.path.exists(resolved):
        raise FileNotFoundError(path)
    return resolved


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-version", required=True)
    parser.add_argument("--test-specifiers", required=True)
    parser.add_argument("--test-markers", required=True)
    parser.add_argument(
        "--version-cases",
        required=True,
        help="The file with the version and specifier test cases to write or check.",
    )
    parser.add_argument(
        "--marker-cases",
        required=True,
        help="The file with the marker test cases to write or check.",
    )
    parser.add_argument(
        "--tags-cases",
        required=True,
        help="The file with the tags test cases to write or check.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if the files are out of date instead of writing them.",
    )
    args = parser.parse_args(argv)

    outputs = {
        args.version_cases: version_cases(
            _resolve(args.test_version),
            _resolve(args.test_specifiers),
        ),
        args.marker_cases: marker_cases(_resolve(args.test_markers)),
        args.tags_cases: tags_cases(),
    }

    stale = []
    for path, content in outputs.items():
        if args.check:
            current = pathlib.Path(_resolve(path)).read_text(encoding="utf-8")
            if current != content:
                stale.append(path)
            continue

        # The files are in the parent directory of this Bazel module.
        root = os.environ.get("BUILD_WORKSPACE_DIRECTORY", "")
        out = pathlib.Path(root, path)
        out.write_text(content, encoding="utf-8")
        print("Wrote", out)

    if stale:
        print(
            "Out of date: {}\nRun: cd conformance && bazel run //:update".format(
                ", ".join(stale),
            ),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
