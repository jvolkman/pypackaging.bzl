"""The workloads that are measured by the benchmarks and the steps test.

The names and the inputs of the marker and version workloads are the same as
in `tests/perf/workloads.bzl` of rules_python, so that the results can be
compared. `evaluate_partial` is `evaluate_non_strict` there.
"""

load("@pypackaging.bzl", "pypackaging")

_markers = pypackaging.markers
_requirements = pypackaging.requirements
_specifiers = pypackaging.specifiers
_tags = pypackaging.tags
_utils = pypackaging.utils
_version = pypackaging.version

_ENV = {
    "extra": "foo",
    "implementation_name": "cpython",
    "implementation_version": "3.11.4",
    "os_name": "posix",
    "platform_machine": "x86_64",
    "platform_python_implementation": "CPython",
    "platform_release": "6.1.0",
    "platform_system": "Linux",
    "platform_version": "#1 SMP Debian",
    "python_full_version": "3.11.4",
    "python_version": "3.11",
    "sys_platform": "linux",
}

# This is what the universal lock files have for the packages that are only
# built for some of the platforms.
_LONG_MARKER = (
    "(python_full_version >= '3.12' and platform_machine == 'aarch64' and sys_platform == 'linux')" +
    " or (python_full_version >= '3.12' and platform_machine == 'x86_64' and sys_platform == 'linux')" +
    " or (python_full_version < '3.12' and platform_machine != 'aarch64'" +
    " and platform_machine != 'x86_64' and sys_platform == 'linux')" +
    " or sys_platform == 'darwin' or sys_platform == 'win32'"
)
_STRING_MARKER = "sys_platform == 'win32'"
_TWO_STRINGS_MARKER = "os_name == 'posix' and sys_platform == 'linux'"
_VERSION_MARKER = "python_version >= '3.8'"

_PARSED_LONG_MARKER = _markers.parse(_LONG_MARKER)
_PARSED_VERSION_MARKER = _markers.parse(_VERSION_MARKER)

_V_3_11_4 = _version.parse("3.11.4")
_COMPATIBLE_3_8 = _specifiers.parse("~=3.8")
_EQ_3_11_PREFIX = _specifiers.parse("==3.11.*")
_GE_3_8 = _specifiers.parse(">=3.8")
_LT_3_8 = _specifiers.parse("<3.8")
_SPECIFIER_SET = _specifiers.parse_set(">=3.8,!=3.9.*,<4")

WORKLOADS = {
    # keep sorted
    "evaluate_long": lambda: _markers.evaluate(_markers.parse(_LONG_MARKER), _ENV),
    "evaluate_long_parsed": lambda: _markers.evaluate(_PARSED_LONG_MARKER, _ENV),
    "evaluate_partial": lambda: _markers.evaluate_partial(
        _markers.parse("python_version < '3.11' and extra == 'dev'"),
        {"extra": "dev"},
    ),
    "evaluate_string": lambda: _markers.evaluate(_markers.parse(_STRING_MARKER), _ENV),
    "evaluate_two_strings": lambda: _markers.evaluate(_markers.parse(_TWO_STRINGS_MARKER), _ENV),
    "evaluate_version": lambda: _markers.evaluate(_markers.parse(_VERSION_MARKER), _ENV),
    "evaluate_version_parsed": lambda: _markers.evaluate(_PARSED_VERSION_MARKER, _ENV),
    "parse_long": lambda: _markers.parse(_LONG_MARKER),
    "requirement_parse": lambda: _requirements.parse("requests[socks]>=2.31,<3; python_version >= '3.8'"),
    "specifier_set_contains": lambda: _specifiers.set_contains(_SPECIFIER_SET, _V_3_11_4),
    "specifier_set_parse": lambda: _specifiers.parse_set(">=3.8,!=3.9.*,<4"),
    "tags_get_supported": lambda: _tags.get_supported(
        version = "312",
        platforms = ["manylinux_2_28_x86_64"],
        impl = "cp",
        abis = ["cp312"],
    ),
    "version_is_compatible": lambda: _specifiers.contains(_COMPATIBLE_3_8, _V_3_11_4),
    "version_is_eq_prefix": lambda: _specifiers.contains(_EQ_3_11_PREFIX, _V_3_11_4),
    "version_is_ge": lambda: _specifiers.contains(_GE_3_8, _V_3_11_4),
    "version_is_lt": lambda: _specifiers.contains(_LT_3_8, _V_3_11_4),
    "version_normalize": lambda: _version.to_string(_version.parse("2023.07.19")),
    "version_parse_all_segments": lambda: _version.try_parse("1!2.0.0rc1.post3.dev4+ubuntu.7"),
    "version_parse_invalid": lambda: _version.try_parse("#1 SMP Debian"),
    "version_parse_pre_release": lambda: _version.try_parse("3.13.0rc1"),
    "version_parse_release": lambda: _version.try_parse("3.11.4"),
    "wheel_filename_parse": lambda: _utils.parse_wheel_filename("foo_bar-1.0.post1-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"),
}
