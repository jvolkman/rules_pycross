"""Tests for platform_tags.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private/pypackaging/tags:tags.bzl", "get_supported")

def _test_get_supported_basic_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["any"], impl = "cp", abis = ["none"])

    # Let's check some specific ones are present.
    env.expect.that_collection(tags).contains("cp311-none-any")
    env.expect.that_collection(tags).contains("cp311-abi3-any")
    env.expect.that_collection(tags).contains("cp32-abi3-any")
    env.expect.that_collection(tags).contains("py311-none-any")
    env.expect.that_collection(tags).contains("py3-none-any")

def _test_get_supported_basic(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_get_supported_basic_impl,
    )

def _test_get_supported_pypy_impl(env, _target):
    tags = get_supported(version = "39", platforms = ["any"], impl = "pp", abis = ["none"])
    env.expect.that_collection(tags).contains("pp39-none-any")
    env.expect.that_collection(tags).contains("py39-none-any")
    env.expect.that_collection(tags).contains("py3-none-any")
    env.expect.that_collection(tags).not_contains("cp39-abi3-any")

def _test_get_supported_pypy(name):
    util.helper_target(
        native.filegroup,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_get_supported_pypy_impl,
    )

def _test_expand_macosx_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["macosx_11_0_arm64"], impl = "cp", abis = ["none"])

    # Should contain the exact one
    env.expect.that_collection(tags).contains("cp311-none-macosx_11_0_arm64")

    # Should contain universal2 fallback
    env.expect.that_collection(tags).contains("cp311-none-macosx_11_0_universal2")

    # Should contain 10.16 fallback
    env.expect.that_collection(tags).contains("cp311-none-macosx_10_16_universal2")

    # Should contain older compatible versions (e.g. 10.15 universal2)
    env.expect.that_collection(tags).contains("cp311-none-macosx_10_15_universal2")

def _test_expand_macosx(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_macosx_impl)

def _test_expand_manylinux_pep600_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["manylinux_2_17_x86_64"], impl = "cp", abis = ["none"])
    env.expect.that_collection(tags).contains("cp311-none-manylinux_2_17_x86_64")

    # Should contain legacy alias
    env.expect.that_collection(tags).contains("cp311-none-manylinux2014_x86_64")

    # Should contain older compatible versions
    env.expect.that_collection(tags).contains("cp311-none-manylinux_2_5_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-manylinux1_x86_64")

def _test_expand_manylinux_pep600(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_manylinux_pep600_impl)

def _test_expand_manylinux_legacy_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["manylinux2014_x86_64"], impl = "cp", abis = ["none"])
    env.expect.that_collection(tags).contains("cp311-none-manylinux_2_17_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-manylinux2014_x86_64")

def _test_expand_manylinux_legacy(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_manylinux_legacy_impl)

def _test_expand_musllinux_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["musllinux_1_2_x86_64"], impl = "cp", abis = ["none"])
    env.expect.that_collection(tags).contains("cp311-none-musllinux_1_2_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-musllinux_1_1_x86_64")
    env.expect.that_collection(tags).contains("cp311-none-musllinux_1_0_x86_64")

def _test_expand_musllinux(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_musllinux_impl)

def _test_expand_android_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["android_30_arm64_v8a"], impl = "cp", abis = ["none"])
    env.expect.that_collection(tags).contains("cp311-none-android_30_arm64_v8a")
    env.expect.that_collection(tags).contains("cp311-none-android_29_arm64_v8a")

    # Should stop at 16
    env.expect.that_collection(tags).contains("cp311-none-android_16_arm64_v8a")
    env.expect.that_collection(tags).not_contains("cp311-none-android_15_arm64_v8a")

def _test_expand_android(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_android_impl)

def _test_expand_ios_impl(env, _target):
    tags = get_supported(version = "311", platforms = ["ios_14_0_arm64"], impl = "cp", abis = ["none"])
    env.expect.that_collection(tags).contains("cp311-none-ios_14_0_arm64")
    env.expect.that_collection(tags).contains("cp311-none-ios_13_0_arm64")
    env.expect.that_collection(tags).contains("cp311-none-ios_12_0_arm64")

    # Should not contain < 12
    env.expect.that_collection(tags).not_contains("cp311-none-ios_11_0_arm64")

def _test_expand_ios(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_ios_impl)

def _test_freethreaded_impl(env, _target):
    tags = get_supported(version = "313", platforms = ["any"], impl = "cp", abis = ["cp313t"])
    env.expect.that_collection(tags).contains("cp313-cp313t-any")

    # Should use abi3t, not abi3
    env.expect.that_collection(tags).contains("cp313-abi3t-any")
    env.expect.that_collection(tags).not_contains("cp313-abi3-any")

    # Older versions should also have abi3t
    env.expect.that_collection(tags).contains("cp312-abi3t-any")
    env.expect.that_collection(tags).not_contains("cp312-abi3-any")

def _test_freethreaded(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_freethreaded_impl)

def tags_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_get_supported_basic,
            _test_get_supported_pypy,
            _test_expand_macosx,
            _test_expand_manylinux_pep600,
            _test_expand_manylinux_legacy,
            _test_expand_musllinux,
            _test_expand_android,
            _test_expand_ios,
            _test_freethreaded,
        ],
    )
