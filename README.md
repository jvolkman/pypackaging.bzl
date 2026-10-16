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

- Bazel 7 or newer
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

# Parse versions; compare them through their sort keys
v = pypackaging.version.parse("1.2.3")
is_older = pypackaging.version.parse("1.0rc1").key < v.key  # True

# Check a version against a specifier set
spec = pypackaging.specifiers.parse_set(">=1.0,<2")
pypackaging.specifiers.set_contains(spec, "1.5")  # True

# Parse a requirement (req.name, req.extras, req.specifier, req.marker)
req = pypackaging.requirements.parse("requests[socks]>=2.31; python_version >= '3.8'")

# Parse a wheel filename
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

<!-- TODO(v0.3.0): integration fills this section with the remaining intentional
divergences from packaging 26.2 (reported by each area's branch). Known so far:
the non-standard list-valued `extra` in `markers.evaluate`. -->

TODO

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
