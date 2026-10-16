<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Python packaging utilities in Starlark.

<a id="pypackaging.markers.evaluate"></a>

## pypackaging.markers.evaluate

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.markers.evaluate(<a href="#pypackaging.markers.evaluate-markers">markers</a>, <a href="#pypackaging.markers.evaluate-environment">environment</a>)
</pre>

Evaluates a parsed marker expression against an environment.

Semantics follow `packaging.markers.Marker.evaluate` (packaging 26.2):

- `python_version`, `python_full_version`, `implementation_version` and
  `platform_release` are compared as PEP 440 versions when `op + value` is a
  valid specifier (pre-releases always match). If it is not a valid
  specifier, the comparison falls back to the string table below; if the
  version being tested is not a valid version, the comparison is False. A
  `python_full_version` ending in "+" gets "local" appended first.
- All other comparisons use upstream's string table: `==`, `!=`, `in` and
  `not in` as usual, `<` and `>` are always False, `<=` and `>=` mean
  equality, and `~=` and `===` fail ("Undefined comparison").
- `extra`, `extras` and `dependency_groups` values are normalized (PEP 685
  / PEP 735) on both sides.

There is no default environment: every variable the marker references must
be present, except `extra`, which defaults to "" (None is also treated as
""). Callers must supply `extras` / `dependency_groups` (as lists of
strings) when markers use them.

Non-standard extension (uv-compatible): `environment["extra"]` may be a
list or tuple of strings, the set of active extras (uv also uses this for
its conflict tokens). Each element is normalized. `extra == X`,
`X == extra` and `===` are True iff X is in the set; `!=` is True iff it is
not. An empty list therefore makes `==` False and `!=` True. Any other
operator with a list-valued `extra` fails.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.markers.evaluate-markers"></a>markers |  The parsed marker tree (list), as returned by `parse`. An empty list evaluates to True.   |  none |
| <a id="pypackaging.markers.evaluate-environment"></a>environment |  A dict mapping marker variable names (underscore form) to values.   |  none |

**RETURNS**

True if the markers evaluate to true, False otherwise.


<a id="pypackaging.markers.parse"></a>

## pypackaging.markers.parse

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.markers.parse(<a href="#pypackaging.markers.parse-marker_str">marker_str</a>)
</pre>

Parses a PEP 508 marker string into an AST-like structure.

The grammar, error conditions and value processing follow
`packaging.markers.Marker` (packaging 26.2): quoted strings are decoded like
Python string literals (`\N{...}` escapes are not supported), dotted
variable names are mapped to their underscore form, `python_implementation`
is an alias for `platform_python_implementation`, and the value compared
against `extra` is normalized (PEP 685) at every nesting level.

Unlike upstream, the empty string is accepted and returns `[]`, which
`evaluate` treats as always true. Whitespace-only input is rejected.

Invalid input fails with an upstream-style message that shows the marker
and a caret at the error position.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.markers.parse-marker_str"></a>marker_str |  The marker string to parse.   |  none |

**RETURNS**

A list representing the parsed marker tree. Each comparison is a tuple
  `(lhs, op, rhs)` where `lhs`/`rhs` are `struct(type, value)` with
  `type` either "variable" or "string" and `op` a string such as "==",
  "in" or "not in"; boolean operators are the strings "and"/"or"; and
  parenthesized groups are nested lists.


<a id="pypackaging.markers.to_string"></a>

## pypackaging.markers.to_string

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.markers.to_string(<a href="#pypackaging.markers.to_string-markers">markers</a>)
</pre>

Serializes a parsed marker tree like upstream `str(Marker)`.

Variables are emitted in their normalized form and string values are
always double-quoted (without escaping, like upstream). Redundant
parentheses around a whole group are dropped.

Divergence: upstream also drops the parentheses of a doubly parenthesized
nested group, e.g. `a and ((b or c))` becomes `a and b or c`, which changes
the meaning. This implementation keeps them: `a and (b or c)`.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.markers.to_string-markers"></a>markers |  A parsed marker tree (from `parse`).   |  none |

