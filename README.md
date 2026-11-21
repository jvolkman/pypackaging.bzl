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
- Bzlmod, or WORKSPACE with Bazel 7 and 8 (Bazel 9 removed WORKSPACE)

## Installation

### Bzlmod

Add to your `MODULE.bazel` file (see the
[releases](https://github.com/jvolkman/pypackaging.bzl/releases) for the
latest version):

```starlark
bazel_dep(name = "pypackaging.bzl", version = "0.3.0")
```

### WORKSPACE

Add to your `WORKSPACE.bazel` file (the release notes have the snippet with
the checksum of each release). The repository must be named `pypackaging.bzl`,
so that the same `load` statements work as with Bzlmod:

```starlark
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "pypackaging.bzl",
    sha256 = "09570564367dfbff313950528376c9ba9ded9025cacb2c731545db19bc27e1e9",
    strip_prefix = "pypackaging.bzl-0.3.0",
    url = "https://github.com/jvolkman/pypackaging.bzl/releases/download/v0.3.0/pypackaging.bzl-v0.3.0.tar.gz",
)
```

Loading `@pypackaging.bzl` from a `.bzl` file needs nothing else. The
`@pypackaging.bzl//:pypackaging` `bzl_library` target also needs the
`bazel_skylib` and `package_metadata` repositories, define them if your
workspace does not have them yet:

```starlark
http_archive(
    name = "bazel_skylib",
    sha256 = "6e78f0e57de26801f6f564fa7c4a48dc8b36873e416257a92bbb0937eeac8446",
    url = "https://github.com/bazelbuild/bazel-skylib/releases/download/1.8.2/bazel-skylib-1.8.2.tar.gz",
)

http_archive(
    name = "package_metadata",
    sha256 = "8f27dc7393e3f3bdc793bdc4ba36d67a63c22cc9d38cc65d3204654974ea4563",
    strip_prefix = "supply-chain-0.0.7/metadata",
    url = "https://github.com/bazel-contrib/supply-chain/releases/download/v0.0.7/supply-chain-v0.0.7.tar.gz",
)
```

Bazel 8 needs `--enable_workspace` to read the `WORKSPACE.bazel` file.

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

# Or evaluate only what is known: the result is True, False or the marker
# that is left to evaluate.
left = pypackaging.markers.evaluate_partial(marker, {"python_version": "3.12"})
pypackaging.markers.to_string(left)  # 'sys_platform == "linux"'

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

`pypackaging.bzl` follows `packaging` 26.3 (plus set-of-extras marker
evaluation from `pypa/packaging#1438`) and `pip`'s `get_supported` wrapper.
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
  - `environment["extra"]` may also be a list, tuple, or set of active extras
    for `==` and `!=` (matching `pypa/packaging#1438`; an empty collection
    evaluates like `""`).
  - `\N{...}` named Unicode escapes in marker string literals are not supported.
  - `markers.evaluate_partial` is not in `packaging`: it evaluates the
    comparisons of the variables that are in `environment` and returns `True`,
    `False` or the marker that is left to evaluate.
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

1. **[pypa/packaging](https://github.com/pypa/packaging)** (baseline: **26.3**,
   Apache-2.0 OR BSD-2-Clause): PEP 440 versions and specifiers, PEP 508
   markers and requirements, PEP 425 compatibility tags, and filename/name
   utilities.
2. **[pypa/pip](https://github.com/pypa/pip)** (MIT): `get_supported` platform
   expansion wrapper logic.

Upstream copyright notices and license texts are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES/](LICENSES).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
