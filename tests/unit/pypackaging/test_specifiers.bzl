"""Tests for specifiers.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private/pypackaging/specifiers:specifiers.bzl", "specifiers")

def _test_specifier_basic_impl(env, _target):
    spec = specifiers.parse(">=1.0")
    env.expect.that_str(spec.operator).equals(">=")
    env.expect.that_str(spec.version).equals("1.0")

def _test_specifier_basic(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_specifier_basic_impl)

def _test_specifier_contains_impl(env, _target):
    # >=
    spec = specifiers.parse(">=1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "0.9")).equals(False)

    # <=
    spec = specifiers.parse("<=1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "0.9")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(False)

    # ==
    spec = specifiers.parse("==1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.0.0")).equals(True)  # Normalized
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(False)

    # == with wildcard
    spec = specifiers.parse("==1.*")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.9.1")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "2.0")).equals(False)

    spec = specifiers.parse("==1.2.*")
    env.expect.that_bool(specifiers.contains(spec, "1.2.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.2.3")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.3.0")).equals(False)

    # !=
    spec = specifiers.parse("!=1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(True)

    # != with wildcard
    spec = specifiers.parse("!=1.*")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "2.0")).equals(True)

    # >
    spec = specifiers.parse(">1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(False)

    # >V MUST NOT allow a post-release of the specified version unless the specified version is itself a post-release.
    env.expect.that_bool(specifiers.contains(spec, "1.0.post1")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "1.1.post1")).equals(True)

    # <
    spec = specifiers.parse("<1.0")
    env.expect.that_bool(specifiers.contains(spec, "0.9")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(False)

    # <V MUST NOT allow a pre-release of the specified version unless the specified version is itself a pre-release.
    env.expect.that_bool(specifiers.contains(spec, "1.0a1")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "0.9a1")).equals(True)

    # ~=
    spec = specifiers.parse("~=2.2")
    env.expect.that_bool(specifiers.contains(spec, "2.2")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "2.7")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "3.0")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "2.1")).equals(False)

    spec = specifiers.parse("~=1.4.5")
    env.expect.that_bool(specifiers.contains(spec, "1.4.5")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.4.6")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.5.0")).equals(False)
    env.expect.that_bool(specifiers.contains(spec, "1.4.4")).equals(False)

    # ===
    spec = specifiers.parse("===1.0")
    env.expect.that_bool(specifiers.contains(spec, "1.0")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "1.0.0")).equals(False)  # Exact string match
    env.expect.that_bool(specifiers.contains(spec, "1.1")).equals(False)

    spec = specifiers.parse("===abc")
    env.expect.that_bool(specifiers.contains(spec, "abc")).equals(True)
    env.expect.that_bool(specifiers.contains(spec, "ABC")).equals(True)  # Case-insensitive

_UPSTREAM_SPECIFIERS_PASS = [
    # Test the equality operation
    ("2.0", "==2"),
    ("2.0", "==2.0"),
    ("2.0", "==2.0.0"),
    ("2.0+deadbeef", "==2"),
    ("2.0+deadbeef", "==2.0"),
    ("2.0+deadbeef", "==2.0.0"),
    ("2.0+deadbeef", "==2+deadbeef"),
    ("2.0+deadbeef", "==2.0+deadbeef"),
    ("2.0+deadbeef", "==2.0.0+deadbeef"),
    ("2.0+deadbeef.0", "==2.0.0+deadbeef.00"),
    # Test the equality operation with a prefix
    ("2.dev1", "==2.*"),
    ("2a1", "==2.*"),
    ("2a1.post1", "==2.*"),
    ("2b1", "==2.*"),
    ("2b1.dev1", "==2.*"),
    ("2c1", "==2.*"),
    ("2c1.post1.dev1", "==2.*"),
    ("2c1.post1.dev1", "==2.0.*"),
    ("2rc1", "==2.*"),
    ("2rc1", "==2.0.*"),
    ("2", "==2.*"),
    ("2", "==2.0.*"),
    ("2", "==2.0.0.*"),
    ("2", "==0!2.*"),
    ("0!2", "==2.*"),
    ("2.0", "==2.*"),
    ("2.0.0", "==2.*"),
    ("2.0.0.0", "==2.0.*"),
    ("2.1+local.version", "==2.1.*"),
    # Test the in-equality operation
    ("2.1", "!=2"),
    ("2.1", "!=2.0"),
    ("2.0.1", "!=2"),
    ("2.0.1", "!=2.0"),
    ("2.0.1", "!=2.0.0"),
    ("2.0", "!=2.0+deadbeef"),
    # Test the in-equality operation with a prefix
    ("2.0", "!=3.*"),
    ("2.1", "!=2.0.*"),
    ("3", "!=2.0.0.*"),
    ("2.1.0.0", "!=2.0.*"),
    # Test the greater than equal operation
    ("2.0", ">=2"),
    ("2.0", ">=2.0"),
    ("2.0", ">=2.0.0"),
    ("2.0.post1", ">=2"),
    ("2.0.post1.dev1", ">=2"),
    ("3", ">=2"),
    ("3.0.0a8", ">=3.0.0a7"),
    # Test the less than equal operation
    ("2.0", "<=2"),
    ("2.0", "<=2.0"),
    ("2.0", "<=2.0.0"),
    ("2.0.dev1", "<=2"),
    ("2.0a1", "<=2"),
    ("2.0a1.dev1", "<=2"),
    ("2.0b1", "<=2"),
    ("2.0b1.post1", "<=2"),
    ("2.0c1", "<=2"),
    ("2.0c1.post1.dev1", "<=2"),
    ("2.0rc1", "<=2"),
    ("1", "<=2"),
    ("3.0.0a7", "<=3.0.0a8"),
    # Test the greater than operation
    ("3", ">2"),
    ("2.1", ">2.0"),
    ("2.0.1", ">2"),
    ("2.1.post1", ">2"),
    ("2.1+local.version", ">2"),
    ("3.0.0a8", ">3.0.0a7"),
    # Test the less than operation
    ("1", "<2"),
    ("2.0", "<2.1"),
    ("2.0.dev0", "<2.1"),
    ("3.0.0a7", "<3.0.0a8"),
    # Test the compatibility operation
    ("1", "~=1.0"),
    ("1.0.1", "~=1.0"),
    ("1.1", "~=1.0"),
    ("1.9999999", "~=1.0"),
    ("1.1", "~=1.0a1"),
    # Test that epochs are handled sanely
    ("2!1.0", "~=2!1.0"),
    ("2!1.0", "==2!1.*"),
    ("2!1.0", "==2!1.0"),
    ("2!1.0", "!=1.0"),
    ("2!1.0.0", "==2!1.0.0.0.*"),
    ("2!1.0.0", "==2!1.0.*"),
    ("2!1.0.0", "==2!1.*"),
    ("1.0", "!=2!1.0"),
    ("1.0", "<=2!0.1"),
    ("2!1.0", ">=2.0"),
    ("1.0", "<2!0.1"),
    ("2!1.0", ">2.0"),
    # Test some normalization rules
    ("2.0.5", ">2.0dev"),
    # Test local versions with pre/dev/post segments and >
    ("1.0+local", ">1.0.dev1"),
    ("4.1.0a2.dev1235+local", ">4.1.0a2.dev1234"),
    ("1.0a2+local", ">1.0a1"),
    ("1.0b2+local", ">1.0b1"),
    ("1.0rc2+local", ">1.0rc1"),
    ("1.0.post2+local", ">1.0.post1"),
    ("1.0.dev2+local", ">1.0.dev1"),
    ("1.0a1.dev2+local", ">1.0a1.dev1"),
    ("1.0.post1.dev2+local", ">1.0.post1.dev1"),
]

_UPSTREAM_SPECIFIERS_FAIL = [
    # Test the equality operation
    ("2.1", "==2"),
    ("2.1", "==2.0"),
    ("2.1", "==2.0.0"),
    ("2.0", "==2.0+deadbeef"),
    # Test the equality operation with a prefix
    ("2.0", "==3.*"),
    ("2.1", "==2.0.*"),
    ("3", "==2.0.0.*"),
    ("2.1.0.0", "==2.0.*"),
    # Test the in-equality operation
    ("2.0", "!=2"),
    ("2.0", "!=2.0"),
    ("2.0", "!=2.0.0"),
    ("2.0+deadbeef", "!=2"),
    ("2.0+deadbeef", "!=2.0"),
    ("2.0+deadbeef", "!=2.0.0"),
    ("2.0+deadbeef", "!=2+deadbeef"),
    ("2.0+deadbeef", "!=2.0+deadbeef"),
    ("2.0+deadbeef", "!=2.0.0+deadbeef"),
    ("2.0+deadbeef.0", "!=2.0.0+deadbeef.00"),
    # Test the in-equality operation with a prefix
    ("2.dev1", "!=2.*"),
    ("2a1", "!=2.*"),
    ("2a1.post1", "!=2.*"),
    ("2b1", "!=2.*"),
    ("2b1.dev1", "!=2.*"),
    ("2c1", "!=2.*"),
    ("2c1.post1.dev1", "!=2.*"),
    ("2c1.post1.dev1", "!=2.0.*"),
    ("2rc1", "!=2.*"),
    ("2rc1", "!=2.0.*"),
    ("2", "!=2.*"),
    ("2", "!=2.0.*"),
    ("2", "!=2.0.0.*"),
    ("2.0", "!=2.*"),
    ("2.0.0", "!=2.*"),
    ("2.0.0.0", "!=2.0.*"),
    # Test the greater than equal operation
    ("2.0.dev1", ">=2"),
    ("2.0a1", ">=2"),
    ("2.0a1.dev1", ">=2"),
    ("2.0b1", ">=2"),
    ("2.0b1.post1", ">=2"),
    ("2.0c1", ">=2"),
    ("2.0c1.post1.dev1", ">=2"),
    ("2.0rc1", ">=2"),
    ("1", ">=2"),
    # Test the less than equal operation
    ("2.0.post1", "<=2"),
    ("2.0.post1.dev1", "<=2"),
    ("3", "<=2"),
    # Test the greater than operation
    ("1", ">2"),
    ("2.0.dev1", ">2"),
    ("2.0a1", ">2"),
    ("2.0a1.post1", ">2"),
    ("2.0b1", ">2"),
    ("2.0b1.dev1", ">2"),
    ("2.0c1", ">2"),
    ("2.0c1.post1.dev1", ">2"),
    ("2.0rc1", ">2"),
    ("2.0", ">2"),
    ("2.0.post1", ">2"),
    ("2.0.post1.dev1", ">2"),
    ("2.0+local.version", ">2"),
    ("4.1.0a2.dev1234+local", ">4.1.0a2.dev1234"),
    # Test local versions with pre/dev/post segments and >
    # (local variant of the exact spec version must not match)
    ("1.0a1+local", ">1.0a1"),
    ("1.0b1+local", ">1.0b1"),
    ("1.0rc1+local", ">1.0rc1"),
    ("1.0.post1+local", ">1.0.post1"),
    ("1.0.dev1+local", ">1.0.dev1"),
    ("1.0a1.dev1+local", ">1.0a1.dev1"),
    ("1.0.post1.dev1+local", ">1.0.post1.dev1"),
    # Test the less than operation
    ("2.0.dev1", "<2"),
    ("2.0a1", "<2"),
    ("2.0a1.post1", "<2"),
    ("2.0b1", "<2"),
    ("2.0b2.dev1", "<2"),
    ("2.0c1", "<2"),
    ("2.0c1.post1.dev1", "<2"),
    ("2.0rc1", "<2"),
    ("2.0", "<2"),
    ("2.post1", "<2"),
    ("2.post1.dev1", "<2"),
    ("3", "<2"),
    # Test the compatibility operation
    ("2.0", "~=1.0"),
    ("1.1.0", "~=1.0.0"),
    ("1.1.post1", "~=1.0.0"),
    # Test that epochs are handled sanely
    ("1.0", "~=2!1.0"),
    ("2!1.0", "~=1.0"),
    ("2!1.0", "==1.0"),
    ("1.0", "==2!1.0"),
    ("2!1.0", "==1.0.0.*"),
    ("1.0", "==2!1.0.0.*"),
    ("2!1.0", "==1.*"),
    ("1.0", "==2!1.*"),
    ("2!1.0", "!=2!1.0"),
]

def _test_specifier_contains_upstream_impl(env, _target):
    for version, spec_str in _UPSTREAM_SPECIFIERS_PASS:
        spec = specifiers.parse(spec_str)
        env.expect.that_bool(specifiers.contains(spec, version)).equals(True)

    for version, spec_str in _UPSTREAM_SPECIFIERS_FAIL:
        spec = specifiers.parse(spec_str)
        env.expect.that_bool(specifiers.contains(spec, version)).equals(False)

def _test_specifier_contains_upstream(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_specifier_contains_upstream_impl)

def _test_specifier_contains(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_specifier_contains_impl)

def _test_specifier_set_contains_impl(env, _target):
    spec_set = specifiers.parse_set(">=1.0, <2.0")
    env.expect.that_bool(specifiers.set_contains(spec_set, "1.5")).equals(True)
    env.expect.that_bool(specifiers.set_contains(spec_set, "0.9")).equals(False)
    env.expect.that_bool(specifiers.set_contains(spec_set, "2.0")).equals(False)

def _test_specifier_set_contains(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_specifier_set_contains_impl)

def specifiers_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_specifier_basic,
            _test_specifier_contains,
            _test_specifier_set_contains,
            _test_specifier_contains_upstream,
        ],
    )
