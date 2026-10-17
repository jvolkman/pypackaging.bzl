# pypackaging.bzl

Python packaging utilities in Starlark: a port of
[pypa/packaging](https://github.com/pypa/packaging) that runs during Bazel's
loading and analysis phases without a Python interpreter.

- PEP 440 versions and version specifiers
- PEP 508 environment markers and dependency specifiers (requirements)
- PEP 425 compatibility tags, including platform expansion for macOS,
  manylinux, musllinux, Android, and iOS
- Wheel and sdist filename parsing, name and version normalization

## Requirements

- Bazel 7.1 or newer
- Bzlmod (WORKSPACE is not supported)

## Installation

Add to your `MODULE.bazel` file (see the
[releases](https://github.com/jvolkman/pypackaging.bzl/releases) for the
latest version):

```starlark
bazel_dep(name = "pypackaging.bzl", version = "0.3.0")
```

## Usage

For the full API documentation, see [the API reference](docs/pypackaging.md).

### In a `.bzl` file

```starlark
load("@pypackaging.bzl", "pypackaging")

# Versions (PEP 440): compare them through their sort keys.
v = pypackaging.version.parse("1.2.3")
is_older = pypackaging.version.parse("1.0rc1").key < v.key  # True
pypackaging.version.to_string(pypackaging.version.parse("1.0-RC1"))  # "1.0rc1"
pypackaging.version.try_parse("not a version")  # None (parse() would fail)

# Specifiers: membership and filtering, with packaging's pre-release rules.
spec = pypackaging.specifiers.parse_set(">=1.0,<2")
pypackaging.specifiers.set_contains(spec, "1.5")  # True
pypackaging.specifiers.set_filter(spec, ["0.9", "1.1", "1.2rc1"])  # ["1.1"]

# Markers (PEP 508). There is no default environment: supply every variable
# the marker uses ("extra" defaults to "").
marker = pypackaging.markers.parse("python_version >= '3.8' and sys_platform == 'linux'")
pypackaging.markers.evaluate(marker, {"python_version": "3.12", "sys_platform": "linux"})  # True

# Requirements: req.name, req.extras, req.specifier, req.url, req.marker,
# req.marker_str.
req = pypackaging.requirements.parse("requests[socks]>=2.31; python_version >= '3.8'")

# Compatibility tags (PEP 425): pick the best wheel for a target.
supported = pypackaging.tags.get_supported(
    version = "312",
    platforms = ["manylinux_2_28_x86_64"],
    impl = "cp",
    abis = ["cp312"],
)
ranks = pypackaging.tags.priority_map(supported)  # build once, reuse
best = pypackaging.tags.select_compatible(ranks, [
    (f, pypackaging.utils.parse_wheel_filename(f).tags)
    for f in ["foo-1.0-py3-none-any.whl", "foo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"]
])[0]  # the manylinux wheel

# Names, versions and filenames.
pypackaging.utils.canonicalize_name("Foo_Bar")  # "foo-bar"
wheel_info = pypackaging.utils.parse_wheel_filename("foo-1.0-py3-none-any.whl")
```

### In a `BUILD` file

If you document or test your `.bzl` files with `bzl_library`, depend on the
public library:

```starlark
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

bzl_library(
    name = "my_rules",
    srcs = ["my_rules.bzl"],
    deps = ["@pypackaging.bzl//:pypackaging"],
)
```

## API stability

The public API is the `pypackaging` struct exported by `@pypackaging.bzl`
(`//:pypackaging.bzl`) and the `@pypackaging.bzl//:pypackaging` `bzl_library`.
Everything under `pypackaging/private/` is an implementation detail; other
repositories cannot load those files or depend on those targets.

The project follows [Semantic Versioning](https://semver.org/). While the
version is 0.x, breaking changes are released as minor versions and listed in
the [changelog](CHANGELOG.md).

## Differences from pypa/packaging

`pypackaging.bzl` follows `packaging` 26.2 and `pip`'s `get_supported` wrapper.
Because Starlark has no classes, exceptions, or host Python runtime, the API
differs in the following ways:

- **Structs and `fail()`**: Parsed objects are structs rather than classes, and
  invalid inputs call `fail()` (`version.try_parse` returns `None`).
- **Versions**: Compare versions via their `key` field (`v1.key < v2.key`), and
  use `version.to_string(v)` for the normalized string (`version_str` retains
  the input text).
- **Specifiers**: Pass `prereleases` to `contains`, `set_contains`, `filter`, or
  `set_filter`. `~=` derives its prefix from the normalized version per PEP 440.
- **Markers**:
  - `markers.parse` accepts empty or whitespace-only strings (returning `[]`,
    which evaluates to `True`).
  - `markers.evaluate` requires an explicit `environment` dict containing every
    referenced variable (`extra` defaults to `""`).
  - `environment["extra"]` may also be a list or tuple of active extras
    (uv-compatible extension for `==` and `!=`).
  - `\N{...}` named Unicode escapes in marker string literals are not supported.
- **Requirements**: `requirements.parse` normalizes `name` and returns sorted,
  deduplicated, normalized `extras` (with original spellings in `raw_name` and
  `raw_extras`). `specifier` is `None` for URL requirements.
- **Tags**: `tags.get_supported` requires `version` (no host interpreter
  fallback) and expands `manylinux*` and `musllinux*` platform tags into their
  full compatibility sequences. `tags.parse_tag` returns a deduplicated list in
  component order rather than a `frozenset`.
- **ASCII case folding**: `utils.canonicalize_name` and `===` fold case for
  ASCII letters only.

## Upstream Sources

1. **[pypa/packaging](https://github.com/pypa/packaging)** (baseline: **26.2**,
   Apache-2.0 OR BSD-2-Clause): PEP 440 versions and specifiers, PEP 508
   markers and requirements, PEP 425 compatibility tags, and filename/name
   utilities.
2. **[pypa/pip](https://github.com/pypa/pip)** (MIT): `get_supported` platform
   expansion wrapper logic.

Upstream copyright notices and license texts are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES/](LICENSES).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
