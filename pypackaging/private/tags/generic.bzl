"""Generic platform tag generation.

Derived from pypa/packaging: packaging/tags.py (Apache 2.0 / BSD).
See README.md for details.
"""

visibility(["//", "//pypackaging/..."])

def generic_tags(interpreter, abis, platforms):
    """Generates generic tags.

    Like packaging's `Tag`, the generated tags are lowercase.

    Args:
        interpreter: The interpreter string.
        abis: A list of ABIs.
        platforms: A list of platforms.

    Returns:
        A list of generic tag strings.
    """
    tags = []
    abis_copy = list(abis) if abis else []
    if "none" not in abis_copy:
        abis_copy.append("none")

    interpreter = interpreter.lower()
    platforms = [p.lower() for p in platforms]
    for abi in abis_copy:
        abi = abi.lower()
        for platform in platforms:
            tags.append("{}-{}-{}".format(interpreter, abi, platform))
    return tags
