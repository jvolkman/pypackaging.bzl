"""Tests for requirements.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/markers:markers.bzl", "markers")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/requirements:requirements.bzl", "requirements")

# buildifier: disable=bzl-visibility
load("//pypackaging/private/utils:utils.bzl", "utils")

def _invalid_requirement_subject_rule_impl(ctx):
    requirements.parse(ctx.attr.req_str)
    return []

_invalid_requirement_subject_rule = rule(
    implementation = _invalid_requirement_subject_rule_impl,
    attrs = {
        "req_str": attr.string(mandatory = True),
    },
)

_EQUAL_DEPENDENCIES = [
    ("packaging>20.1", "packaging>20.1"),
    (
        'requests[security, tests]>=2.8.1,==2.8.*;python_version<"2.7"',
        'requests [security,tests] >= 2.8.1, == 2.8.* ; python_version < "2.7"',
    ),
    (
        'importlib-metadata; python_version<"3.8"',
        'importlib-metadata; python_version<"3.8"',
    ),
    (
        'appdirs>=1.4.4,<2; os_name=="posix" and extra=="testing"',
        'appdirs>=1.4.4,<2; os_name == "posix" and extra == "testing"',
    ),
]

_EQUIVALENT_DEPENDENCIES = [
    ("scikit-learn==1.0.1", "scikit_learn==1.0.1"),
    ("urllib3[secure]", "urllib3[SECURE]"),
    ("fishtank[all-blue]", "fishtank[all_blue]"),
    ("fishtank[all-blue]", "fishtank[all---blue]"),
    ("fishtank[crazy-bunches]", "fishtank[cRazy_BUnches]"),
]

_DIFFERENT_DEPENDENCIES = [
    ("package_one", "package_two"),
    ("packaging>20.1", "packaging>=20.1"),
    ("packaging>20.1", "packaging>21.1"),
    ("packaging>20.1", "package>20.1"),
    (
        'requests[security,tests]>=2.8.1,==2.8.*;python_version<"2.7"',
        'requests [security,tests] >= 2.8.1 ; python_version < "2.7"',
    ),
    (
        'importlib-metadata; python_version<"3.8"',
        "importlib-metadata; python_version<'3.7'",
    ),
    (
        'appdirs>=1.4.4,<2; os_name=="posix" and extra=="testing"',
        "appdirs>=1.4.4,<2; os_name == 'posix' and extra == 'docs'",
    ),
]

_NAMES = [
    "package",
    "pAcKaGe",
    "Package",
    "foo-bar.quux_bAz",
    "installer",
    "android12",
]

_EXTRAS = [
    [],
    ["a"],
    ["a", "b"],
    ["a", "B", "CDEF123"],
]

_URLS_AND_SPECIFIERS = [
    (None, ""),
    ("https://example.com/packagename.zip", ""),
    ("ssh://user:pass%20word@example.com/packagename.zip", ""),
    ("https://example.com/name;v=1.1/?query=foo&bar=baz#blah", ""),
    ("git+ssh://git.example.com/MyProject", ""),
    ("git+ssh://git@github.com:pypa/packaging.git", ""),
    ("git+https://git.example.com/MyProject.git@master", ""),
    ("git+https://git.example.com/MyProject.git@v1.0", ""),
    ("git+https://git.example.com/MyProject.git@refs/pull/123/head", ""),
    ("gopher:/foo/com", ""),
    (None, "==={ws}arbitrarystring"),
    (None, "({ws}==={ws}arbitrarystring{ws})"),
    (None, "=={ws}1.0"),
    (None, "({ws}=={ws}1.0{ws})"),
    (None, "=={ws}1.0-alpha"),
    (None, "<={ws}1!3.0.0.rc2"),
    (None, ">{ws}2.2{ws},{ws}<{ws}3"),
    (None, "(>{ws}2.2{ws},{ws}<{ws}3)"),
]

_MARKERS = [
    None,
    "python_version{ws}>={ws}'3.3'",
    '({ws}python_version{ws}>={ws}"3.4"{ws}){ws}and extra{ws}=={ws}"oursql"',
    "sys_platform{ws}!={ws}'linux' and(os_name{ws}=={ws}'linux' or python_version{ws}>={ws}'3.3'{ws}){ws}",
]

_WHITESPACES = ["", " ", "\t"]

# (input, expected message): packaging 26.2 error messages with "Invalid requirement: " prefix.
_INVALID_REQUIREMENTS = [
    ("", "Invalid requirement: Expected package name at the start of dependency specifier\n    \n    ^"),
    (" ", "Invalid requirement: Expected package name at the start of dependency specifier\n     \n     ^"),
    ("==0.0", "Invalid requirement: Expected package name at the start of dependency specifier\n    ==0.0\n    ^"),
    ("name[bar baz]", "Invalid requirement: Expected comma between extra names\n    name[bar baz]\n             ^"),
    ("name[bar, baz,]", "Invalid requirement: Expected extra name after comma\n    name[bar, baz,]\n                  ^"),
    ("name (>= 1.0", "Invalid requirement: Expected matching RIGHT_PARENTHESIS for LEFT_PARENTHESIS, after version specifier\n    name (>= 1.0\n         ~~~~~~~^"),
    ("name[bar, baz >= 1.0", "Invalid requirement: Expected matching RIGHT_BRACKET for LEFT_BRACKET, after extras\n    name[bar, baz >= 1.0\n        ~~~~~~~~~~^"),
    ("name[bar, baz", "Invalid requirement: Expected matching RIGHT_BRACKET for LEFT_BRACKET, after extras\n    name[bar, baz\n        ~~~~~~~~~^"),
    ("name @ https://example.com/; extra == 'example'", "Invalid requirement: Expected semicolon (after URL and whitespace) or end\n    name @ https://example.com/; extra == 'example'\n           ~~~~~~~~~~~~~~~~~~~~~~^"),
    ("name @ file:///a b", "Invalid requirement: Expected semicolon (after URL and whitespace) or end\n    name @ file:///a b\n           ~~~~~~~~~~^"),
    ("name; (extra == 'example'", "Invalid requirement: Expected matching RIGHT_PARENTHESIS for LEFT_PARENTHESIS, after marker expression\n    name; (extra == 'example'\n          ~~~~~~~~~~~~~~~~~~~^"),
    ("name @ ", "Invalid requirement: Expected URL after @\n    name @ \n           ^"),
    # Invalid names.
    ("-foo", "Invalid requirement: Expected package name at the start of dependency specifier\n    -foo\n    ^"),
    ("foo-", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo-\n       ^"),
    (".foo", "Invalid requirement: Expected package name at the start of dependency specifier\n    .foo\n    ^"),
    ("_foo", "Invalid requirement: Expected package name at the start of dependency specifier\n    _foo\n    ^"),
    ("foo bar", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo bar\n        ^"),
    ("foo 1.0", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo 1.0\n        ^"),
    ("foo,bar", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo,bar\n       ^"),
    ("foo/bar", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo/bar\n       ^"),
    ("foo$bar", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo$bar\n       ^"),
    ("foo!", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo!\n       ^"),
    ("\nfoo", "Invalid requirement: Expected package name at the start of dependency specifier\n    \nfoo\n    ^"),
    ("foo\n\n", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo\n\n\n       ^"),
    ("foo\303\251", "Invalid requirement: Expected package name at the start of dependency specifier\n    foo\303\251\n    ^"),
    # Invalid extras.
    ("foo[bar]]", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo[bar]]\n            ^"),
    ("foo[[bar]]", "Invalid requirement: Expected matching RIGHT_BRACKET for LEFT_BRACKET, after extras\n    foo[[bar]]\n       ~^"),
    ("foo[-bar]", "Invalid requirement: Expected matching RIGHT_BRACKET for LEFT_BRACKET, after extras\n    foo[-bar]\n       ~^"),
    ("foo[_bar]", "Invalid requirement: Expected matching RIGHT_BRACKET for LEFT_BRACKET, after extras\n    foo[_bar]\n       ~^"),
    ("foo[bar-]", "Invalid requirement: Expected matching RIGHT_BRACKET for LEFT_BRACKET, after extras\n    foo[bar-]\n       ~~~~^"),
    ("foo[,bar]", "Invalid requirement: Expected matching RIGHT_BRACKET for LEFT_BRACKET, after extras\n    foo[,bar]\n       ~^"),
    ("foo]", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo]\n       ^"),
    # Invalid specifiers.
    ("foo==1.0,,<2", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo==1.0,,<2\n       ~~~~~~^"),
    ("foo,>=1", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo,>=1\n       ^"),
    ("foo ,", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo ,\n        ^"),
    ("foo>=1.0 <2", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo>=1.0 <2\n       ~~~~~~^"),
    ("foo>1.0<2", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo>1.0<2\n       ~~~~^"),
    ("foo>=1.0.*", "Invalid requirement: .* suffix can only be used with `==` or `!=` operators\n    foo>=1.0.*\n       ~~~~~~^"),
    ("foo>=1.0+abc", "Invalid requirement: Local version label can only be used with `==` or `!=` operators\n    foo>=1.0+abc\n       ~~~~~^"),
    ("foo~=1", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo~=1\n       ^"),
    ("foo==", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo==\n       ^"),
    ("foo =1.0", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo =1.0\n        ^"),
    ("foo ==1.0)", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo ==1.0)\n        ~~~~~^"),
    ("foo (==1.0))", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo (==1.0))\n        ~~~~~~~^"),
    ("foo===a)b", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo===a)b\n       ~~~~^"),
    ("foo==1.0 bar", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo==1.0 bar\n       ~~~~~~^"),
    # Specifier tokens end where packaging's specifier regex stops matching.
    ("foo>=1!", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo>=1!\n       ~~~^"),
    ("foo==1.0a.*", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo==1.0a.*\n       ~~~~~~~^"),
    ("foo<=1.0-", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo<=1.0-\n       ~~~~~^"),
    ("foo==1.0+abc.", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo==1.0+abc.\n       ~~~~~~~~~^"),
    ("foo>1.0+ABC", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo>1.0+ABC\n       ~~~~^"),
    ("foo==1.*.0", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo==1.*.0\n       ~~~~~^"),
    ("foo>=1.0rc1+", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo>=1.0rc1+\n       ~~~~~~~~^"),
    ("foo>=1.0 rc1", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo>=1.0 rc1\n       ~~~~~~^"),
    ("foo~=1.0.*", "Invalid requirement: .* suffix can only be used with `==` or `!=` operators\n    foo~=1.0.*\n       ~~~~~~^"),
    ("foo<=1..0", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo<=1..0\n       ~~~^"),
    ("foo===abc,def", "Invalid specifier: def"),
    ("foo\r", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo\r\n       ^"),
    ("foo>=1.0,\n<2", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo>=1.0,\n<2\n       ~~~~~~^"),
    ("foo\n>=1.0", "Invalid requirement: Expected semicolon (after name with no version specifier) or end\n    foo\n>=1.0\n       ^"),
    # A specifier and a URL.
    ("foo>=1.0 @ https://x", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo>=1.0 @ https://x\n       ~~~~~~^"),
    ("foo (>=1.0) @ https://x", "Invalid requirement: Expected comma (within version specifier), semicolon (after version specifier) or end\n    foo (>=1.0) @ https://x\n        ~~~~~~~~^"),
    ("foo @ https://x @ y", "Invalid requirement: Expected semicolon (after URL and whitespace) or end\n    foo @ https://x @ y\n          ~~~~~~~~~~^"),
    # Empty or invalid markers.
    ("foo;", "Invalid requirement: Expected a marker variable or quoted string\n    foo;\n        ^"),
    ("foo ;", "Invalid requirement: Expected a marker variable or quoted string\n    foo ;\n         ^"),
    ("foo; ", "Invalid requirement: Expected a marker variable or quoted string\n    foo; \n         ^"),
    ("foo[a]; ", "Invalid requirement: Expected a marker variable or quoted string\n    foo[a]; \n            ^"),
    ("foo>=1.0;", "Invalid requirement: Expected a marker variable or quoted string\n    foo>=1.0;\n             ^"),
    ("foo>=1.0 ; ", "Invalid requirement: Expected a marker variable or quoted string\n    foo>=1.0 ; \n               ^"),
    ("foo @ https://x ;", "Invalid requirement: Expected a marker variable or quoted string\n    foo @ https://x ;\n                     ^"),
    ("foo;\n os_name=='nt'", "Invalid requirement: Expected a marker variable or quoted string\n    foo;\n os_name=='nt'\n        ^"),
    ("foo; os_name == 'nt' or", "Invalid requirement: Expected a marker variable or quoted string\n    foo; os_name == 'nt' or\n                           ^"),
    ("foo>=1.0; os_name=='nt' and", "Invalid requirement: Expected a marker variable or quoted string\n    foo>=1.0; os_name=='nt' and\n                               ^"),
    ("foo; os_name == 'nt'; x", "Invalid requirement: Expected end of dependency specifier\n    foo; os_name == 'nt'; x\n                        ^"),
    ("foo; os_name == 'nt' xx", "Invalid requirement: Expected end of dependency specifier\n    foo; os_name == 'nt' xx\n                         ^"),
    ("foo; os_name == '\\'", "Invalid string literal (the closing quote is escaped)"),
    ("foo; bogus == 'x'", "Invalid requirement: Expected a marker variable or quoted string\n    foo; bogus == 'x'\n         ^"),
    ("foo; os_name == '\303\251' and", "Invalid requirement: Expected a marker variable or quoted string\n    foo; os_name == '\303\251' and\n" + " " * 27 + "^"),
    # Caret position counts code points, not UTF-8 bytes.
    ("foo; os_name == '\303\251\342\202\254' xx", "Invalid requirement: Expected end of dependency specifier\n    foo; os_name == '\303\251\342\202\254' xx\n" + " " * 25 + "^"),
]

def _test_parse_requirement_basic_impl(env, _target):
    req = requirements.parse("packaging")
    env.expect.that_str(req.name).equals("packaging")
    env.expect.that_collection(req.extras).has_size(0)
    env.expect.that_bool(req.url == None).equals(True)
    env.expect.that_collection(req.specifier.specs).has_size(0)
    env.expect.that_bool(req.marker == None).equals(True)

def _test_parse_requirement_basic(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_basic_impl)

def _test_parse_requirement_with_extras_impl(env, _target):
    req = requirements.parse("requests[security,tests]")
    env.expect.that_str(req.name).equals("requests")
    env.expect.that_collection(req.extras).contains_exactly(["security", "tests"]).in_order()

def _test_parse_requirement_with_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_with_extras_impl)

def _test_parse_requirement_equality_impl(env, _target):
    for dep1, dep2 in _EQUAL_DEPENDENCIES + _EQUIVALENT_DEPENDENCIES:
        req1 = requirements.parse(dep1)
        req2 = requirements.parse(dep2)

        env.expect.that_str(req1.name).equals(req2.name)
        env.expect.that_collection(req1.extras).contains_exactly(req2.extras)
        env.expect.that_bool(req1.url == req2.url).equals(True)
        env.expect.that_bool(req1.specifier == req2.specifier).equals(True)
        env.expect.that_bool(req1.marker == req2.marker).equals(True)

    for dep1, dep2 in _EQUAL_DEPENDENCIES:
        env.expect.that_str(requirements.to_string(requirements.parse(dep1))).equals(
            requirements.to_string(requirements.parse(dep2)),
        )

def _test_parse_requirement_equality(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_equality_impl)

def _test_parse_requirement_difference_impl(env, _target):
    for dep1, dep2 in _DIFFERENT_DEPENDENCIES:
        req1 = requirements.parse(dep1)
        req2 = requirements.parse(dep2)

        is_equal = (
            req1.name == req2.name and
            req1.extras == req2.extras and
            req1.url == req2.url and
            req1.specifier == req2.specifier and
            req1.marker == req2.marker
        )
        env.expect.that_bool(is_equal).equals(False)

def _test_parse_requirement_difference(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_difference_impl)

def _test_parse_requirement_matrix_impl(env, _target):
    for name in _NAMES:
        expected_name = utils.canonicalize_name(name)
        for extras in _EXTRAS:
            for url, specifier in _URLS_AND_SPECIFIERS:
                for marker in _MARKERS:
                    for ws in _WHITESPACES:
                        parts = [name]
                        if extras:
                            parts.append("[")
                            parts.append(",".join(["{ws}{e}{ws}".format(ws = ws, e = e) for e in sorted(extras)]))
                            parts.append("]")

                        if specifier:
                            parts.append(specifier.replace("{ws}", ws))

                        if url != None:
                            parts.append("@")
                            parts.append(url)

                        if marker != None:
                            parts.append(" ;" if url != None else ";")
                            parts.append(marker.replace("{ws}", ws))

                        req = requirements.parse(ws.join(parts))
                        env.expect.that_str(req.name).equals(expected_name)
                        env.expect.that_str(req.raw_name).equals(name)

def _test_parse_requirement_matrix(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_matrix_impl)

def _test_parse_requirement_marker_with_at_impl(env, _target):
    req = requirements.parse('requests >= 2.0; extra == "my@extra"')
    env.expect.that_str(req.name).equals("requests")
    env.expect.that_bool(req.url == None).equals(True)

    req2 = requirements.parse("pkg @ https://example.com/a;b.zip")
    env.expect.that_str(req2.name).equals("pkg")
    env.expect.that_str(req2.url).equals("https://example.com/a;b.zip")

def _test_parse_requirement_marker_with_at(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_marker_with_at_impl)

def _test_parse_requirement_grammar_impl(env, _target):
    # Empty parenthesized specifier.
    for s in ["foo ()", "foo()", "foo (  )", "foo[a] ( )"]:
        req = requirements.parse(s)
        env.expect.where(req = s).that_str(req.name).equals("foo")
        env.expect.where(req = s).that_collection(req.specifier.specs).has_size(0)

    # A trailing comma in the specifier list is accepted.
    for s in ["foo==1.0,", "foo (==1.0,)", "foo ( ==1.0 , <2 , )", "foo==1.0 , ; os_name == 'a'"]:
        req = requirements.parse(s)
        env.expect.where(req = s).that_str(req.specifier.specs[0].operator).equals("==")
        env.expect.where(req = s).that_str(req.specifier.specs[0].version).equals("1.0")

    # Extras are normalized, de-duplicated and sorted.
    env.expect.that_collection(requirements.parse("Foo_Bar [B,a,b]").extras).contains_exactly(["a", "b"]).in_order()
    env.expect.that_collection(requirements.parse("foo[Extra_Name, extra.name]").extras).contains_exactly(["extra-name"])
    env.expect.that_collection(requirements.parse("foo[]").extras).has_size(0)
    env.expect.that_collection(requirements.parse("foo[ ]").extras).has_size(0)

    # Identifier edge cases accepted by upstream.
    for s, name in [("a", "a"), ("1", "1"), ("foo_", "foo-"), ("foo-_", "foo-"), ("Zope.Interface>=5", "zope-interface")]:
        env.expect.where(req = s).that_str(requirements.parse(s).name).equals(name)
    env.expect.that_collection(requirements.parse("foo[a_]").extras).contains_exactly(["a-"])

    # Whitespace: spaces/tabs anywhere between tokens, a single trailing newline.
    for s in ["  foo  ", "\tfoo", "foo\n", "foo ==1 \n", "foo\t>=\t1.0"]:
        env.expect.where(req = s).that_str(requirements.parse(s).name).equals("foo")

    # URLs: everything up to whitespace, including ';' and '@'.
    req = requirements.parse("foo@https://x/a;b@c")
    env.expect.that_str(req.url).equals("https://x/a;b@c")
    env.expect.that_bool(req.specifier == None).equals(True)
    env.expect.that_bool(req.marker == None).equals(True)
    req = requirements.parse("foo [bar] @ https://x/y.whl\t; os_name == 'nt'")
    env.expect.that_str(req.url).equals("https://x/y.whl")
    env.expect.that_collection(req.extras).contains_exactly(["bar"])
    env.expect.that_bool(markers.evaluate(req.marker, {"os_name": "nt"})).equals(True)

    # Non-ASCII text survives intact (Bazel 7's no-argument strip() would
    # remove the trailing UTF-8 continuation byte of "\303\240").
    req = requirements.parse(" foo @ https://x/\303\240 ")
    env.expect.that_str(req.url).equals("https://x/\303\240")
    env.expect.that_str(req.req_str).equals("foo @ https://x/\303\240")
    env.expect.that_str(requirements.to_string(req)).equals("foo @ https://x/\303\240")

    # `===` with an empty version is a valid specifier.
    req = requirements.parse("foo===")
    env.expect.that_str(req.specifier.specs[0].operator).equals("===")
    env.expect.that_str(req.specifier.specs[0].version).equals("")

def _test_parse_requirement_grammar(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_grammar_impl)

def _test_parse_requirement_specifier_tokens_impl(env, _target):
    # Expected values are from packaging 26.2.
    cases = [
        ("foo>=1!2.0", [(">=", "1!2.0")]),
        ("foo==1.0.*", [("==", "1.0.*")]),
        ("foo!=v1.0+Local.1", [("!=", "v1.0+Local.1")]),
        ("foo~=1!1.0rc1.post2.dev3", [("~=", "1!1.0rc1.post2.dev3")]),
        ("foo>=1.0dev-", [(">=", "1.0dev-")]),
        ("foo>=1.0.post", [(">=", "1.0.post")]),
        ("foo==1.0+abc", [("==", "1.0+abc")]),
        ("foo>=\302\2401.0", [(">=", "1.0")]),
        ("foo===\302\240x", [("===", "x")]),
        ("foo(===a)", [("===", "a")]),
        ("foo== 1.0 ,!= 1.1", [("==", "1.0"), ("!=", "1.1")]),
        ("foo==1.0.0RC1", [("==", "1.0.0RC1")]),
        ("foo==V1.0", [("==", "V1.0")]),
        ("foo==1.0-1", [("==", "1.0-1")]),
        ("foo==1.0_post-1", [("==", "1.0_post-1")]),
    ]
    for s, expected in cases:
        specs = requirements.parse(s).specifier.specs
        env.expect.where(req = s).that_collection([(spec.operator, spec.version) for spec in specs]).contains_exactly(expected).in_order()

def _test_parse_requirement_specifier_tokens(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_specifier_tokens_impl)

def _test_parse_requirement_raw_names_impl(env, _target):
    req = requirements.parse("Foo_Bar [B, a,b] >= 1")
    env.expect.that_str(req.raw_name).equals("Foo_Bar")
    env.expect.that_collection(req.raw_extras).contains_exactly(["B", "a", "b"]).in_order()
    env.expect.that_collection(req.extras).contains_exactly(["a", "b"]).in_order()

    # The bare-name fast path returns the same struct as the full parser.
    for name in ["requests", "Zope.Interface", "a", "1", "foo-_bar"]:
        fast = requirements.parse(name)
        full = requirements.parse(name + " ")
        env.expect.where(req = name).that_bool(fast == full).equals(True)
        env.expect.where(req = name).that_str(fast.raw_name).equals(name)

    # to_string uses the struct's fields, not the original text.
    req = requirements.parse("foo[x]>=1")
    fields = {k: getattr(req, k) for k in dir(req) if k not in ("to_json", "to_proto")}
    fields["raw_name"] = "Bar"
    renamed = struct(**fields)
    env.expect.that_str(requirements.to_string(renamed)).equals("Bar[x]>=1")

def _test_parse_requirement_raw_names(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_raw_names_impl)

def _test_parse_requirement_marker_str_impl(env, _target):
    env.expect.that_bool(requirements.parse("foo>=1").marker_str == None).equals(True)
    env.expect.that_bool(requirements.parse("foo @ https://x").marker_str == None).equals(True)
    cases = [
        ("foo>=1;python_version<'3.8'", "python_version<'3.8'"),
        ("foo ; os_name == 'nt' and extra=='x'  ", "os_name == 'nt' and extra=='x'"),
        ("foo @ https://x/a;b ;\t(os_name == 'nt')\n", "(os_name == 'nt')"),
        ("foo; extra == 'my@extra'", "extra == 'my@extra'"),
    ]
    for s, expected in cases:
        env.expect.where(req = s).that_str(requirements.parse(s).marker_str).equals(expected)

def _test_parse_requirement_marker_str(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_requirement_marker_str_impl)

def _test_requirement_to_string_impl(env, _target):
    # Expected values are `str(packaging.requirements.Requirement(...))` (26.2).
    cases = [
        ("packaging", "packaging"),
        ("Foo_Bar[B,a,b]>=1;extra=='X_y'", "Foo_Bar[B,a,b]>=1; extra == \"x-y\""),
        ("foo [ a , b ] ( >= 1 , < 2 ) ; os_name == 'a'", "foo[a,b]<2,>=1; os_name == \"a\""),
        ("foo>=1,>=1", "foo>=1"),
        ("foo>=1.0,>=1", "foo>=1"),
        ("foo==1.0,", "foo==1.0"),
        ("foo ()", "foo"),
        ("foo[a,a]", "foo[a]"),
        ("foo ===  1.0", "foo===1.0"),
        ("foo@https://x", "foo @ https://x"),
        ("foo @ https://x/a;os_name=='a'", "foo @ https://x/a;os_name=='a'"),
        ("foo @ https://x ; extra=='A_B'", "foo @ https://x ; extra == \"a-b\""),
        ("foo == 1 ;python_version>'3'", "foo==1; python_version > \"3\""),
        ("requests[security, tests]>=2.8.1,==2.8.*;python_version<\"2.7\"", "requests[security,tests]==2.8.*,>=2.8.1; python_version < \"2.7\""),
    ]
    for s, expected in cases:
        env.expect.where(req = s).that_str(requirements.to_string(requirements.parse(s))).equals(expected)

def _test_requirement_to_string(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_requirement_to_string_impl)

def _make_error_message_test_impl(message):
    def _impl(env, target):
        env.expect.that_target(target).failures().contains_predicate(matching.contains(message))

    return _impl

def requirements_test_suite(name):
    """Sets up the requirement parsing tests.

    Args:
        name: the name of the test suite
    """
    test_suite(
        name = name + "_standard",
        tests = [
            _test_parse_requirement_basic,
            _test_parse_requirement_with_extras,
            _test_parse_requirement_equality,
            _test_parse_requirement_difference,
            _test_parse_requirement_matrix,
            _test_parse_requirement_marker_with_at,
            _test_parse_requirement_grammar,
            _test_parse_requirement_specifier_tokens,
            _test_parse_requirement_marker_str,
            _test_parse_requirement_raw_names,
            _test_requirement_to_string,
        ],
    )

    invalid_test_names = []

    # buildifier: disable=enumerate
    for i, (req, message) in enumerate(_INVALID_REQUIREMENTS):
        test_name = name + "_invalid_{}".format(i)
        util.helper_target(_invalid_requirement_subject_rule, name = test_name + "_subject", req_str = req)
        analysis_test(name = test_name, target = test_name + "_subject", expect_failure = True, impl = _make_error_message_test_impl(message))
        invalid_test_names.append(test_name)

    native.test_suite(
        name = name,
        tests = [":" + name + "_standard"] + [":" + n for n in invalid_test_names],
    )
