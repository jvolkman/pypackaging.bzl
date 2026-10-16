#!/usr/bin/env bash
# Turns the version proposed by smlx/ccv into the version to release.
#
# ccv bumps the major version for `feat!:`/`fix!:` commits and
# `BREAKING CHANGE:` footers, even while the module is still at 0.x: it would
# turn v0.2.3 into v1.0.0. While the major version is 0, SemVer says the
# minor version carries breaking changes, so this script turns such a bump
# into a minor bump (v0.2.3 -> v0.3.0). Real major releases (from 1.x
# onward) are refused here and must be tagged by hand; see CONTRIBUTING.md.
#
# Inputs (environment):
#   CCV_TAG   ccv's `new-tag-version` output, e.g. v1.0.0
#   CCV_TYPE  ccv's `new-tag-version-type` output: major, minor or patch
# Output (stdout, in $GITHUB_OUTPUT format):
#   new-tag-version=<tag to create>
#   new-tag-version-type=<major|minor|patch>

set -o errexit -o nounset -o pipefail

: "${CCV_TAG:?}" "${CCV_TYPE:?}"

semver_re='^v([0-9]+)\.([0-9]+)\.([0-9]+)$'

new_tag="$CCV_TAG"
new_type="$CCV_TYPE"

if [[ "$CCV_TYPE" == "major" ]]; then
    prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' HEAD)"
    if [[ ! "$prev" =~ $semver_re ]]; then
        echo "ERROR: cannot parse previous tag '$prev'" >&2
        exit 1
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    if [[ "v$((major + 1)).0.0" != "$CCV_TAG" ]]; then
        echo "ERROR: ccv proposed $CCV_TAG, but the previous tag found by git describe is $prev" >&2
        exit 1
    fi
    if [[ "$major" != "0" ]]; then
        echo "ERROR: refusing to release major version $CCV_TAG automatically." >&2
        echo "Tag it manually if this is intended (see CONTRIBUTING.md)." >&2
        exit 1
    fi
    new_tag="v0.$((minor + 1)).0"
    new_type="minor"
    echo "Breaking changes since $prev while at 0.x: releasing $new_tag instead of $CCV_TAG" >&2
fi

if git rev-parse --quiet --verify "refs/tags/$new_tag" > /dev/null; then
    echo "ERROR: tag $new_tag already exists" >&2
    exit 1
fi

echo "new-tag-version=$new_tag"
echo "new-tag-version-type=$new_type"
