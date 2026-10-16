# Contributing

## Development

- Bazel is pinned in `.bazelversion` (also in `docs/` and `e2e/smoke/`);
  use [Bazelisk](https://github.com/bazelbuild/bazelisk).
- Unit tests: `bazel test //...` in the repository root. They use
  [rules_testing](https://github.com/bazelbuild/rules_testing) and live in
  `pypackaging/tests/`.
- Smoke test of the public API, run by the BCR presubmit on every platform:
  `cd e2e/smoke && bazel test //...`.
- API docs: `docs/pypackaging.md` is generated from the docstrings. After
  changing a public docstring, run `cd docs && bazel run //:update`.
  `bazel test //...` in `docs/` checks that it is up to date.
- Formatting and lint: install [pre-commit](https://pre-commit.com) and run
  `pre-commit install`, or run `pre-commit run --all-files` before
  sending a change. CI runs the same hooks (buildifier, buildifier-lint,
  prettier, yamlfmt, typos, ...).
- To test against another Bazel version, set `USE_BAZEL_VERSION` (e.g.
  `USE_BAZEL_VERSION=9.x`) and pass `--lockfile_mode=off` so the lockfiles
  aren't rewritten. `tools/preset.bazelrc` is generated for the pinned
  version, so on Bazel 7 run the root tests with
  `bazel --ignore_all_rc_files test //...`.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/). The
release workflow derives the next version from them:

- `fix: ...` gives a patch release;
- `feat: ...` gives a minor release;
- `feat!: ...` / `fix!: ...` or a `BREAKING CHANGE: ...` footer marks a
  breaking change. While the version is 0.x this gives a minor release,
  e.g. v0.2.3 -> v0.3.0.

Other types (`docs:`, `ci:`, `test:`, `chore:`, ...) don't trigger a
release on their own. Note that the version tool only recognizes `!` on
`feat` and `fix`, so use a `BREAKING CHANGE:` footer to mark a breaking
change in a commit of any other type.

## Releasing

1. Add the release's entries to `CHANGELOG.md`.
2. Run the **Tag a Release** workflow (`.github/workflows/tag.yaml`) from
   the Actions tab. It runs [smlx/ccv](https://github.com/smlx/ccv) to
   compute the next version. `.github/workflows/next_version.sh` then
   turns a breaking-change bump on 0.x into a minor bump, because ccv would
   otherwise propose v1.0.0. The workflow pushes the tag and calls
   `release.yaml`, which creates the GitHub release (source archive, Stardoc
   `docs.tar.gz`, attestations) and opens the Bazel Central Registry PR.

To release a specific version by hand (for example the first 1.0.0, which
the workflow refuses to tag automatically), push the tag from a clone:

```sh
git tag v1.0.0 <commit>
git push origin v1.0.0
```

A tag pushed by a person triggers `release.yaml` directly, through its
`push: tags` trigger. A tag pushed by the workflow with `GITHUB_TOKEN` doesn't
trigger it, which is why `tag.yaml` calls `release.yaml` itself.
