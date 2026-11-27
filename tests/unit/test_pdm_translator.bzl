"""Tests for the Starlark PDM translator."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_resolver.bzl", "resolve", "resolve_workspace")

# buildifier: disable=bzl-visibility
load("//pycross/private:pdm_lock_model.bzl", "discover_pdm_all_members", "translate_pdm")

# buildifier: disable=bzl-visibility
load("//pycross/private:translator_project.bzl", "read_project_dicts_for_testing")

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
    result = translate_pdm(project, lock, _lock_model(dependency_groups = ["default", "group:dev"]))
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

# --- test_pdm_resolution_forks ---

# buildifier: disable=unused-variable
def _test_pdm_resolution_forks_impl(env, target):
    """Test PDM multi-target lock files with different versions per environment."""
    project = {
        "project": {
            "name": "my-app",
            "version": "0.1.0",
            "requires-python": ">=3.9",
            "dependencies": [
                "greenlet>=2.0,<3.3; python_version < '3.10'",
                "greenlet>=3.5; python_version >= '3.10'",
            ],
        },
    }
    lock = {
        "metadata": {"lock_version": "4.5"},
        "package": [
            {
                "name": "greenlet",
                "version": "3.2.5",
                "requires_python": ">=3.9",
                "groups": ["default"],
                "marker": "python_version < \"3.10\" and python_version >= \"3.9\"",
                "files": [_whl("greenlet-3.2.5-cp39-cp39-manylinux2014_x86_64.whl", "aaaa")],
            },
            {
                "name": "greenlet",
                "version": "3.5.3",
                "requires_python": ">=3.10",
                "groups": ["default"],
                "marker": "python_version >= \"3.10\"",
                "files": [_whl("greenlet-3.5.3-cp310-cp310-manylinux_2_24_x86_64.whl", "bbbb")],
            },
        ],
    }
    result = translate_pdm(project, lock, _lock_model())

    # Both versions should be present as separate packages
    env.expect.that_collection(result["packages"].keys()).contains_exactly(["greenlet@3.2.5", "greenlet@3.5.3"])

    # Resolution marker expressions should be generated
    res_exprs = result.get("resolution_marker_exprs", {})
    env.expect.that_bool("res_greenlet_3_2_5" in res_exprs).equals(True)
    env.expect.that_bool("res_greenlet_3_5_3" in res_exprs).equals(True)

    env.expect.that_str(res_exprs["res_greenlet_3_2_5"]).equals('python_version < "3.10" and python_version >= "3.9"')
    env.expect.that_str(res_exprs["res_greenlet_3_5_3"]).equals('python_version >= "3.10"')

    # Pinned specs should be conditional
    pins = result["pins"]["greenlet"]
    env.expect.that_str(pins["res_greenlet_3_2_5"]).equals("greenlet@3.2.5")
    env.expect.that_str(pins["res_greenlet_3_5_3"]).equals("greenlet@3.5.3")

def _test_pdm_resolution_forks(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_resolution_forks_impl)

# --- test_pdm_root_dependency_markers ---

# buildifier: disable=unused-variable
def _test_pdm_root_dependency_markers_impl(env, target):
    project = _minimal_project(deps = [
        "foo==1.0 ; sys_platform == \"linux\"",
        "bar==2.0",
    ])
    lock = _minimal_lock([
        {
            "name": "foo",
            "version": "1.0",
            "files": [_whl("foo-1.0-py3-none-any.whl")],
        },
        {
            "name": "bar",
            "version": "2.0",
            "files": [_whl("bar-2.0-py3-none-any.whl")],
        },
    ])
    result = translate_pdm(project, lock, _lock_model())

    markers = result["root_dependency_markers"]
    env.expect.that_collection(markers.keys()).contains("foo")
    env.expect.that_collection(markers.keys()).contains_none_of(["bar"])
    env.expect.that_str(markers["foo"][0]).equals("sys_platform == \"linux\"")

def _test_pdm_root_dependency_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_root_dependency_markers_impl)

# --- test_pdm_git_dependency ---

# buildifier: disable=unused-variable
def _test_pdm_git_dependency_impl(env, target):
    project = _minimal_project(deps = ["sampleproject @ git+https://github.com/pypa/sampleproject.git@main"])
    lock = _minimal_lock([{
        "name": "sampleproject",
        "version": "4.0.0",
        "git": "https://github.com/pypa/sampleproject.git",
        "ref": "main",
        "revision": "621e4974ca25ce531773def586ba3ed8e736b3fc",
        "subdirectory": "src/pkg",
    }])
    result = translate_pdm(project, lock, _lock_model())
    pkg = result["packages"]["sampleproject@4.0.0"]
    env.expect.that_str(pkg["source_dir"]).equals("src/pkg")
    env.expect.that_str(pkg["files"][0]["name"]).equals("sampleproject-4.0.0.tar.gz")
    env.expect.that_collection(pkg["files"][0]["urls"]).contains_exactly([
        "git+https://github.com/pypa/sampleproject.git#621e4974ca25ce531773def586ba3ed8e736b3fc",
    ])

def _test_pdm_git_dependency(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_git_dependency_impl)

# --- test_pdm_transitive_include_group_and_root_extra_pin ---

# buildifier: disable=unused-variable
def _test_pdm_transitive_include_group_and_root_extra_pin_impl(env, target):
    project = {
        "project": {
            "name": "my-app",
            "dependencies": [
                "requests[socks]==2.32.3",
                "flex",
                'flex>=2.0 ; python_version >= "3.10"',
            ],
        },
        # Diamond include-group DAG: all -> [dev, extra-g, tail], dev -> [extra-g, leaf], extra-g -> [leaf].
        "dependency-groups": {
            "leaf": [],
            "extra-g": [{"include-group": "leaf"}],
            "dev": [{"include-group": "extra-g"}, {"include-group": "leaf"}],
            "tail": ["ruff==0.5.0"],
            "all": [{"include-group": "dev"}, {"include-group": "extra-g"}, {"include-group": "tail"}],
        },
    }
    lock = _minimal_lock([
        {
            "name": "requests",
            "version": "2.32.3",
            "extras": ["socks"],
            "dependencies": ['pysocks==1.7.1 ; extra == "socks"'],
            "files": [_whl("requests-2.32.3-py3-none-any.whl", "r")],
        },
        {
            "name": "pysocks",
            "version": "1.7.1",
            "files": [_whl("PySocks-1.7.1-py3-none-any.whl", "p")],
        },
        {
            "name": "flex",
            "version": "1.5.0",
            "files": [_whl("flex-1.5.0-py3-none-any.whl", "f")],
        },
        {
            "name": "ruff",
            "version": "0.5.0",
            "files": [_whl("ruff-0.5.0-py3-none-any.whl", "u")],
        },
    ])
    model = struct(
        projects = ["*"],
        dependency_groups = ["default", "group:all"],
        testonly_groups = ["group:all"],
        non_testonly_groups = [],
        wildcard_testonly = False,
    )
    result = translate_pdm(project, lock, model)
    env.expect.that_collection(result["pins"].keys()).contains_exactly(["flex", "requests", "requests[socks]", "ruff"])
    env.expect.that_str(result["pins"]["flex"]).equals("flex@1.5.0")
    env.expect.that_str(result["pins"]["requests[socks]"]).equals("requests[socks]@2.32.3")
    env.expect.that_collection(result["testonly_pins"]).contains_exactly(["ruff"])

def _test_pdm_transitive_include_group_and_root_extra_pin(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_transitive_include_group_and_root_extra_pin_impl)

# --- test_pdm_multi_project_workspace ---

# buildifier: disable=unused-variable
def _test_pdm_multi_project_workspace_impl(env, target):
    root_label = Label("//:pyproject.toml")
    proj_a_label = Label("//:project_a/pyproject.toml")
    proj_b_label = Label("//:project_b/pyproject.toml")
    files = {
        str(root_label): '[project]\nname = "workspace-root"\nrequires-python = ">=3.10"\n',
        str(proj_a_label): '[project]\nname = "project-a"\ndependencies = ["six>=1.17.0", "regex>=2024.11.6"]\n',
        str(proj_b_label): '[project]\nname = "project-b"\ndependencies = ["attrs>=24.2.0", "regex>=2024.10.0"]\n',
    }
    rctx = struct(
        path = lambda label: struct(exists = str(label) in files, label = str(label)),
        read = lambda path: files[path.label],
    )
    all_dicts = read_project_dicts_for_testing(
        rctx,
        [proj_a_label, root_label, proj_b_label],
        Label("//:pdm.lock"),
        _lock_model(projects = ["*"]),
    )
    env.expect.that_collection([d["project"]["name"] for d in all_dicts]).contains_exactly([
        "workspace-root",
        "project-a",
        "project-b",
    ]).in_order()

    subset_dicts = read_project_dicts_for_testing(
        rctx,
        [root_label, proj_a_label, proj_b_label],
        Label("//:pdm.lock"),
        _lock_model(projects = ["project-a", "project-b"]),
    )
    env.expect.that_collection([d["project"]["name"] for d in subset_dicts]).contains_exactly([
        "project-a",
        "project-b",
    ]).in_order()

    lock = _minimal_lock([
        {"name": "six", "version": "1.17.0", "files": [_whl("six-1.17.0-py2.py3-none-any.whl", "1")]},
        {"name": "attrs", "version": "24.2.0", "files": [_whl("attrs-24.2.0-py3-none-any.whl", "2")]},
        {"name": "regex", "version": "2024.11.6", "files": [_whl("regex-2024.11.6-py3-none-any.whl", "3")]},
    ])
    result = translate_pdm(all_dicts, lock, _lock_model(projects = ["*"]))
    env.expect.that_collection(result["pins"].keys()).contains_exactly(["attrs", "regex", "six"])

def _test_pdm_multi_project_workspace(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_multi_project_workspace_impl)

# --- test_pdm_forked_transitive_dep ---

# buildifier: disable=unused-variable
def _test_pdm_forked_transitive_dep_impl(env, target):
    project = _minimal_project(deps = ["app==1.0.0"])
    lock = _minimal_lock([
        {
            "name": "app",
            "version": "1.0.0",
            "dependencies": ["lib>=1.0"],
            "files": [_whl("app-1.0.0-py3-none-any.whl", "a")],
        },
        {
            "name": "lib",
            "version": "1.5.0",
            "marker": 'python_version < "3.10"',
            "files": [_whl("lib-1.5.0-py3-none-any.whl", "1")],
        },
        {
            "name": "lib",
            "version": "2.0.0",
            "marker": 'python_version >= "3.10"',
            "files": [_whl("lib-2.0.0-py3-none-any.whl", "2")],
        },
    ])
    result = translate_pdm(project, lock, _lock_model())
    edges = {d["name"] + "@" + d["version"]: d["marker"] for d in result["packages"]["app@1.0.0"]["dependencies"]}
    env.expect.that_dict(edges).contains_exactly({
        "lib@1.5.0": 'python_version < "3.10"',
        "lib@2.0.0": 'python_version >= "3.10"',
    })

def _test_pdm_forked_transitive_dep(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_forked_transitive_dep_impl)

# --- test_pdm_extra_package_entry_markers ---

# buildifier: disable=unused-variable
def _test_pdm_extra_package_entry_markers_impl(env, target):
    project = _minimal_project(deps = ["foo[bar,qux]==1.0", "foo[solo]==1.0"])
    lock = _minimal_lock([
        {
            "name": "foo",
            "version": "1.0",
            "dependencies": ["base-dep==1.0"],
            "files": [_whl("foo-1.0-py3-none-any.whl", "f")],
        },
        {
            "name": "foo",
            "version": "1.0",
            "extras": ["solo"],
            "dependencies": [
                "foo==1.0",
                "solo-dep==1.0",
                'solo-win==1.0 ; sys_platform == "win32"',
            ],
            "files": [_whl("foo-1.0-py3-none-any.whl", "f")],
        },
        {
            "name": "foo",
            "version": "1.0",
            "extras": ["bar", "qux"],
            "dependencies": [
                "foo==1.0",
                "combo-dep==1.0",
                'combo-py310==1.0 ; python_version >= "3.10"',
                'explicit-bar==1.0 ; extra == "bar"',
            ],
            "files": [_whl("foo-1.0-py3-none-any.whl", "f")],
        },
        {"name": "base-dep", "version": "1.0", "files": [_whl("base_dep-1.0-py3-none-any.whl", "1")]},
        {"name": "solo-dep", "version": "1.0", "files": [_whl("solo_dep-1.0-py3-none-any.whl", "2")]},
        {"name": "solo-win", "version": "1.0", "files": [_whl("solo_win-1.0-py3-none-any.whl", "3")]},
        {"name": "combo-dep", "version": "1.0", "files": [_whl("combo_dep-1.0-py3-none-any.whl", "4")]},
        {"name": "combo-py310", "version": "1.0", "files": [_whl("combo_py310-1.0-py3-none-any.whl", "5")]},
        {"name": "explicit-bar", "version": "1.0", "files": [_whl("explicit_bar-1.0-py3-none-any.whl", "6")]},
    ])
    result = translate_pdm(project, lock, _lock_model())
    edges = {d["name"]: d["marker"] for d in result["packages"]["foo@1.0"]["dependencies"]}
    env.expect.that_dict(edges).contains_exactly({
        "base-dep": "",
        "solo-dep": 'extra == "solo"',
        "solo-win": '(sys_platform == "win32") and extra == "solo"',
        "combo-dep": 'extra == "bar" or extra == "qux"',
        "combo-py310": '(python_version >= "3.10") and (extra == "bar" or extra == "qux")',
        "explicit-bar": 'extra == "bar"',
    })

def _test_pdm_extra_package_entry_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_extra_package_entry_markers_impl)

# buildifier: disable=unused-variable
def _test_discover_pdm_all_members_impl(env, target):
    lock_toml = "\n".join([
        "[[package]]",
        'name = "app-a"',
        'version = "0.1.0"',
        "editable = true",
        'path = "apps/a"',
        "[[package]]",
        'name = "ext-lib"',
        'version = "0.1.0"',
        "editable = true",
        'path = "../../libs/ext"',
        "[[package]]",
        'name = "non-editable"',
        'version = "0.1.0"',
        'path = "vendor/pkg"',
        "[[package]]",
        'name = "six"',
        'version = "1.17.0"',
    ])
    mctx = struct(
        path = lambda _lbl: struct(exists = True),
        read = lambda _path: lock_toml,
    )
    members = discover_pdm_all_members(mctx, Label("//:pdm.lock"))
    env.expect.that_collection([(m.name, m.path) for m in members]).contains_exactly([
        ("app-a", "apps/a"),
    ]).in_order()

def _test_discover_pdm_all_members(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_discover_pdm_all_members_impl)

# buildifier: disable=unused-variable
def _test_pdm_workspace_cache_matches_standalone_impl(env, target):
    """Cached multi-member PDM translation and resolve_workspace match standalone runs exactly."""
    proj_a = {
        "project": {
            "name": "app-a",
            "version": "0.1.0",
            "dependencies": ['forked>=1.0 ; sys_platform == "linux"', "local-lib==0.1.0"],
        },
        "dependency-groups": {"test": ["pytest==8.0.0"]},
    }
    proj_b = {
        "project": {
            "name": "app-b",
            "version": "0.1.0",
            "dependencies": ["forked>=1.0", "helper[opt]==1.0.0"],
        },
    }
    lock = _minimal_lock([
        {"name": "local-lib", "version": "0.1.0", "path": "libs/local", "dependencies": ["core==1.0.0"]},
        {"name": "core", "version": "1.0.0", "files": [_whl("core-1.0.0-py3-none-any.whl", "0")]},
        {"name": "forked", "version": "1.0.0", "marker": 'python_version < "3.11"', "files": [_whl("forked-1.0.0-py3-none-any.whl", "1")]},
        {"name": "forked", "version": "2.0.0", "marker": 'python_version >= "3.11"', "files": [_whl("forked-2.0.0-py3-none-any.whl", "2")]},
        {"name": "pytest", "version": "8.0.0", "files": [_whl("pytest-8.0.0-py3-none-any.whl", "3")]},
        {
            "name": "helper",
            "version": "1.0.0",
            "dependencies": ['opt-dep==1.0.0 ; extra == "opt"'],
            "files": [_whl("helper-1.0.0-py3-none-any.whl", "4")],
        },
        {"name": "opt-dep", "version": "1.0.0", "files": [_whl("opt_dep-1.0.0-py3-none-any.whl", "5")]},
    ])
    model_a = struct(
        projects = ["app-a"],
        dependency_groups = ["default", "group:test"],
        testonly_groups = ["group:test"],
        non_testonly_groups = ["default"],
        wildcard_testonly = False,
    )
    model_b = _lock_model(projects = ["app-b"])
    model_all = _lock_model(projects = ["*"], dependency_groups = ["*"])

    cases = [
        ("app_a", [proj_a], model_a, True, True),
        ("app_b", [proj_b], model_b, False, False),
        ("ws__build", [proj_a, proj_b], model_all, True, False),
    ]

    ws_cache = {}
    cached_raw = {}
    member_entries = []
    for repo_name, projects, model, inc_trans, trans_testonly in cases:
        cached = translate_pdm(projects, lock, model, workspace_cache = ws_cache)
        cached_raw[repo_name] = cached
        member_entries.append(struct(
            name = repo_name,
            lock_model_data = cached,
            include_transitive = inc_trans,
            transitive_testonly = trans_testonly,
        ))

    env.expect.that_bool(ws_cache.get("shared_packages", False)).equals(True)

    standalone_raw = {}
    for repo_name, projects, model, _inc_trans, _trans_testonly in cases:
        standalone = translate_pdm(projects, lock, model)
        env.expect.that_str(json.encode(cached_raw[repo_name])).equals(json.encode(standalone))
        standalone_raw[repo_name] = standalone

    hoisted_resolved = resolve_workspace(member_entries, shared_packages = True)
    for repo_name, _projects, _model, inc_trans, trans_testonly in cases:
        standalone_res = resolve(
            standalone_raw[repo_name],
            include_transitive = inc_trans,
            transitive_testonly = trans_testonly,
        )
        expected_dict = {
            "packages": standalone_res.packages,
            "pins": standalone_res.pins,
            "remote_files": standalone_res.remote_files,
            "cycle_groups": standalone_res.cycle_groups,
            "variants": standalone_res.variants,
            "resolution_marker_exprs": standalone_res.resolution_marker_exprs,
            "testonly_pins": standalone_res.testonly_pins,
        }
        env.expect.that_str(json.encode(hoisted_resolved[repo_name])).equals(json.encode(expected_dict))

def _test_pdm_workspace_cache_matches_standalone(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_workspace_cache_matches_standalone_impl)

# buildifier: disable=unused-variable
def _test_pdm_versionless_local_package_impl(env, target):
    project = _minimal_project(deps = ["local-lib"])
    lock = _minimal_lock([
        {
            "name": "local-lib",
            "editable": True,
            "path": "libs/local",
            "dependencies": ["core==1.0.0"],
        },
        {
            "name": "core",
            "version": "1.0.0",
            "files": [_whl("core-1.0.0-py3-none-any.whl", "1")],
        },
    ])
    result = translate_pdm(project, lock, _lock_model())
    env.expect.that_collection(result["pins"].keys()).contains_exactly(["core"])
    env.expect.that_str(result["pins"]["core"]).equals("core@1.0.0")

def _test_pdm_versionless_local_package(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pdm_versionless_local_package_impl)

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
            _test_pdm_resolution_forks,
            _test_pdm_root_dependency_markers,
            _test_pdm_git_dependency,
            _test_pdm_transitive_include_group_and_root_extra_pin,
            _test_pdm_multi_project_workspace,
            _test_pdm_forked_transitive_dep,
            _test_pdm_extra_package_entry_markers,
            _test_discover_pdm_all_members,
            _test_pdm_workspace_cache_matches_standalone,
            _test_pdm_versionless_local_package,
        ],
    )