**RETURNS**

The normalized marker string ("" for an empty tree).


<a id="pypackaging.requirements.parse"></a>

## pypackaging.requirements.parse

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.requirements.parse(<a href="#pypackaging.requirements.parse-req_str">req_str</a>)
</pre>

Parses a PEP 508 requirement (dependency specifier) string.

Accepts and rejects exactly what `packaging.requirements.Requirement`
(packaging 26.2) does, failing with an upstream-style message that shows
the input and a caret at the error position.

Differences from upstream's `Requirement` object:

- `name` is normalized (`utils.canonicalize_name`), and `extras` is a
  sorted, de-duplicated list of normalized extra names.
- `specifier` is the result of `specifiers.parse_set` for name-based
  requirements (with no specifiers it has an empty `specs` list), but
  `None` for URL requirements.
- `marker` is the parsed marker tree (see `markers.parse`), or `None` when
  the requirement has no marker. `marker_str` is the marker text exactly as
  written (without surrounding whitespace), or `None`.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.requirements.parse-req_str"></a>req_str |  The requirement string to parse.   |  none |

**RETURNS**

A struct with fields:
    name: The normalized project name.
    url: The URL for `name @ url` requirements, else None.
    extras: Sorted list of unique, normalized extras.
    specifier: A specifier set struct, or None for URL requirements.
    marker: The parsed marker tree, or None.
    marker_str: The raw marker string, or None.
    req_str: The input string with surrounding whitespace stripped.


<a id="pypackaging.requirements.to_string"></a>

## pypackaging.requirements.to_string

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.requirements.to_string(<a href="#pypackaging.requirements.to_string-req">req</a>)
</pre>

Serializes a parsed requirement like upstream `str(Requirement)`.

The project name and extras are emitted as originally written (extras
sorted and de-duplicated), specifiers are sorted and de-duplicated, and the
marker is normalized with `markers.to_string`.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.requirements.to_string-req"></a>req |  A requirement struct returned by `parse`.   |  none |

**RETURNS**

The normalized requirement string.


<a id="pypackaging.specifiers.contains"></a>

## pypackaging.specifiers.contains

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.contains(<a href="#pypackaging.specifiers.contains-spec">spec</a>, <a href="#pypackaging.specifiers.contains-version">version</a>, <a href="#pypackaging.specifiers.contains-prereleases">prereleases</a>)
</pre>

Checks if a version satisfies a specifier.

This is upstream's `Specifier.contains`. Pre-releases are accepted unless
`prereleases` is False: there are no other candidates to prefer, so the
PEP 440 rule to exclude them doesn't apply. A `version` that is not a valid
PEP 440 version never matches, except that `===` compares it as a string.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.contains-spec"></a>spec |  The specifier struct.   |  none |
| <a id="pypackaging.specifiers.contains-version"></a>version |  The version to check: a string or a struct returned by `version.parse`.   |  none |
| <a id="pypackaging.specifiers.contains-prereleases"></a>prereleases |  If False, pre-release versions never match. None (the default) and True accept them.   |  `None` |

**RETURNS**

True if the version satisfies the specifier, False otherwise.


<a id="pypackaging.specifiers.filter"></a>

## pypackaging.specifiers.filter

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.filter(<a href="#pypackaging.specifiers.filter-spec">spec</a>, <a href="#pypackaging.specifiers.filter-versions">versions</a>, <a href="#pypackaging.specifiers.filter-prereleases">prereleases</a>)
</pre>

Filters versions that satisfy a specifier.

This is upstream's `Specifier.filter`. With `prereleases = None`, whether
pre-releases are included comes from `prereleases(spec)`; if that is not
True, matching pre-releases are only returned when no matching final
release (or post-release) was found.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.filter-spec"></a>spec |  The specifier struct.   |  none |
| <a id="pypackaging.specifiers.filter-versions"></a>versions |  A list of versions: strings or structs returned by `version.parse`. Strings that are not valid PEP 440 versions only match `===`.   |  none |
| <a id="pypackaging.specifiers.filter-prereleases"></a>prereleases |  True to include pre-releases, False to exclude them, or None for the default behavior described above.   |  `None` |

