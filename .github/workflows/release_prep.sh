#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Argument provided by reusable workflow caller
TAG=$1
VERSION="${TAG#v}"
# The prefix is chosen to match what GitHub generates for source archives
PREFIX="pypackaging.bzl-${VERSION}"
ARCHIVE="pypackaging.bzl-$TAG.tar.gz"

# NB: configuration for 'git archive' is in /.gitattributes
git archive --format=tar --prefix=${PREFIX}/ ${TAG} | gzip > $ARCHIVE
SHA=$(shasum -a 256 $ARCHIVE | awk '{print $1}')

# Add generated API docs
docs="$(mktemp -d)"; targets="$(mktemp)"
bazel --output_base="$docs" query --output=label --output_file="$targets" 'kind("starlark_doc_extract rule", //...)'
if [ ! -s "$targets" ]; then
    echo "ERROR: no starlark_doc_extract targets found; the docs archive would be empty" >&2
    exit 1
fi
bazel --output_base="$docs" build --target_pattern_file="$targets"
bazel_bin="$(bazel --output_base="$docs" info bazel-bin)"
# Only ship the extracted API protos, not other build outputs.
(cd "$bazel_bin" && find . -name '*.binaryproto' -print0 | LC_ALL=C sort -z) > "$targets"
if [ ! -s "$targets" ]; then
    echo "ERROR: building the starlark_doc_extract targets produced no .binaryproto files" >&2
    exit 1
fi
tar --create --auto-compress \
    --directory "$bazel_bin" \
    --null --files-from "$targets" \
    --file "$GITHUB_WORKSPACE/${ARCHIVE%.tar.gz}.docs.tar.gz"

REPO="${GITHUB_REPOSITORY:-jvolkman/pypackaging.bzl}"
CHANGELOG_URL="https://github.com/${REPO}/blob/${TAG}/CHANGELOG.md"
CHANGELOG_HEADING=""
CHANGELOG_SECTION=""

if git cat-file -e "${TAG}:CHANGELOG.md" 2>/dev/null; then
    CHANGELOG_FILE="$(mktemp)"
    git show "${TAG}:CHANGELOG.md" > "${CHANGELOG_FILE}"
    CHANGELOG_HEADING=$(
        awk -v ver="${VERSION}" '
            /^## / {
                if ($0 == "## [" ver "]" || index($0, "## [" ver "] ") == 1 || $0 == "## " ver || index($0, "## " ver " ") == 1) {
                    print substr($0, 4)
                    exit
                }
            }
        ' "${CHANGELOG_FILE}"
    )
    CHANGELOG_SECTION=$(
        awk -v ver="${VERSION}" '
            /^## / || /^\[[^]]+\]: / {
                if (found) exit
                if ($0 == "## [" ver "]" || index($0, "## [" ver "] ") == 1 || $0 == "## " ver || index($0, "## " ver " ") == 1) {
                    found = 1
                    next
                }
            }
            found {
                if (!started && $0 == "") next
                started = 1
                lines[++n] = $0
            }
            END {
                while (n > 0 && lines[n] == "") n--
                for (i = 1; i <= n; i++) print lines[i]
            }
        ' "${CHANGELOG_FILE}"
    )
    rm -f "${CHANGELOG_FILE}"

    if [[ -n "${CHANGELOG_HEADING}" ]]; then
        ANCHOR=$(printf '%s' "${CHANGELOG_HEADING}" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9_-')
        CHANGELOG_URL="${CHANGELOG_URL}#${ANCHOR}"
    fi

    echo "See the [CHANGELOG](${CHANGELOG_URL})."
    echo ""
    if [[ -n "${CHANGELOG_SECTION}" ]]; then
        echo "## Release Notes"
        echo ""
        printf '%s\n\n' "${CHANGELOG_SECTION}"
    fi
fi

cat << EOF
## Using Bzlmod

Requires Bazel 7.1 or newer.
Add to your \`MODULE.bazel\` file:

\`\`\`starlark
bazel_dep(name = "pypackaging.bzl", version = "${VERSION}")
\`\`\`

## Using WORKSPACE

Add to your \`WORKSPACE.bazel\` file, see the README for the repositories that
the \`bzl_library\` target needs:

\`\`\`starlark
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "pypackaging.bzl",
    sha256 = "${SHA}",
    strip_prefix = "${PREFIX}",
    url = "https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE}",
)
\`\`\`

## Usage

Then load the API from a \`.bzl\` file:

\`\`\`starlark
load("@pypackaging.bzl", "pypackaging")
\`\`\`

and add \`@pypackaging.bzl//:pypackaging\` to the \`deps\` of your \`bzl_library\` targets.
EOF
