"""Tests for the Starlark PDM translator."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:pdm_lock_model.bzl", "translate_pdm")

def _lock_model(
        projects = ["*"],
        dependency_groups = ["default"]):
    return struct(
        projects = projects,
        dependency_groups = dependency_groups,
    )

def _minimal_project(deps = None):
    return {
        "project": {
            "name": "my-app",
            "version": "0.1.0",
            "dependencies": deps or ["requests==2.31.0"],
        },
    }

def _minimal_lock(packages):
    return {
        "metadata": {"lock_version": "4.3"},
        "package": packages,
    }

def _whl(name, sha256 = "1234"):
    return {"file": name, "hash": "sha256:" + sha256}

# --- test_minimal_lock ---

# buildifier: disable=unused-variable
def _test_pdm_minimal_lock_impl(env, target):
    project = _minimal_project()
    lock = _minimal_lock([{
        "name": "requests",
        "version": "2.31.0",
        "files": [_whl("requests-2.31.0-py3-none-any.whl", "12345")],
    }])
    result = translate_pdm(project, lock, _lock_model())

    env.expect.that_collection(result["packages"].keys()).contains_exactly(["requests@2.31.0"])
    pkg = result["packages"]["requests@2.31.0"]
    env.expect.that_str(pkg["name"]).equals("requests")
    env.expect.that_str(pkg["version"]).equals("2.31.0")

    files = pkg["files"]
    env.expect.that_collection(files).has_size(1)
    env.expect.that_str(files[0]["package_name"]).equals("requests")
    env.expect.that_str(files[0]["package_version"]).equals("2.31.0")

def _test_pdm_minimal_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_minimal_lock_impl)

# --- test_package_with_groups ---

# buildifier: disable=unused-variable
def _test_pdm_package_with_groups_default_only_impl(env, target):
    project = {
        "project": {
            "name": "my-app",
            "version": "0.1.0",
            "dependencies": ["requests==2.31.0"],
        },
        "dependency-groups": {
            "dev": ["pytest==7.0.0"],
        },
    }
    lock = _minimal_lock([
        {
            "name": "requests",
            "version": "2.31.0",
            "files": [_whl("requests-2.31.0-py3-none-any.whl", "123")],
        },
        {
            "name": "pytest",
            "version": "7.0.0",
            "files": [_whl("pytest-7.0.0-py3-none-any.whl", "abc")],
        },
    ])

    # Default group only: pytest should not be pinned
    result = translate_pdm(project, lock, _lock_model())
    env.expect.that_collection(result["pins"].keys()).contains_exactly(["requests"])

def _test_pdm_package_with_groups_default_only(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_package_with_groups_default_only_impl)

# buildifier: disable=unused-variable
def _test_pdm_package_with_groups_dev_included_impl(env, target):
    project = {
        "project": {
            "name": "my-app",
            "version": "0.1.0",
            "dependencies": ["requests==2.31.0"],
        },
        "dependency-groups": {
            "dev": ["pytest==7.0.0"],
        },
    }
    lock = _minimal_lock([
        {
            "name": "requests",
            "version": "2.31.0",
            "files": [_whl("requests-2.31.0-py3-none-any.whl", "123")],
        },
        {
            "name": "pytest",
            "version": "7.0.0",
            "files": [_whl("pytest-7.0.0-py3-none-any.whl", "abc")],
        },
    ])

    # Dev group included: both should be pinned
    result = translate_pdm(project, lock, _lock_model(dependency_groups = ["default", "development:dev"]))
    env.expect.that_collection(result["pins"].keys()).contains_at_least(["requests", "pytest"])

def _test_pdm_package_with_groups_dev_included(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_package_with_groups_dev_included_impl)

# --- test_conditional_dependency ---

# buildifier: disable=unused-variable
def _test_pdm_conditional_dependency_impl(env, target):
    project = _minimal_project(deps = ["a==1.0"])
    lock = _minimal_lock([
        {
            "name": "a",
            "version": "1.0",
            "files": [_whl("a-1.0-py3-none-any.whl", "a")],
            "dependencies": ["b==2.0; python_version >= '3.10'"],
        },
        {
            "name": "b",
            "version": "2.0",
            "files": [_whl("b-2.0-py3-none-any.whl", "b")],
        },
    ])
    result = translate_pdm(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    dep_b = pkg_a["dependencies"][0]
    env.expect.that_str(dep_b["name"]).equals("b")
    env.expect.that_str(dep_b["marker"]).contains("python_version")

def _test_pdm_conditional_dependency(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_conditional_dependency_impl)

# --- test_cross_platform_files ---

# buildifier: disable=unused-variable
def _test_pdm_cross_platform_files_impl(env, target):
    project = _minimal_project(deps = ["a==1.0"])
    lock = _minimal_lock([{
        "name": "a",
        "version": "1.0",
        "files": [
            _whl("a-1.0-cp39-cp39-macosx_10_9_x86_64.whl", "mac"),
            _whl("a-1.0-cp39-cp39-manylinux1_x86_64.whl", "lin"),
        ],
    }])
    result = translate_pdm(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    env.expect.that_int(len(pkg_a["files"])).equals(2)
    file_names = [f["name"] for f in pkg_a["files"]]
    env.expect.that_collection(file_names).contains("a-1.0-cp39-cp39-macosx_10_9_x86_64.whl")

def _test_pdm_cross_platform_files(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_cross_platform_files_impl)

# --- test_local_editable_package ---

# buildifier: disable=unused-variable
def _test_pdm_local_editable_package_impl(env, target):
    project = _minimal_project(deps = ["localpkg"])
    lock = _minimal_lock([{
        "name": "localpkg",
        "version": "1.0",
        "path": ".",
    }])
    result = translate_pdm(project, lock, _lock_model())

    # Local/editable packages should be elided
    env.expect.that_collection(result["packages"].keys()).has_size(0)

def _test_pdm_local_editable_package(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_local_editable_package_impl)

# --- test_file_hashes ---

# buildifier: disable=unused-variable
def _test_pdm_file_hashes_impl(env, target):
    project = _minimal_project(deps = ["a==1.0"])
    lock = _minimal_lock([{
        "name": "a",
        "version": "1.0",
        "files": [_whl("a-1.0-py3-none-any.whl", "myhash123")],
    }])
    result = translate_pdm(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    env.expect.that_str(pkg_a["files"][0]["sha256"]).equals("myhash123")

def _test_pdm_file_hashes(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_file_hashes_impl)

# --- test_extras_in_markers ---

# buildifier: disable=unused-variable
def _test_pdm_extras_in_markers_impl(env, target):
    project = _minimal_project(deps = ["a==1.0"])
    lock = _minimal_lock([
        {
            "name": "a",
            "version": "1.0",
            "files": [_whl("a-1.0-py3-none-any.whl", "a")],
            "dependencies": ["b==2.0; extra == 'testing'"],
        },
        {
            "name": "b",
            "version": "2.0",
            "files": [_whl("b-2.0-py3-none-any.whl", "b")],
        },
    ])
    result = translate_pdm(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    dep_b = pkg_a["dependencies"][0]
    env.expect.that_str(dep_b["marker"]).contains("extra")

def _test_pdm_extras_in_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_extras_in_markers_impl)

# --- test_extra_dependency ---

# buildifier: disable=unused-variable
def _test_pdm_extra_dependency_impl(env, target):
    project = _minimal_project(deps = ["a==1.0"])
    lock = _minimal_lock([
        {
            "name": "a",
            "version": "1.0",
            "files": [_whl("a-1.0-py3-none-any.whl", "a")],
            "dependencies": ["b[test]==2.0"],
        },
        {
            "name": "b",
            "version": "2.0",
            "extras": ["test"],
            "files": [_whl("b-2.0-py3-none-any.whl", "b")],
        },
    ])
    result = translate_pdm(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    dep_b = pkg_a["dependencies"][0]
    env.expect.that_str(dep_b["name"]).equals("b[test]")

def _test_pdm_extra_dependency(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_extra_dependency_impl)

# --- Test suite ---

def pdm_translator_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pdm_minimal_lock,
            _test_pdm_package_with_groups_default_only,
            _test_pdm_package_with_groups_dev_included,
            _test_pdm_conditional_dependency,
            _test_pdm_cross_platform_files,
            _test_pdm_local_editable_package,
            _test_pdm_file_hashes,
            _test_pdm_extras_in_markers,
            _test_pdm_extra_dependency,
        ],
    )
