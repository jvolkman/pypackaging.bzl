"""PEP 508 Dependency Specification Parsing.

Derived from pypa/packaging: packaging/requirements.py (Apache 2.0 / BSD).
"""

load("//pypackaging/private/markers:markers.bzl", "markers")
load("//pypackaging/private/specifiers:specifiers.bzl", "specifiers")
load("//pypackaging/private/utils:utils.bzl", "utils")

def _make_requirement(name, url, extras, specifier, marker, req_str = ""):
    return struct(
        name = name,
        url = url,
        extras = extras,
        specifier = specifier,
        marker = marker,
        req_str = req_str,
    )

def _parse_requirement(req_str):
    """Parses a requirement string.

    Args:
        req_str: The requirement string to parse.

    Returns:
        A struct representing the parsed requirement.
    """
    req_str = req_str.strip()
    if not req_str:
        fail("Empty requirement string")

    # 1. Extract Marker
    marker_str = None
    at_idx = req_str.find("@")
    semi_idx = req_str.find(";")

    if at_idx != -1 and (semi_idx == -1 or at_idx < semi_idx):
        # URL requirement
        left = req_str[:at_idx].strip()
        right = req_str[at_idx + 1:].strip()
        if not right:
            fail("Missing URL after @")

        # Find first whitespace in right part
        ws_idx = -1

        # buildifier: disable=string-iteration
        for i in range(len(right)):
            if right[i] in " \t":
                ws_idx = i
                break

        if ws_idx == -1:
            url = right
            marker_str = None
        else:
            url = right[:ws_idx]
            rest = right[ws_idx:].strip()
            if rest.startswith(";"):
                marker_str = rest[1:].strip()
            elif rest:
                fail("Expected semicolon or end after URL")

        req_no_marker = left
        name_extras = left
        specifier = None
    else:
        # Specifier requirement
        semi_idx = req_str.find(";")
        if semi_idx != -1:
            marker_str = req_str[semi_idx + 1:].strip()
            req_no_marker = req_str[:semi_idx].strip()
        else:
            req_no_marker = req_str

        # Find first operator
        op_idx = -1

        # buildifier: disable=string-iteration
        for i in range(len(req_no_marker)):
            if req_no_marker[i] in "=><!~":
                op_idx = i
                break

        if op_idx != -1:
            name_extras = req_no_marker[:op_idx].strip()
            specifier_str = req_no_marker[op_idx:].strip()

            # Handle enclosing parentheses: name (>=1.0)
            if name_extras.endswith("("):
                name_extras = name_extras[:-1].strip()
                if specifier_str.endswith(")"):
                    specifier_str = specifier_str[:-1].strip()
                else:
                    fail("Unclosed parenthesis in specifier")

            specifier = specifiers.parse_set(specifier_str)
        else:
            name_extras = req_no_marker
            specifier = specifiers.parse_set("")

        url = None

    if not name_extras:
        fail("Missing requirement name")

    # Parse name_extras
    if name_extras.endswith("]"):
        bracket_idx = name_extras.find("[")
        if bracket_idx != -1:
            name = name_extras[:bracket_idx].strip()
            extras_str = name_extras[bracket_idx + 1:-1].strip()
            if extras_str:
                raw_extras = extras_str.split(",")
                extras = []
                for e in raw_extras:
                    e_stripped = e.strip()
                    if not e_stripped:
                        fail("Empty extra name")

                    # Simple validation: no spaces
                    if " " in e_stripped or "\t" in e_stripped:
                        fail("Invalid extra name: '{}'".format(e_stripped))
                    extras.append(utils.canonicalize_name(e_stripped))
                extras = sorted(extras)
            else:
                extras = []
        else:
            fail("Invalid requirement name/extras: {}".format(name_extras))
    else:
        if "[" in name_extras:
            fail("Unclosed bracket in extras")
        name = name_extras
        extras = []

    name = utils.canonicalize_name(name)

    parsed_marker = None
    if marker_str:
        parsed_marker = markers.parse(marker_str)

    return _make_requirement(name, url, extras, specifier, parsed_marker, req_str)

requirements = struct(
    parse = _parse_requirement,
)
