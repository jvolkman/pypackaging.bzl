#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Argument provided by reusable workflow caller
TAG=$1
# The prefix is chosen to match what GitHub generates for source archives
PREFIX="pypackaging.bzl-${TAG:1}"
ARCHIVE="pypackaging.bzl-$TAG.tar.gz"

# NB: configuration for 'git archive' is in /.gitattributes
git archive --format=tar --prefix=${PREFIX}/ ${TAG} | gzip > $ARCHIVE

# Add generated API docs
docs="$(mktemp -d)"; targets="$(mktemp)"
bazel --output_base="$docs" query --output=label --output_file="$targets" 'kind("starlark_doc_extract rule", //...)'
bazel --output_base="$docs" build --target_pattern_file="$targets"
tar --create --auto-compress \
    --directory "$(bazel --output_base="$docs" info bazel-bin)" \
    --file "$GITHUB_WORKSPACE/${ARCHIVE%.tar.gz}.docs.tar.gz" .

cat << EOF
## Using Bzlmod

Requires Bazel 7 or newer with Bzlmod (WORKSPACE is not supported).
Add to your \`MODULE.bazel\` file:

\`\`\`starlark
bazel_dep(name = "pypackaging.bzl", version = "${TAG:1}")
\`\`\`

Then load the API from a \`.bzl\` file:

\`\`\`starlark
load("@pypackaging.bzl", "pypackaging")
\`\`\`

and add \`@pypackaging.bzl//:pypackaging\` to the \`deps\` of your \`bzl_library\` targets.
EOF
