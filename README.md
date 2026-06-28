# pypackaging.bzl

Python packaging utilities in Starlark.

## Usage

For full API documentation, see [the API Reference](docs/pypackaging.md).

### In a `.bzl` file

```starlark
load("@pypackaging.bzl//:pypackaging.bzl", "pypackaging")

# Parse a version
v = pypackaging.version.parse("1.2.3")

# Parse a wheel filename
wheel_info = pypackaging.utils.parse_wheel_filename("foo-1.0-py3-none-any.whl")
```

## Upstream Sources

The logic in this repository is derived from the following upstream projects:

1. **[pypa/packaging](https://github.com/pypa/packaging)**

   - **Baseline**: Derived from release **26.2**.
   - **Purpose**: Core logic for PEP 440 versions, specifiers, PEP 508 markers, and PEP 425 compatibility tags (including platform expansion for macOS, manylinux, musllinux, Android, and iOS).
   - **License**: Dual licensed under the **Apache License, Version 2.0** or the **BSD 2-Clause License**.

2. **[pypa/pip](https://github.com/pypa/pip)**
   - **Purpose**: Wrapper logic for handling custom platform strings and legacy aliases in tag generation.
   - **License**: **MIT License**.

## Modifications

The original Python implementations have been ported to Starlark (`.bzl`) to allow evaluation during Bazel's analysis phase without requiring a Python interpreter. The core algorithms and compatibility rules remain faithful to the upstream implementations.

See individual `.bzl` files in `pypackaging/private/` for specific upstream sources and detailed documentation.