**RETURNS**

The matching items of `versions`, in order.


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
| <a id="pypackaging.specifiers.parse-spec_str"></a>spec_str |  The specifier string to parse. Fails if it isn't a valid PEP 440 specifier.   |  none |

**RETURNS**

A struct representing the parsed specifier, with these fields:

  * `operator`: one of `~=`, `==`, `!=`, `<=`, `>=`, `<`, `>`, `===`.
  * `version`: the version string as written (e.g. `1.0`, `1.0.*`).
  * `parsed_version`: the parsed version (see `version.parse`), without
    the `.*` suffix for wildcard specifiers. None for `===`.


<a id="pypackaging.specifiers.parse_set"></a>

## pypackaging.specifiers.parse_set

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.parse_set(<a href="#pypackaging.specifiers.parse_set-spec_set_str">spec_set_str</a>)
</pre>

Parses a comma-separated set of specifiers.

Like `packaging.specifiers.SpecifierSet`, empty items are ignored, so
`">=1.0,"`, `">=1.0,,<2"` and `" "` are accepted.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.parse_set-spec_set_str"></a>spec_set_str |  The specifier set string to parse.   |  none |

**RETURNS**

A struct with a `specs` field: the list of parsed specifiers (see
  `parse`), in order.


<a id="pypackaging.specifiers.prereleases"></a>

## pypackaging.specifiers.prereleases

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.prereleases(<a href="#pypackaging.specifiers.prereleases-spec">spec</a>)
</pre>

Returns whether a specifier implies that pre-releases are allowed.

This is upstream's `Specifier.prereleases` for a specifier constructed
without an explicit `prereleases` argument: False for `!=` and for `==`
with a wildcard, None for `===` with a version that isn't valid PEP 440,
and otherwise whether the specifier's version is a pre-release.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.prereleases-spec"></a>spec |  The specifier struct.   |  none |

**RETURNS**

True, False, or None.


<a id="pypackaging.specifiers.set_contains"></a>

## pypackaging.specifiers.set_contains

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.set_contains(<a href="#pypackaging.specifiers.set_contains-spec_set">spec_set</a>, <a href="#pypackaging.specifiers.set_contains-version">version</a>, <a href="#pypackaging.specifiers.set_contains-prereleases">prereleases</a>, <a href="#pypackaging.specifiers.set_contains-installed">installed</a>)
</pre>

Checks if a version satisfies all specifiers in the set.

This is upstream's `SpecifierSet.contains`. Pre-releases are accepted unless
`prereleases` is False. A `version` that is not a valid PEP 440 version
only matches if every specifier in the set is `===` and matches it as a
string. An empty set matches everything.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.set_contains-spec_set"></a>spec_set |  The specifier set struct.   |  none |
| <a id="pypackaging.specifiers.set_contains-version"></a>version |  The version to check: a string or a struct returned by `version.parse`.   |  none |
| <a id="pypackaging.specifiers.set_contains-prereleases"></a>prereleases |  If False, pre-release versions never match. None (the default) and True accept them.   |  `None` |
| <a id="pypackaging.specifiers.set_contains-installed"></a>installed |  If True, a pre-release version is accepted even if `prereleases` is False.   |  `None` |

**RETURNS**

True if the version satisfies all specifiers, False otherwise.


<a id="pypackaging.specifiers.set_filter"></a>

## pypackaging.specifiers.set_filter

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.set_filter(<a href="#pypackaging.specifiers.set_filter-spec_set">spec_set</a>, <a href="#pypackaging.specifiers.set_filter-versions">versions</a>, <a href="#pypackaging.specifiers.set_filter-prereleases">prereleases</a>)
</pre>

Filters versions that satisfy all specifiers in the set.

