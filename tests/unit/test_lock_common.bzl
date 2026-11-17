"""Tests for lock_common.bzl helpers."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_common.bzl", "resolve_member_project_file", "sibling_project_file")

# buildifier: disable=unused-variable
def _test_member_project_files_impl(env, target):
    cases = [
        # Lock at a package root: members resolve within the same package, so member
        # directories don't need BUILD files.
        ("//:uv.lock", "apps/app-a", "//:apps/app-a/pyproject.toml"),
        ("//:uv.lock", "./apps/app-a", "//:apps/app-a/pyproject.toml"),
        ("//:uv.lock", ".", "//:pyproject.toml"),
        ("//:uv.lock", "", "//:pyproject.toml"),
        ("//py:uv.lock", "libs/common", "//py:libs/common/pyproject.toml"),
        # Lock in a subdirectory of its package: paths are relative to the lock's directory.
        ("//:project/uv.lock", "apps/app-a", "//:project/apps/app-a/pyproject.toml"),
        ("//:project/uv.lock", "", "//:project/pyproject.toml"),
        ("//:project/uv.lock", "apps/../libs/common", "//:project/libs/common/pyproject.toml"),
        # Members outside the lock's package resolve from the repository root.
        ("//py:uv.lock", "../other", "//:other/pyproject.toml"),
    ]
    for lock, member, expected in cases:
        actual = resolve_member_project_file(Label(lock), member)
        env.expect.where(lock = lock, member = member).that_str(str(actual)).equals(str(Label(expected)))

    env.expect.that_str(str(sibling_project_file(Label("//:project/uv.lock")))).equals(str(Label("//:project/pyproject.toml")))
    env.expect.that_str(str(sibling_project_file(Label("//py:uv.lock")))).equals(str(Label("//py:pyproject.toml")))

def _test_member_project_files(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_member_project_files_impl)

def lock_common_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_member_project_files,
        ],
    )
