# Contributing

## Development

- Bazel is pinned in `.bazelversion` (also in `docs/` and `e2e/smoke/`);
  use [Bazelisk](https://github.com/bazelbuild/bazelisk).
- Unit tests: `bazel test //...` in the repository root.
- Smoke test of the public API (also run by BCR presubmit):
  `cd e2e/smoke && bazel test //...`.
- API docs: `docs/pypackaging.md` is generated from docstrings. After
  changing a public docstring, run `cd docs && bazel run //:update` and
  verify with `cd docs && bazel test //...`.
- Formatting and lint: run `pre-commit run --all-files` before sending a
  change (or install the git hook with `pre-commit install`).
- To test against another Bazel version, set `USE_BAZEL_VERSION` (e.g.
  `USE_BAZEL_VERSION=9.x`) and pass `--lockfile_mode=off`. On Bazel 7, pass
  `--ignore_all_rc_files` (`bazel --ignore_all_rc_files test //...`) because
  `tools/preset.bazelrc` targets Bazel 8+.
