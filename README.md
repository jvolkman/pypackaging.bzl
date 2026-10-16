# pypackaging.bzl

Python packaging utilities in Starlark: a port of
[pypa/packaging](https://github.com/pypa/packaging) that runs during Bazel's
loading and analysis phases without a Python interpreter.

- PEP 440 versions and version specifiers
- PEP 508 environment markers and dependency specifiers (requirements)
- PEP 425 compatibility tags, including platform expansion for macOS,
  manylinux, musllinux, Android and iOS
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
(`//:pypackaging.bzl`) and the `@pypackaging.bzl//:pypackaging` bzl_library.
Everything under `pypackaging/private/` is an implementation detail; other
repositories cannot load those files or depend on those targets.

The project follows [Semantic Versioning](https://semver.org/). While the
version is 0.x, breaking changes are released as minor versions and listed in
the [changelog](CHANGELOG.md).

## Divergences from pypa/packaging

pypackaging.bzl follows packaging 26.2 (and pip's `get_supported` wrapper)
closely and is tested against it. Starlark has no classes or exceptions, so
results are structs, and functions `fail()` where packaging raises. Apart from
that, these are the intentional differences.

### Versions and specifiers

- Versions are structs. Compare them through their `key` field, and use
  `version.to_string(v)` for packaging's `str(Version)`. `version_str` is the
  input text (without surrounding whitespace), not the normalized form.
  `pre`, `post` and `dev` are tuples such as `("rc", 1)`, and there are no
  `public`, `base_version`, `major`, `minor` or `micro` properties.
- `parse` functions fail on invalid input; `version.try_parse` returns None
  instead.
- `~=` derives its prefix from the normalized version, as PEP 440 says:
  `~=1.0c1` means `>=1.0c1, ==1.*`. packaging derives it from the raw string,
  so it treats `~=1.0c1`, `~=1.0.r1` or `~=1.0.RC1` as `==1.0.*`, and `~=v1.0`
  matches nothing.
- Specifiers and specifier sets are immutable structs, so there is no
  constructor-level `prereleases`; pass `prereleases` to `contains`,
  `set_contains`, `filter` or `set_filter` instead. There is no `key`
  argument for filtering, no set intersection (`&`), no `is_unsatisfiable`,
  and no normalized `str()` or equality: struct equality compares specifiers
  as written.
- `===` folds case for ASCII letters only.

### Markers and requirements

- `markers.parse("")` returns `[]`, which evaluates to True; packaging rejects
  the empty string.
- There is no default environment: every variable a marker uses must be in
  the environment dict, except `extra`, which defaults to `""` (None also
  means `""`).
- `extra` may be a list or tuple of active extras, as uv does. `==`, `===`
  and `!=` then test membership, and any other operator fails.
- The value compared with `extra` is normalized at every nesting level;
  packaging only normalizes top-level comparisons, so its
  `(extra == 'Foo_Bar')` never matches.
- `\N{...}` escapes in marker strings are not supported and fail.
- A collection (`extras`, `dependency_groups`) on the left of a comparison
  fails with a clear error; packaging raises `AssertionError`.
- `markers.to_string` keeps the parentheses of a doubly parenthesized nested
  group; packaging turns `a and ((b or c))` into `a and b or c`.
- Word boundaries treat every non-ASCII character as a word character. This
  isn't observable on valid input.
- `requirements.parse` returns the normalized `name` and sorted,
  de-duplicated, normalized `extras`; `specifier` is None for URL
  requirements.

### Tags and utilities

- `tags.get_supported` fully expands `manylinux_X_Y_<arch>`, legacy
  `manylinux*_<arch>` and `musllinux_X_Y_<arch>` platforms the way packaging
  expands the host platform: older glibc/musl versions, legacy aliases, the
  armv8l to armv7l fallback, and `linux_<arch>` last. pip leaves them mostly
  unexpanded.
- There is no host interpreter to fall back to: `version` is required, `impl`
  defaults to `cp`, `abis = None` means no interpreter-specific ABIs, and
  empty or `None` platforms (or platforms that expand to nothing) mean
  `["any"]`.
- Every duplicate `abi3` and `none` in `abis` is removed; packaging removes
  only the first of each.
- `tags.parse_tag` returns a list without duplicates, in component order,
  instead of a frozenset.
- `utils.canonicalize_name` lowercases ASCII letters only, and wheel project
  names may contain any non-ASCII character (packaging accepts only Unicode
  word characters).

## Upstream Sources

The logic in this repository is derived from the following upstream projects:

1. **[pypa/packaging](https://github.com/pypa/packaging)**

   - **Baseline**: Derived from release **26.2**.
   - **Purpose**: Core logic for PEP 440 versions, specifiers, PEP 508 markers, and PEP 425 compatibility tags (including platform expansion for macOS, manylinux, musllinux, Android, and iOS).
   - **License**: Dual licensed under the **Apache License, Version 2.0** or the **BSD 2-Clause License**.

2. **[pypa/pip](https://github.com/pypa/pip)**
   - **Purpose**: Wrapper logic for handling custom platform strings and legacy aliases in tag generation.
   - **License**: **MIT License**.

The upstream copyright notices and license texts are reproduced in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES/](LICENSES).

## Modifications

The original Python implementations have been ported to Starlark (`.bzl`) so
they can be evaluated during Bazel's analysis phase without a Python
interpreter. The port follows the upstream algorithms and compatibility rules
and is tested against upstream's test cases. Known differences are listed in
[Divergences from pypa/packaging](#divergences-from-pypapackaging).

See individual `.bzl` files in `pypackaging/private/` for specific upstream sources and detailed documentation.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
