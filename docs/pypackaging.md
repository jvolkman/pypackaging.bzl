<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Python packaging utilities in Starlark.

<a id="pypackaging.markers.evaluate"></a>

## pypackaging.markers.evaluate

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.markers.evaluate(<a href="#pypackaging.markers.evaluate-markers">markers</a>, <a href="#pypackaging.markers.evaluate-environment">environment</a>)
</pre>

Evaluates a parsed marker expression against an environment.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.markers.evaluate-markers"></a>markers |  The parsed marker tree (list).   |  none |
| <a id="pypackaging.markers.evaluate-environment"></a>environment |  A dict mapping environment variables to values.   |  none |

**RETURNS**

True if the markers evaluate to true, False otherwise.


<a id="pypackaging.markers.parse"></a>

## pypackaging.markers.parse

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.markers.parse(<a href="#pypackaging.markers.parse-marker_str">marker_str</a>)
</pre>

Parses a PEP 508 marker string into an AST-like structure.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.markers.parse-marker_str"></a>marker_str |  The marker string to parse.   |  none |

**RETURNS**

A list representing the parsed marker tree.


<a id="pypackaging.specifiers.contains"></a>

## pypackaging.specifiers.contains

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.contains(<a href="#pypackaging.specifiers.contains-spec">spec</a>, <a href="#pypackaging.specifiers.contains-version_str">version_str</a>)
</pre>

Checks if a version satisfies a specifier.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.contains-spec"></a>spec |  The specifier struct.   |  none |
| <a id="pypackaging.specifiers.contains-version_str"></a>version_str |  The version string to check.   |  none |

**RETURNS**

True if the version satisfies the specifier, False otherwise.


<a id="pypackaging.specifiers.parse"></a>

## pypackaging.specifiers.parse

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.parse(<a href="#pypackaging.specifiers.parse-spec_str">spec_str</a>)
</pre>

Parses a single specifier string.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.parse-spec_str"></a>spec_str |  The specifier string to parse.   |  none |

**RETURNS**

A struct representing the parsed specifier.


<a id="pypackaging.specifiers.parse_set"></a>

## pypackaging.specifiers.parse_set

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.parse_set(<a href="#pypackaging.specifiers.parse_set-spec_set_str">spec_set_str</a>)
</pre>

Parses a comma-separated set of specifiers.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.parse_set-spec_set_str"></a>spec_set_str |  The specifier set string to parse.   |  none |

**RETURNS**

A struct representing the parsed specifier set.


<a id="pypackaging.specifiers.set_contains"></a>

## pypackaging.specifiers.set_contains

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.set_contains(<a href="#pypackaging.specifiers.set_contains-spec_set">spec_set</a>, <a href="#pypackaging.specifiers.set_contains-version_str">version_str</a>)
</pre>

Checks if a version satisfies all specifiers in the set.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.set_contains-spec_set"></a>spec_set |  The specifier set struct.   |  none |
| <a id="pypackaging.specifiers.set_contains-version_str"></a>version_str |  The version string to check.   |  none |

**RETURNS**

True if the version satisfies all specifiers, False otherwise.


<a id="pypackaging.tags.get_supported"></a>

## pypackaging.tags.get_supported

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.tags.get_supported(<a href="#pypackaging.tags.get_supported-version">version</a>, <a href="#pypackaging.tags.get_supported-platforms">platforms</a>, <a href="#pypackaging.tags.get_supported-impl">impl</a>, <a href="#pypackaging.tags.get_supported-abis">abis</a>)
</pre>

Return a list of supported tags.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.tags.get_supported-version"></a>version |  The Python version string (e.g., "311").   |  `None` |
| <a id="pypackaging.tags.get_supported-platforms"></a>platforms |  A list of allowed platforms.   |  `None` |
| <a id="pypackaging.tags.get_supported-impl"></a>impl |  The interpreter implementation prefix (e.g., "cp").   |  `None` |
| <a id="pypackaging.tags.get_supported-abis"></a>abis |  A list of ABIs.   |  `None` |

**RETURNS**

A list of compatibility tag strings.


<a id="pypackaging.tags.parse_tag"></a>