This is upstream's `SpecifierSet.filter`. With `prereleases = None`,
pre-releases are included if `set_prereleases(spec_set)` is True;
otherwise matching pre-releases are only returned when no matching final
release (or post-release) was found, as PEP 440 recommends.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.set_filter-spec_set"></a>spec_set |  The specifier set struct.   |  none |
| <a id="pypackaging.specifiers.set_filter-versions"></a>versions |  A list of versions: strings or structs returned by `version.parse`. Strings that are not valid PEP 440 versions only match if every specifier is `===` (or the set is empty), and are never treated as pre-releases.   |  none |
| <a id="pypackaging.specifiers.set_filter-prereleases"></a>prereleases |  True to include pre-releases, False to exclude them, or None for the default behavior described above.   |  `None` |

**RETURNS**

The matching items of `versions`, in order.


<a id="pypackaging.specifiers.set_prereleases"></a>

## pypackaging.specifiers.set_prereleases

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.specifiers.set_prereleases(<a href="#pypackaging.specifiers.set_prereleases-spec_set">spec_set</a>)
</pre>

Returns whether a specifier set implies that pre-releases are allowed.

This is upstream's `SpecifierSet.prereleases` for a set constructed without
an explicit `prereleases` argument: True if any specifier implies
pre-releases (see `prereleases`), otherwise None.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.specifiers.set_prereleases-spec_set"></a>spec_set |  The specifier set struct.   |  none |

**RETURNS**

True or None.


<a id="pypackaging.tags.get_supported"></a>

## pypackaging.tags.get_supported

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.tags.get_supported(<a href="#pypackaging.tags.get_supported-version">version</a>, <a href="#pypackaging.tags.get_supported-platforms">platforms</a>, <a href="#pypackaging.tags.get_supported-impl">impl</a>, <a href="#pypackaging.tags.get_supported-abis">abis</a>)
</pre>

Return a list of supported tags, most preferred first.

A port of pip's `get_supported()` (`pip/_internal/utils/compatibility_tags.py`)
on top of packaging's `cpython_tags()`, `generic_tags()` and
`compatible_tags()`. Each requested platform is expanded into the
platforms it is compatible with, as pip does for `--platform`:

* `macosx*_X_Y_<arch>`: packaging's `mac_platforms((X, Y), arch)`. As in
  pip, a custom prefix such as `macosxcustom_` is kept.
* `ios*_X_Y_<multiarch>`: packaging's `ios_platforms()`, likewise.
* `android_N_<abi>`: packaging's `android_platforms()`.

Differences from pip, all because this runs at analysis time without a
host interpreter:

* `manylinux_X_Y_<arch>`, legacy `manylinux1/2010/2014_<arch>` and
  `musllinux_X_Y_<arch>` are fully expanded, as packaging does for the host
  platform in `_linux_platforms()`: every older glibc/musl version, the
  legacy aliases, an `armv8l` -> `armv7l` fallback, and finally
  `linux_<arch>` (after all other expanded platforms). pip only maps
  `manylinux2014` -> `manylinux2010`/`manylinux1` and `manylinux2010` ->
  `manylinux1`. As in packaging, nothing older than glibc 2.17 is emitted
  on architectures other than x86_64/i686, so `manylinux2010_aarch64`
  expands to just `linux_aarch64`.
* `platforms=None`, `[]`, or platforms that all expand to nothing (e.g.
  `macosx_9_0_x86_64`) mean `["any"]`, and `abis=None` means no
  interpreter-specific ABIs; pip uses the host's platforms and ABIs.
  `version` is required and `impl` defaults to `"cp"`.
* Every `"abi3"` and `"none"` entry in `abis` is ignored for CPython;
  packaging only removes the first occurrence of each.

Tags are lowercase, like packaging's `Tag`.


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

A compressed tag set such as `py2.py3-none-any` expands to one Tag per
combination. packaging returns a `frozenset`; this returns a list without
duplicates, in the order the components appear in the tag. Tag structs
have `interpreter`, `abi` and `platform` fields, are lowercased like
packaging's `Tag`, and compare equal by value.

