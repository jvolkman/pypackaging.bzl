# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is 0.x, breaking changes are released as minor versions.

## [0.3.0] - 2026-10-16

This release fixes the remaining known differences from packaging 26.2 (see
[Divergences from pypa/packaging](README.md#divergences-from-pypapackaging)
for the intentional ones) and adds the missing pieces of the API.

### Breaking changes

Packaging and Bazel support:

- `load("@pypackaging.bzl", "pypackaging")` (`//:pypackaging.bzl`) and the
  `@pypackaging.bzl//:pypackaging` bzl_library are the only public
  entrypoints. The undocumented `@pypackaging.bzl//pypackaging:pypackaging.bzl`
  and its `//pypackaging:pypackaging` bzl_library are removed, and other
  repositories can no longer load files under `pypackaging/private/` or depend
  on targets there.
- Bazel 7.1 or newer with Bzlmod is required
  (`bazel_compatibility = [">=7.1.0"]`). WORKSPACE is no longer supported and
  the root `WORKSPACE.bazel` file is removed. (Bazel 7.0 can't use the module
  through `local_path_override` without that file.)

Versions and specifiers:

- The second parameter of `specifiers.contains` and `specifiers.set_contains`
  is renamed from `version_str` to `version` (it now also accepts a parsed
  version). Positional callers are unaffected.
- `specifiers.parse` rejects `===` specifiers whose version contains Unicode
  whitespace, like packaging.

Markers:

- `markers.evaluate` uses packaging's string operator table for markers that
  aren't compared as versions: `<` and `>` are always False and `<=`/`>=`
  test equality (they used to compare lexicographically), and `~=`/`===`
  fail with "Undefined comparison".
- `markers.evaluate` fails on an `extra` that isn't a string, list or tuple,
  on a non-string left-hand value, and on environment values that aren't
  strings or collections of strings.
- `markers.parse` rejects a dangling `and`/`or`, invalid string literals and
  `\N{...}` escapes.
- Parsed marker trees changed: string values hold the decoded string (escape
  sequences are processed), the value compared with `extra` is normalized at
  every nesting level, and the variable `python_implementation` is reported
  as `platform_python_implementation`.
- Marker and requirement error messages use packaging's wording and show the
  input with a `~~~^` marker at the error position.

Requirements:

- `requirements.parse` rejects everything packaging rejects: invalid project
  names or extras, malformed specifier lists (`foo==1.0,,<2`, `foo,>=1`), a
  `;` with no marker after it, a leading newline, trailing whitespace other
  than spaces, tabs and a single final newline (`foo\r`, `foo\n\n`), and
  newlines inside the specifier list (`foo>=1.0,\n<2`). The input used to be
  stripped first.
- For URL requirements, `url` keeps a trailing `\r` or `\n` (`foo @ url\n`
  gives `url\n`), like packaging.
- `extras` is de-duplicated (it was already normalized and sorted).

Tags and utilities:

- `utils.canonicalize_name(name, validate = True)` fails for invalid project
  names; `validate` used to be ignored.
- `utils.canonicalize_version` returns a string that isn't a valid version
  unchanged instead of failing, and ignores surrounding whitespace.
- `tags.get_supported` output changed to match packaging and pip:
  - `linux_<arch>` comes after all manylinux and musllinux platforms instead
    of first.
  - Tags are always lowercase.
  - If no platform survives expansion (e.g. `macosx_9_0_x86_64`), the result
    is the tags for platform `any` instead of only `*-none-any`.
  - Custom `macosx*`/`ios*` platform prefixes are expanded like pip, and
    Android and iOS ABIs are normalized.
  - Free-threaded CPython ABIs (`cp313t`) are detected like packaging.
  - The interpreter tag is `impl + version` verbatim, like pip:
    `get_supported(version = "3011")` gives `cp3011-*` tags (it used to give
    `cp311-*`). Versions such as `"311"` are unaffected.
- `tags.parse_tag` and `parse_wheel_filename(...).tags` drop duplicate tags,
  so the list can be shorter, and empty tag components are accepted like
  packaging.
- `utils.parse_wheel_filename` and `utils.parse_sdist_filename` failure
  messages use packaging's wording.

### Added

- `version.to_string` (packaging's `str(Version)`) and `version.try_parse`,
  which returns None instead of failing.
- `specifiers.filter`, `specifiers.set_filter`, `specifiers.prereleases` and
  `specifiers.set_prereleases`, a `prereleases` argument for
  `specifiers.contains`/`set_contains`, and an `installed` argument for
  `set_contains`, with packaging's pre-release rules. Candidates may be
  version strings or parsed versions.
- A `parsed_version` field on parsed specifiers.
- `markers.evaluate` accepts a list or tuple of active extras as
  `environment["extra"]` (a uv-compatible extension): `==` and `!=` test
  membership, and any other operator fails.
- `markers.to_string` and `requirements.to_string` (packaging's `str()`), and
  `marker_str` (the raw marker text), `raw_name` and `raw_extras` fields on
  parsed requirements.
- `tags.priority_map`, `tags.select_compatible` (packaging's
  `create_compatible_tags_selector`) and `tags.tag_str`.
- Third-party notices for pypa/packaging and pypa/pip
  ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).
- CI and BCR presubmit coverage for Bazel 7.x, 8.x and 9.x, and for macOS and
  Windows. The e2e smoke test now covers every module.

### Fixed

Versions and specifiers:

- `~=` matches candidates with a shorter release, e.g. `1` matches `~=1.0.0`.
- `specifiers.contains`/`set_contains` return False for a candidate that
  isn't a valid version instead of failing; only `===` matches it, as a
  string.
- `version.parse` ignores surrounding whitespace, including Unicode
  whitespace.
- `specifiers.parse_set` ignores empty items (`">=1.0,"`), like packaging.
- Unicode whitespace around specifier operators and versions is ignored.
- Versions and specifiers are parsed by hand instead of with regexes. Versions
  with pre-release, post-release, dev or local segments, and wildcard
  specifiers, parse 20 to 30 times faster, and `set_contains` no longer
  re-parses the specifiers' versions (about twice as fast). Parsing a plain
  specifier set such as `>=1.0,<2.0` takes about twice as long as before
  (microseconds per call), because its versions are now parsed up front.

Markers and requirements:

- Version markers (`python_version`, `python_full_version`,
  `implementation_version`, `platform_release`) no longer fail when the value
  isn't a valid version: if `op + value` isn't a valid specifier the
  comparison falls back to the string table, and if the environment value
  isn't a valid version it is False. For example `platform_release >= '5'`
  with a kernel-style release no longer breaks analysis.
- A `python_full_version` ending in `+` is repaired like packaging, and
  `python_implementation` is an alias of `platform_python_implementation`.
- Marker parsing and evaluation no longer stop after 1000 steps, so very long
  or deeply nested markers work.
- Quoted strings in markers are decoded like Python string literals.
- The marker grammar matches packaging, including word boundaries and a single
  trailing newline.
- Requirements are parsed with packaging's PEP 508 grammar: a trailing comma
  in the specifier list and `foo ()` are accepted, and `.*` or local version
  misuse gets packaging's errors. `requirements.parse("name")` is faster than
  in v0.2.2; full requirements with specifiers and a marker take about 1.6
  times as long, because of the stricter grammar.

Tags and utilities:

- `manylinux_X_Y` platforms with a glibc major version other than 2 no longer
  fail, and expand like packaging.
- `[manylinux_X, musllinux_Y]` platform lists expand in packaging's order.
- `utils.parse_wheel_filename` accepts non-ASCII project names and whitespace
  around the version.
- The release `docs.tar.gz` (the BCR `docs_url`) now contains the Stardoc API
  docs; it used to be empty.
- `bazel build @pypackaging.bzl//...` works from a consumer module:
  development-only packages are no longer part of the release archive.

### Removed

- The `re.bzl` dependency.

## [0.2.2] and earlier

See the [GitHub releases](https://github.com/jvolkman/pypackaging.bzl/releases).

[0.3.0]: https://github.com/jvolkman/pypackaging.bzl/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/jvolkman/pypackaging.bzl/releases/tag/v0.2.2
