"""Python packaging utilities in Starlark."""

load("//pypackaging/private/markers:markers.bzl", _markers = "markers")
load("//pypackaging/private/requirements:requirements.bzl", _requirements = "requirements")
load("//pypackaging/private/specifiers:specifiers.bzl", _specifiers = "specifiers")
load("//pypackaging/private/tags:tags.bzl", _tags = "tags")
load("//pypackaging/private/utils:utils.bzl", _utils = "utils")
load("//pypackaging/private/version:version.bzl", _version = "version")

pypackaging = struct(
    markers = _markers,
    requirements = _requirements,
    specifiers = _specifiers,
    tags = _tags,
    utils = _utils,
    version = _version,
)