Like packaging, empty components (e.g. `py3--any`) are not rejected; they
produce tags with empty fields that never match a supported tag.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.tags.parse_tag-tag"></a>tag |  The tag to parse (e.g., "py3-none-any").   |  none |
| <a id="pypackaging.tags.parse_tag-validate_order"></a>validate_order |  Whether to check if compressed tag set components are in sorted order.   |  `False` |

**RETURNS**

A list of Tag structs.


<a id="pypackaging.tags.priority_map"></a>

## pypackaging.tags.priority_map

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.tags.priority_map(<a href="#pypackaging.tags.priority_map-supported">supported</a>)
</pre>

Builds a `{tag string: rank}` map from an ordered list of supported tags.

Rank 0 is the most preferred tag. If a tag appears more than once, its
first (best) rank is kept. Build the map once and reuse it with
`select_compatible`, or look up `tag_str(tag)` directly, instead of
scanning the supported tag list for every candidate.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.tags.priority_map-supported"></a>supported |  An ordered list of supported tags, most preferred first, as returned by `get_supported`. Entries may be tag strings (which are lowercased) or Tag structs. Compressed tag sets are not expanded.   |  none |

**RETURNS**

A dict mapping each tag string to its rank.


<a id="pypackaging.tags.select_compatible"></a>

## pypackaging.tags.select_compatible

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.tags.select_compatible(<a href="#pypackaging.tags.select_compatible-supported">supported</a>, <a href="#pypackaging.tags.select_compatible-tagged">tagged</a>)
</pre>

Orders things by their best-matching supported tag.

A port of packaging's `create_compatible_tags_selector()`. Things with no
supported tag are dropped. The rest are sorted by the rank of their best
supported tag; ties keep their input order. To pick the best wheel, take
the first element of the result.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.tags.select_compatible-supported"></a>supported |  An ordered list of supported tags (most preferred first), or a map returned by `priority_map`. Pass a precomputed map when calling this repeatedly with the same supported tags.   |  none |
| <a id="pypackaging.tags.select_compatible-tagged"></a>tagged |  A list of `(thing, tags)` tuples, where `tags` is a list of Tag structs (e.g. `parse_wheel_filename(f).tags`) or tag strings.   |  none |

**RETURNS**

The compatible things, best match first.


<a id="pypackaging.tags.tag_str"></a>

## pypackaging.tags.tag_str

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.tags.tag_str(<a href="#pypackaging.tags.tag_str-tag">tag</a>)
</pre>

Returns the `interpreter-abi-platform` string form of a Tag struct.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.tags.tag_str-tag"></a>tag |  A Tag struct, as returned by `parse_tag`.   |  none |

**RETURNS**

The tag string, e.g. "py3-none-any".


<a id="pypackaging.utils.canonicalize_name"></a>

## pypackaging.utils.canonicalize_name

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.utils.canonicalize_name(<a href="#pypackaging.utils.canonicalize_name-name">name</a>, <a href="#pypackaging.utils.canonicalize_name-validate">validate</a>)
</pre>

Takes a valid Python package or extra name, and returns the normalized form of it.

Lowercases the name and replaces runs of `-`, `_` and `.` with a single `-`
(PEP 503). Starlark's `lower()` only lowercases ASCII letters, so unlike
packaging, non-ASCII letters are left unchanged. Valid distribution names
are ASCII-only, so this only matters when `validate` is False.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.utils.canonicalize_name-name"></a>name |  The name to normalize.   |  none |
| <a id="pypackaging.utils.canonicalize_name-validate"></a>validate |  If True, `fail()` unless `name` is a valid distribution name per the core metadata spec (ASCII letters and digits, with `.`, `_` and `-` allowed except at the start and end), like packaging raising `InvalidName`.   |  `False` |

**RETURNS**

The normalized name.


<a id="pypackaging.utils.canonicalize_version"></a>

