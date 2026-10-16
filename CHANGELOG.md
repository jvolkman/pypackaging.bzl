# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is 0.x, breaking changes are released as minor versions.

## [0.3.0] - Unreleased

<!-- TODO(v0.3.0): integration adds the algorithm fixes and API changes from the
version/specifiers, markers/requirements and tags/utils branches. -->

### Changed

- **Breaking:** `load("@pypackaging.bzl", "pypackaging")` (`//:pypackaging.bzl`)
  and the `@pypackaging.bzl//:pypackaging` bzl_library are the only public
  entrypoints. Other repositories can no longer load files under
  `pypackaging/private/` or depend on the targets there.
- **Breaking:** Bazel 7 or newer with Bzlmod is required
  (`bazel_compatibility = [">=7.0.0"]`). WORKSPACE is no longer supported.

### Removed

- **Breaking:** the undocumented second entrypoint
  `@pypackaging.bzl//pypackaging:pypackaging.bzl` and its
  `@pypackaging.bzl//pypackaging:pypackaging` bzl_library.
- The root `WORKSPACE.bazel` file, and the WORKSPACE snippet in the release
  notes.

### Fixed

- The release `docs.tar.gz` (the BCR `docs_url`) now contains the Stardoc API
  docs; it used to be empty.
- `bazel build @pypackaging.bzl//...` works from a consumer module:
  development-only packages are no longer part of the release archive.

### Added

- Third-party notices for pypa/packaging and pypa/pip
  ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).
- CI and BCR presubmit coverage for Bazel 7.x, 8.x and 9.x, and for macOS and
  Windows. The e2e smoke test now covers every module.

## [0.2.2] and earlier

See the [GitHub releases](https://github.com/jvolkman/pypackaging.bzl/releases).

[0.3.0]: https://github.com/jvolkman/pypackaging.bzl/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/jvolkman/pypackaging.bzl/releases/tag/v0.2.2