## pypackaging.tags.parse_tag

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.tags.parse_tag(<a href="#pypackaging.tags.parse_tag-tag">tag</a>, <a href="#pypackaging.tags.parse_tag-validate_order">validate_order</a>)
</pre>

Parses the provided tag into a list of Tag structs.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.tags.parse_tag-tag"></a>tag |  The tag to parse (e.g., "py3-none-any").   |  none |
| <a id="pypackaging.tags.parse_tag-validate_order"></a>validate_order |  Whether to check if compressed tag set components are in sorted order.   |  `False` |

**RETURNS**

A list of Tag structs.


<a id="pypackaging.utils.canonicalize_name"></a>

## pypackaging.utils.canonicalize_name

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.utils.canonicalize_name(<a href="#pypackaging.utils.canonicalize_name-name">name</a>, <a href="#pypackaging.utils.canonicalize_name-validate">validate</a>)
</pre>

Takes a valid Python package or extra name, and returns the normalized form of it.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.utils.canonicalize_name-name"></a>name |  The name to normalize.   |  none |
| <a id="pypackaging.utils.canonicalize_name-validate"></a>validate |  Whether to validate the name.   |  `False` |

**RETURNS**

The normalized name.


<a id="pypackaging.utils.canonicalize_version"></a>

## pypackaging.utils.canonicalize_version

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.utils.canonicalize_version(<a href="#pypackaging.utils.canonicalize_version-version_input">version_input</a>, <a href="#pypackaging.utils.canonicalize_version-strip_trailing_zero">strip_trailing_zero</a>)
</pre>

Return a canonical form of a version as a string.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.utils.canonicalize_version-version_input"></a>version_input |  The version to canonicalize (string or Version struct).   |  none |
| <a id="pypackaging.utils.canonicalize_version-strip_trailing_zero"></a>strip_trailing_zero |  Whether to strip trailing zeros.   |  `True` |

**RETURNS**

The canonicalized version string.


<a id="pypackaging.utils.is_normalized_name"></a>

## pypackaging.utils.is_normalized_name

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.utils.is_normalized_name(<a href="#pypackaging.utils.is_normalized_name-name">name</a>)
</pre>

Check if a name is already normalized.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.utils.is_normalized_name-name"></a>name |  The name to check.   |  none |

**RETURNS**

True if normalized, False otherwise.


<a id="pypackaging.utils.parse_sdist_filename"></a>

## pypackaging.utils.parse_sdist_filename

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.utils.parse_sdist_filename(<a href="#pypackaging.utils.parse_sdist_filename-filename">filename</a>)
</pre>

Parses the filename of a sdist file.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.utils.parse_sdist_filename-filename"></a>filename |  The filename to parse.   |  none |

**RETURNS**

A struct containing name and version.


<a id="pypackaging.utils.parse_wheel_filename"></a>

## pypackaging.utils.parse_wheel_filename

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.utils.parse_wheel_filename(<a href="#pypackaging.utils.parse_wheel_filename-filename">filename</a>, <a href="#pypackaging.utils.parse_wheel_filename-validate_order">validate_order</a>)
</pre>

Parses the filename of a wheel file.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.utils.parse_wheel_filename-filename"></a>filename |  The filename to parse.   |  none |
| <a id="pypackaging.utils.parse_wheel_filename-validate_order"></a>validate_order |  Whether to validate tag order.   |  `False` |

**RETURNS**

A struct containing name, version, build, and tags.


<a id="pypackaging.version.get_public_key"></a>

## pypackaging.version.get_public_key

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.version.get_public_key(<a href="#pypackaging.version.get_public_key-v">v</a>)
</pre>

Returns the comparison key for the public version (without local segment).

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.version.get_public_key-v"></a>v |  <p align="center"> - </p>   |  none |


<a id="pypackaging.version.parse"></a>

## pypackaging.version.parse

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.version.parse(<a href="#pypackaging.version.parse-version_str">version_str</a>)
</pre>

Parses a version string into a struct.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.version.parse-version_str"></a>version_str |  The version string to parse.   |  none |

**RETURNS**

A struct representing the parsed version.