## pypackaging.utils.canonicalize_version

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.utils.canonicalize_version(<a href="#pypackaging.utils.canonicalize_version-version_input">version_input</a>, <a href="#pypackaging.utils.canonicalize_version-strip_trailing_zero">strip_trailing_zero</a>)
</pre>

Return a canonical form of a version as a string.

With `strip_trailing_zero = False`, the result is the normalized PEP 440
form, i.e. packaging's `str(Version(...))`.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.utils.canonicalize_version-version_input"></a>version_input |  The version to canonicalize (string or Version struct). A string that isn't a valid PEP 440 version is returned unchanged, like packaging. Leading and trailing whitespace is ignored.   |  none |
| <a id="pypackaging.utils.canonicalize_version-strip_trailing_zero"></a>strip_trailing_zero |  Whether to strip trailing zeros from the release segment (e.g. "1.0.0" -> "1").   |  `True` |

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

The returned struct has these fields:

* `name`: the project name, normalized with `canonicalize_name`.
* `version`: the Version struct. Its `version_str` field is the version
  text exactly as it appears in the filename. For the normalized form, use
  `version.to_string(version)`.


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

The returned struct has these fields:

* `name`: the project name, normalized with `canonicalize_name`.
* `version`: the Version struct. Its `version_str` field is the version
  text exactly as it appears in the filename (e.g. `1.0.0.RC1`). For the
  normalized form (packaging's `str(version)`, e.g. `1.0.0rc1`), use
  `version.to_string(version)`.
* `build`: `()` or a `(number, suffix)` build tag tuple, e.g. `(1, "abc")`.
* `tags`: a list of Tag structs, as returned by `tags.parse_tag`.

Like packaging, the project name may contain non-ASCII characters. Any
non-ASCII character is accepted, where packaging only accepts Unicode
word characters.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.utils.parse_wheel_filename-filename"></a>filename |  The filename to parse.   |  none |
| <a id="pypackaging.utils.parse_wheel_filename-validate_order"></a>validate_order |  Whether to fail if compressed tag set components aren't in sorted order (PEP 425).   |  `False` |

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

Leading and trailing whitespace is ignored, like `packaging.version.Version`.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.version.parse-version_str"></a>version_str |  The version string to parse. Fails if it isn't a valid PEP 440 version.   |  none |

**RETURNS**

A struct representing the parsed version, with these fields:

  * `version_str`: the input string without surrounding whitespace.
  * `epoch`: the epoch as an int.
  * `release`: the release segment as a tuple of ints.
  * `pre`: `("a" | "b" | "rc", int)` or None.
  * `post`: `("post", int)` or None.
  * `dev`: `("dev", int)` or None.
  * `local`: the local segment as a tuple of lowercase strings and ints,
    or None.
  * `key`: a sort key. Compare keys to compare versions.
  * `is_prerelease`, `is_postrelease`, `is_devrelease`: bools.


<a id="pypackaging.version.to_string"></a>

## pypackaging.version.to_string

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.version.to_string(<a href="#pypackaging.version.to_string-v">v</a>)
</pre>

Returns the normalized string form of a parsed version.

This is upstream's `str(Version)`, e.g. `1.0.0-RC1` becomes `1.0.0rc1` and
`v1!2.0-post3` becomes `1!2.0.post3`. Trailing zeros are kept.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.version.to_string-v"></a>v |  A version struct returned by `parse`.   |  none |

**RETURNS**

The normalized version string.


<a id="pypackaging.version.try_parse"></a>

## pypackaging.version.try_parse

<pre>
load("@pypackaging.bzl", "pypackaging")

pypackaging.version.try_parse(<a href="#pypackaging.version.try_parse-version_str">version_str</a>)
</pre>

Like `parse_version`, but returns None instead of failing on invalid input.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pypackaging.version.try_parse-version_str"></a>version_str |  The version string to parse.   |  none |

**RETURNS**

A struct representing the parsed version, or None if `version_str` is
  not a valid PEP 440 version.


