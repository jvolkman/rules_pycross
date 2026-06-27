"""Tests for version.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private/packaging/version:version.bzl", "version")

def _test_parse_version_basic_impl(env, _target):
    v = version.parse("1.2.3")
    env.expect.that_str(v.version_str).equals("1.2.3")
    env.expect.that_int(v.epoch).equals(0)
    env.expect.that_collection(v.release).contains_exactly([1, 2, 3])

def _test_parse_version_basic(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_version_basic_impl)

def _test_parse_version_parts_impl(env, _target):
    v = version.parse("1.2.3a1.post2.dev3+local")
    env.expect.that_str(v.version_str).equals("1.2.3a1.post2.dev3+local")
    env.expect.that_int(v.epoch).equals(0)
    env.expect.that_collection(v.release).contains_exactly([1, 2, 3])
    env.expect.that_collection(v.pre).contains_exactly(["a", 1])
    env.expect.that_collection(v.post).contains_exactly(["post", 2])
    env.expect.that_collection(v.dev).contains_exactly(["dev", 3])
    env.expect.that_collection(v.local).contains_exactly(["local"])

def _test_parse_version_parts(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_version_parts_impl)

def _test_version_cmp_impl(env, _target):
    v1 = version.parse("1.0")
    v2 = version.parse("1.1")
    v1_post = version.parse("1.0.post1")
    v1_dev = version.parse("1.0.dev1")
    v1_local = version.parse("1.0+local")
    v1_alpha = version.parse("1.0a1")

    # 1.0 < 1.1
    env.expect.that_bool(v1.key < v2.key).equals(True)

    # 1.0.dev1 < 1.0a1
    env.expect.that_bool(v1_dev.key < v1_alpha.key).equals(True)

    # 1.0a1 < 1.0
    env.expect.that_bool(v1_alpha.key < v1.key).equals(True)

    # 1.0 < 1.0.post1
    env.expect.that_bool(v1.key < v1_post.key).equals(True)

    # 1.0 < 1.0+local
    env.expect.that_bool(v1.key < v1_local.key).equals(True)

    # 1.0+local < 1.0.post1
    env.expect.that_bool(v1_local.key < v1_post.key).equals(True)

_UPSTREAM_VERSIONS = [
    # Implicit epoch of 0
    "1.0.dev0",
    "1.0.dev456",
    "1.0.dev456+local",
    "1.0a0",
    "1.0a0.post0.dev0",
    "1.0a0.post0",
    "1.0a1.dev1",
    "1.0a1.dev1+local",
    "1.0a1",
    "1.0a1+local",
    "1.0b0",
    "1.0b1.dev456",
    "1.0b2",
    "1.0b2.post345.dev456",
    "1.0b2.post345",
    "1.0b2-346",
    "1.0rc0",
    "1.0rc1.dev1",
    "1.0c1",
    "1.0rc2",
    "1.0",
    "1.0.post0.dev0",
    "1.0.post0",
    "1.0.post456.dev34",
    "1.0.post456",
    "1.0.post456+local",
    "1.0.1.dev1",
    "1.0.1a1",
    "1.0.1",
    "1.0.1+local",
    "1.0.1.post1",
    "1.1.dev1",
    "1.2+a",
    "1.2+abc",
    "1.2+abcdef",
    "1.2+def",
    "1.2+0",
    "1.2+1",
    "1.2+1.abc",
    "1.2+1.1",
    "1.2+1.1.0",
    "1.2+2",
    "1.2+123",
    "1.2+123456",
    "1.2.r32+123456",
    "1.2.rev33+123456",
    # Explicit epoch of 1
    "1!1.0.dev0",
    "1!1.0.dev456",
    "1!1.0.dev456+local",
    "1!1.0a0",
    "1!1.0a0.post0.dev0",
    "1!1.0a0.post0",
    "1!1.0a1.dev1",
    "1!1.0a1.dev1+local",
    "1!1.0a1",
    "1!1.0a1+local",
    "1!1.0b0",
    "1!1.0b1.dev456",
    "1!1.0b2",
    "1!1.0b2.post345.dev456",
    "1!1.0b2.post345",
    "1!1.0b2-346",
    "1!1.0rc0",
    "1!1.0rc1.dev1",
    "1!1.0c1",
    "1!1.0rc2",
    "1!1.0",
    "1!1.0.post0.dev0",
    "1!1.0.post0",
    "1!1.0.post456.dev34",
    "1!1.0.post456",
    "1!1.0.post456+local",
    "1!1.0.1.dev1",
    "1!1.0.1a1",
    "1!1.0.1",
    "1!1.0.1+local",
    "1!1.0.1.post1",
    "1!1.1.dev1",
    "1!1.2+a",
    "1!1.2+abc",
    "1!1.2+abcdef",
    "1!1.2+def",
    "1!1.2+0",
    "1!1.2+1",
    "1!1.2+1.abc",
    "1!1.2+1.1",
    "1!1.2+1.1.0",
    "1!1.2+2",
    "1!1.2+123",
    "1!1.2+123456",
    "1!1.2.r32+123456",
    "1!1.2.rev33+123456",
]

def _test_version_cmp_upstream_impl(env, _target):
    for i in range(len(_UPSTREAM_VERSIONS) - 1):
        v1_str = _UPSTREAM_VERSIONS[i]
        v2_str = _UPSTREAM_VERSIONS[i + 1]
        v1 = version.parse(v1_str)
        v2 = version.parse(v2_str)

        # v1 < v2
        env.expect.that_bool(v1.key < v2.key).equals(True)

        # v2 > v1
        env.expect.that_bool(v2.key > v1.key).equals(True)

        # v1 <= v2
        env.expect.that_bool(v1.key <= v2.key).equals(True)

        # v2 >= v1
        env.expect.that_bool(v2.key >= v1.key).equals(True)

        # v1 != v2
        env.expect.that_bool(v1.key != v2.key).equals(True)

        # v1 == v1
        env.expect.that_bool(v1.key == v1.key).equals(True)

def _test_version_cmp_upstream(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_version_cmp_upstream_impl)

def _test_version_cmp(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_version_cmp_impl)

def version_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_parse_version_basic,
            _test_parse_version_parts,
            _test_version_cmp,
            _test_version_cmp_upstream,
        ],
    )
