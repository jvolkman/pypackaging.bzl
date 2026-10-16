# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is 0.x, breaking changes are released as minor versions.

## [0.3.0] - 2026-10-16

Aligns version, specifier, marker, requirement, tag, and filename handling with
`packaging` 26.2 and removes the `re.bzl` dependency.

### Breaking changes

Packaging and Bazel support:

- `load("@pypackaging.bzl", "pypackaging")` (`//:pypackaging.bzl`) and the
  `@pypackaging.bzl//:pypackaging` `bzl_library` are the only public
  entrypoints. `@pypackaging.bzl//pypackaging:pypackaging.bzl` is removed, and
  `//pypackaging/private/...` is private.
- Bazel 7.1 or newer with Bzlmod is required (`bazel_compatibility = [">=7.1.0"]`).
  `WORKSPACE.bazel` is removed.

Versions and specifiers:

- The second parameter of `specifiers.contains` and `specifiers.set_contains`
  is renamed from `version_str` to `version` (accepting either a string or a
  parsed version struct).
- `specifiers.parse` rejects `===` specifiers whose version contains Unicode
  whitespace.

Markers:

- `markers.evaluate` uses packaging's string operator table for non-version
  markers: `<` and `>` return `False`, `<=` and `>=` test equality, and `~=`
  and `===` fail with `"Undefined comparison"`.
- `markers.evaluate` validates environment value types and restricts list/tuple
  `extra` values to `==` and `!=`.
- `markers.parse` rejects dangling boolean operators, invalid string literals,
  and `\N{...}` escapes.
- Parsed marker string nodes hold decoded string values, `extra` comparisons
  are normalized at all nesting levels, and `python_implementation` normalizes
  to `platform_python_implementation`.

Requirements:

- `requirements.parse` enforces packaging's PEP 508 grammar and error messages.
- `extras` is deduplicated as well as normalized and sorted.

Tags and utilities:

- `utils.canonicalize_name(name, validate = True)` fails on invalid PEP 508
  project names.
- `utils.canonicalize_version` returns invalid version strings unchanged instead
  of failing, and strips surrounding whitespace.
- `tags.get_supported` matches packaging 26.2 and pip:
  - Places `linux_<arch>` after all `manylinux` and `musllinux` tags.
  - Lowercases all generated tags.
  - Falls back to `["any"]` when platform expansion produces no platforms.
  - Expands custom `macosx*`/`ios*` platform prefixes and normalizes Android
    and iOS ABIs.
  - Detects free-threaded CPython ABIs (`cp313t`) after filtering `abi3`/`none`.
- `tags.parse_tag` and `utils.parse_wheel_filename(...).tags` deduplicate
  expanded tags and accept empty tag components.

### Added

- `version.to_string` and `version.try_parse`.
- `specifiers.filter`, `specifiers.set_filter`, `specifiers.prereleases`, and
  `specifiers.set_prereleases`, plus `prereleases` and `installed` parameters on
  `contains`/`set_contains` and `parsed_version` on specifier structs.
- `markers.to_string` and `requirements.to_string`, plus `marker_str`,
  `raw_name`, and `raw_extras` fields on parsed requirement structs.
- Support for list/tuple `environment["extra"]` in `markers.evaluate`.
- `tags.priority_map`, `tags.select_compatible`, and `tags.tag_str`.
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and upstream license files under
  [LICENSES/](LICENSES/).

### Fixed

- `~=` zero-pads short candidate releases (e.g. `1` matches `~=1.0.0`).
- `specifiers.contains` and `specifiers.set_contains` return `False` for invalid
  PEP 440 candidate strings instead of failing (except `===`).
- `version.parse` and `specifiers.parse` strip ASCII and Unicode whitespace
  across all supported Bazel versions.
- `specifiers.parse_set` ignores empty comma-separated items (`">=1.0,"`).
- Version-keyed markers (`python_version`, `python_full_version`,
  `implementation_version`, `platform_release`) fall back to string comparison
  when the RHS is not a valid specifier and return `False` when the environment
  value is not a valid PEP 440 version.
- `python_full_version` values ending in `+` have `local` appended before
  evaluation.
- Marker parsing and evaluation no longer cap iteration at 1000 steps.
- `manylinux_X_Y` platforms with glibc major version >= 3 are supported.
- Release `docs.tar.gz` archives now ship extracted `.binaryproto` Stardoc
  targets, and dev-only packages are excluded from the release archive.

### Removed

- The `re.bzl` dependency.

## [0.2.2] and earlier

See the [GitHub releases](https://github.com/jvolkman/pypackaging.bzl/releases).

[0.3.0]: https://github.com/jvolkman/pypackaging.bzl/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/jvolkman/pypackaging.bzl/releases/tag/v0.2.2
