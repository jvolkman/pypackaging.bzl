"""Executes a subset of Starlark with CPython to measure what the code does.

Bazel does not have a way to benchmark or to count the steps that the Starlark
interpreter executes, but the `.bzl` files that only have pure functions are
almost valid Python, so we can execute them with CPython and count the
executed lines instead. The absolute numbers are not what Bazel would report,
however they are deterministic and they change when the algorithm changes.

Only what is needed by the measured files is supported:
* `load()` of the `.bzl` files.
* `struct`, `fail`, `type`, `visibility` and `str.elems`.
"""

import re
import sys
import types

_LOAD = re.compile(r"^load\((.*?)\)[ \t]*(#[^\n]*)?$", flags=re.MULTILINE | re.DOTALL)

_TYPE_NAMES = {
    bool: "bool",
    dict: "dict",
    int: "int",
    list: "list",
    set: "set",
    str: "string",
    tuple: "tuple",
    type(None): "NoneType",
}


class StarlarkFail(Exception):
    """Raised when the Starlark code calls `fail`."""


class _Struct:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


def _fail(*args):
    raise StarlarkFail(" ".join([str(a) for a in args]))


def _type(value):
    name = _TYPE_NAMES.get(type(value))
    if name:
        return name
    if isinstance(value, types.FunctionType):
        return "function"
    if isinstance(value, _Struct):
        return "struct"
    return "builtin_function_or_method"


def _parse_label(label, repo, package):
    """Return the (repo, package, name) of the label that is loaded by a file.

    Args:
        label: the label, e.g. `@repo`, `@repo//pkg:file.bzl`,
            `//pkg:file.bzl` or `:file.bzl`.
        repo: the repository of the file that has the `load()`.
        package: the package of the file that has the `load()`.
    """
    if label.startswith(":"):
        return repo, package, label[1:]
    if label.startswith("@"):
        repo, _, label = label[1:].partition("//")
        if not label:
            # `@repo` is `@repo//:repo`.
            return repo, "", repo
    else:
        label = label[2:]
    package, _, name = label.partition(":")
    return repo, package, name


class Shim:
    """Loads `.bzl` files as Python modules."""

    def __init__(self, resolve):
        """Create the shim.

        Args:
            resolve: a function to get the file path from the name of the
                repository (an empty string for the main one) and the path
                relative to the root of the repository.
        """
        self._resolve = resolve
        self._modules = {}

    def load(self, label, repo="", package=""):
        """Load the file and return its globals.

        Args:
            label: the label of the `.bzl` file, e.g. `//:workloads.bzl`.
            repo: the repository that the label is relative to.
            package: the package that the label is relative to.

        Returns:
            The dict of the globals of the module.
        """
        repo, package, name = _parse_label(label, repo, package)
        key = (repo, package, name)
        if key in self._modules:
            return self._modules[key]

        path = self._resolve(repo, "/".join([package, name]) if package else name)

        # The strings in Bazel are sequences of bytes.
        with open(path, encoding="latin-1") as f:
            src = f.read()

        module = {
            "struct": _Struct,
            "fail": _fail,
            "visibility": lambda *_: None,
            "_shim_type": _type,
        }
        for match in _LOAD.finditer(src):
            args = [a.strip() for a in match.group(1).split(",") if a.strip()]
            dep_module = self.load(args[0].strip('"'), repo, package)
            for arg in args[1:]:
                symbol_name, _, symbol = arg.partition("=")
                symbol = (symbol or symbol_name).strip().strip('"')
                module[symbol_name.strip().strip('"')] = dep_module[symbol]

        # Keep the line numbers the same as in the original file.
        src = _LOAD.sub(lambda m: "\n" * m.group(0).count("\n"), src)
        src = src.replace(".elems()", "")
        src = re.sub(r"\btype\(", "_shim_type(", src)

        exec(compile(src, path, "exec"), module)  # pylint: disable=exec-used
        self._modules[key] = module
        return module


def count_steps(fn):
    """Count the lines of the `.bzl` files that are executed by `fn`."""
    steps = [0]

    def trace(frame, event, _arg):
        if not frame.f_code.co_filename.endswith(".bzl"):
            return None
        if event == "line":
            steps[0] += 1
        return trace

    sys.settrace(trace)
    try:
        fn()
    finally:
        sys.settrace(None)
    return steps[0]
