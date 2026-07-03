"""Tests for expand_pins_for_build_repo."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "expand_pins_for_build_repo")

# --------------------------------------------------------------------------- #
# Test: single member, all single-version -> all get pinned
# --------------------------------------------------------------------------- #

# buildifier: disable=unused-variable
def _test_expand_pins_all_single_version_impl(env, target):
    resolved_locks = {
        "my_app": {
            "packages": {
                "foo@1.0": {"name": "foo", "version": "1.0"},
                "bar@2.0": {"name": "bar", "version": "2.0"},
            },
            "pins": {
                "foo": {"": "foo@1.0"},
            },
        },
    }

    pins = expand_pins_for_build_repo(resolved_locks)

    # foo was already pinned, bar should be added.
    env.expect.that_collection(sorted(pins.keys())).contains_exactly(["bar", "foo"])
    env.expect.that_dict(pins["foo"]).contains_exactly({"": "foo@1.0"})
    env.expect.that_dict(pins["bar"]).contains_exactly({"": "bar@2.0"})

def _test_expand_pins_all_single_version(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_pins_all_single_version_impl)

# --------------------------------------------------------------------------- #
# Test: multi-version packages are NOT auto-pinned
# --------------------------------------------------------------------------- #

# buildifier: disable=unused-variable
def _test_expand_pins_multi_version_excluded_impl(env, target):
    resolved_locks = {
        "my_app": {
            "packages": {
                "foo@1.0": {"name": "foo", "version": "1.0"},
                "foo@2.0": {"name": "foo", "version": "2.0"},
                "bar@1.0": {"name": "bar", "version": "1.0"},
            },
            "pins": {},
        },
    }

    pins = expand_pins_for_build_repo(resolved_locks)

    # foo has two versions -> not pinned. bar has one -> pinned.
    env.expect.that_collection(pins.keys()).contains_exactly(["bar"])
    env.expect.that_dict(pins["bar"]).contains_exactly({"": "bar@1.0"})

def _test_expand_pins_multi_version_excluded(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_pins_multi_version_excluded_impl)

# --------------------------------------------------------------------------- #
# Test: existing pins are preserved (not overwritten)
# --------------------------------------------------------------------------- #

# buildifier: disable=unused-variable
def _test_expand_pins_preserves_existing_impl(env, target):
    resolved_locks = {
        "my_app": {
            "packages": {
                "foo@1.0": {"name": "foo", "version": "1.0"},
            },
            "pins": {
                # Existing pin with variant dict.
                "foo": {"linux": "foo@1.0", "macos": "foo@1.0"},
            },
        },
    }

    pins = expand_pins_for_build_repo(resolved_locks)

    # foo's existing pin should not be clobbered.
    env.expect.that_dict(pins["foo"]).contains_exactly({"linux": "foo@1.0", "macos": "foo@1.0"})

def _test_expand_pins_preserves_existing(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_pins_preserves_existing_impl)

# --------------------------------------------------------------------------- #
# Test: extras are ignored for version counting
# --------------------------------------------------------------------------- #

# buildifier: disable=unused-variable
def _test_expand_pins_extras_ignored_impl(env, target):
    resolved_locks = {
        "my_app": {
            "packages": {
                "foo@1.0": {"name": "foo", "version": "1.0"},
                "foo[bar]@1.0": {"name": "foo", "version": "1.0"},
                "foo[baz]@1.0": {"name": "foo", "version": "1.0"},
            },
            "pins": {},
        },
    }

    pins = expand_pins_for_build_repo(resolved_locks)

    # foo@1.0 is the only base version; extras don't count as separate versions.
    env.expect.that_collection(pins.keys()).contains_exactly(["foo"])
    env.expect.that_dict(pins["foo"]).contains_exactly({"": "foo@1.0"})

def _test_expand_pins_extras_ignored(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_pins_extras_ignored_impl)

# --------------------------------------------------------------------------- #
# Test: multiple members' locks are merged
# --------------------------------------------------------------------------- #

# buildifier: disable=unused-variable
def _test_expand_pins_multi_member_merge_impl(env, target):
    resolved_locks = {
        "app_a": {
            "packages": {
                "foo@1.0": {"name": "foo", "version": "1.0"},
                "bar@2.0": {"name": "bar", "version": "2.0"},
            },
            "pins": {
                "foo": {"": "foo@1.0"},
            },
        },
        "app_b": {
            "packages": {
                "foo@1.0": {"name": "foo", "version": "1.0"},
                "baz@3.0": {"name": "baz", "version": "3.0"},
            },
            "pins": {
                "foo": {"": "foo@1.0"},
            },
        },
    }

    pins = expand_pins_for_build_repo(resolved_locks)

    # foo is already pinned. bar and baz are single-version and should be added.
    env.expect.that_collection(sorted(pins.keys())).contains_exactly(["bar", "baz", "foo"])

def _test_expand_pins_multi_member_merge(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_pins_multi_member_merge_impl)

# --------------------------------------------------------------------------- #
# Test: multi-version across members prevents pinning
# --------------------------------------------------------------------------- #

# buildifier: disable=unused-variable
def _test_expand_pins_cross_member_conflict_impl(env, target):
    resolved_locks = {
        "app_a": {
            "packages": {
                "foo@1.0": {"name": "foo", "version": "1.0"},
            },
            "pins": {},
        },
        "app_b": {
            "packages": {
                "foo@2.0": {"name": "foo", "version": "2.0"},
            },
            "pins": {},
        },
    }

    pins = expand_pins_for_build_repo(resolved_locks)

    # foo has versions 1.0 and 2.0 across members -> not auto-pinned.
    env.expect.that_collection(pins.keys()).contains_exactly([])

def _test_expand_pins_cross_member_conflict(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_pins_cross_member_conflict_impl)

# --------------------------------------------------------------------------- #
# Test: empty lock -> empty pins
# --------------------------------------------------------------------------- #

# buildifier: disable=unused-variable
def _test_expand_pins_empty_lock_impl(env, target):
    resolved_locks = {
        "my_app": {
            "packages": {},
            "pins": {},
        },
    }

    pins = expand_pins_for_build_repo(resolved_locks)

    env.expect.that_collection(pins.keys()).contains_exactly([])

def _test_expand_pins_empty_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_pins_empty_lock_impl)

# --------------------------------------------------------------------------- #
# Test: pins from different members are merged
# --------------------------------------------------------------------------- #

# buildifier: disable=unused-variable
def _test_expand_pins_member_pins_merged_impl(env, target):
    resolved_locks = {
        "app_a": {
            "packages": {
                "foo@1.0": {"name": "foo", "version": "1.0"},
            },
            "pins": {
                "foo": {"": "foo@1.0"},
            },
        },
        "app_b": {
            "packages": {
                "bar@2.0": {"name": "bar", "version": "2.0"},
            },
            "pins": {
                "bar": {"": "bar@2.0"},
            },
        },
    }

    pins = expand_pins_for_build_repo(resolved_locks)

    # Both member pins should be present in the merged result.
    env.expect.that_collection(sorted(pins.keys())).contains_exactly(["bar", "foo"])

def _test_expand_pins_member_pins_merged(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_expand_pins_member_pins_merged_impl)

# --------------------------------------------------------------------------- #
# Suite
# --------------------------------------------------------------------------- #

def expand_pins_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_expand_pins_all_single_version,
            _test_expand_pins_multi_version_excluded,
            _test_expand_pins_preserves_existing,
            _test_expand_pins_extras_ignored,
            _test_expand_pins_multi_member_merge,
            _test_expand_pins_cross_member_conflict,
            _test_expand_pins_empty_lock,
            _test_expand_pins_member_pins_merged,
        ],
    )
