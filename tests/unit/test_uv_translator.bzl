"""Tests for the Starlark UV translator."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("@toml.bzl//toml:toml.bzl", "decode")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_resolver.bzl", "resolve", "resolve_workspace")

# buildifier: disable=bzl-visibility
load("//pycross/private:resolved_lock_renderer.bzl", "render_lock_bzl")

# buildifier: disable=bzl-visibility
load("//pycross/private:translator_project.bzl", "read_project_dict_for_testing")

# buildifier: disable=bzl-visibility
load("//pycross/private:translator_util.bzl", "is_external_member_path")

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "base_package_key", "base_packages_with_extras", "format_package_key", "parse_package_key")

# buildifier: disable=bzl-visibility
load("//pycross/private:uv_conflicts.bzl", "make_pin_marker_folder", "parse_uv_conflicts", "resolve_uv_pins")

# buildifier: disable=bzl-visibility
load("//pycross/private:uv_lock_model.bzl", "discover_uv_all_members", "translate_uv")

# buildifier: disable=bzl-visibility
load("//pycross/private:variant_util.bzl", "fold_variant_marker", "variant_active_tokens", "variant_conflict_pairs")

def _lock_model(
        projects = ["*"],
        dependency_groups = ["default"],
        testonly_groups = [],
        non_testonly_groups = [],
        wildcard_testonly = False,
        is_build_tools_repo = False):
    return struct(
        projects = projects,
        dependency_groups = dependency_groups,
        testonly_groups = testonly_groups,
        non_testonly_groups = non_testonly_groups,
        wildcard_testonly = wildcard_testonly,
        is_build_tools_repo = is_build_tools_repo,
    )

def _project(name = "my-app", version = "0.1.0", deps = None, opt_deps = None, dep_groups = None, uv_conflicts = None, uv_default_groups = None):
    p = {"project": {"name": name, "version": version, "dependencies": deps or []}}
    if opt_deps:
        p["project"]["optional-dependencies"] = opt_deps
    if dep_groups:
        p["dependency-groups"] = dep_groups
    tool_uv = {}
    if uv_conflicts:
        tool_uv["conflicts"] = uv_conflicts
    if uv_default_groups:
        tool_uv["default-groups"] = uv_default_groups
    if tool_uv:
        p["tool"] = {"uv": tool_uv}
    return p

def _lock(packages, requires_python = ">=3.8", conflicts = None, manifest = None):
    d = {"version": 1, "requires-python": requires_python, "package": packages}
    if conflicts:
        d["conflicts"] = conflicts
    if manifest != None:
        d["manifest"] = manifest
    return d

def _vpkg(name, version = "0.1.0", deps = None, opt_deps = None, dev_deps = None):
    """Virtual (source=virtual) package for project root."""
    p = {"name": name, "version": version, "source": {"virtual": "."}}
    if deps:
        p["dependencies"] = deps
    if opt_deps:
        p["optional-dependencies"] = opt_deps
    if dev_deps:
        p["dev-dependencies"] = dev_deps
    return p

def _pkg(name, version, wheels = None, deps = None, markers = None, source = None, opt_deps = None):
    """Regular package."""
    p = {"name": name, "version": version}
    if wheels:
        p["wheels"] = wheels
    if deps:
        p["dependencies"] = deps
    if markers:
        p["resolution-markers"] = markers
    if source:
        p["source"] = source
    if opt_deps:
        p["optional-dependencies"] = opt_deps
    return p

def _whl(name = None, sha256 = "1234", url = None):
    w = {}
    if name:
        w["file"] = name
    if url:
        w["url"] = url
    w["hash"] = "sha256:" + sha256
    return w

def _dep(name, version = None, marker = None, extra = None, source = None):
    d = {"name": name}
    if version:
        d["version"] = version
    if marker:
        d["marker"] = marker
    if extra:
        d["extra"] = extra
    if source:
        d["source"] = source
    return d

# --- test_minimal_lock ---

# buildifier: disable=unused-variable
def _test_uv_minimal_lock_impl(env, target):
    project = _project(deps = ["requests==2.31.0"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("requests", "2.31.0")]),
        _pkg("requests", "2.31.0", wheels = [_whl("requests-2.31.0-py3-none-any.whl", "abc")]),
    ])
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_collection(result["packages"].keys()).contains_exactly(["requests@2.31.0"])
    pkg = result["packages"]["requests@2.31.0"]

    files = pkg["files"]
    env.expect.that_collection(files).has_size(1)
    env.expect.that_str(files[0]["package_name"]).equals("requests")
    env.expect.that_str(files[0]["package_version"]).equals("2.31.0")

def _test_uv_minimal_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_minimal_lock_impl)

# --- test_distribution_package_compat ---

# buildifier: disable=unused-variable
def _test_uv_distribution_compat_impl(env, target):
    project = _project(deps = ["requests==2.31.0"])
    lock = {
        "version": 1,
        "requires-python": ">=3.8",
        "distribution": [
            _vpkg("my-app", deps = [_dep("requests", "2.31.0")]),
            _pkg("requests", "2.31.0", wheels = [_whl("requests-2.31.0-py3-none-any.whl", "abc")]),
        ],
    }
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_int(len(result["packages"])).equals(1)

def _test_uv_distribution_compat(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_distribution_compat_impl)

# --- test_multiple_packages_with_deps ---

# buildifier: disable=unused-variable
def _test_uv_multiple_packages_with_deps_impl(env, target):
    project = _project(deps = ["a==1.0"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("a", "1.0")]),
        _pkg("a", "1.0", wheels = [_whl("a-1.0-py3-none-any.whl", "a")], deps = [_dep("b", "2.0")]),
        _pkg("b", "2.0", wheels = [_whl("b-2.0-py3-none-any.whl", "b")]),
    ])
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_int(len(result["packages"])).equals(2)
    pkg_a = result["packages"]["a@1.0"]
    env.expect.that_int(len(pkg_a["dependencies"])).equals(1)

def _test_uv_multiple_packages_with_deps(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_multiple_packages_with_deps_impl)

# --- test_platform_specific_deps ---

# buildifier: disable=unused-variable
def _test_uv_platform_specific_deps_impl(env, target):
    project = _project(deps = ["a==1.0"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("a")]),
        _pkg("a", "1.0", wheels = [_whl("a-1.0-py3-none-any.whl", "a")], deps = [_dep("b", marker = "sys_platform == 'linux'")]),
        _pkg("b", "2.0", wheels = [_whl("b-2.0-py3-none-any.whl", "b")]),
    ])
    result = translate_uv(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    dep_b = pkg_a["dependencies"][0]
    env.expect.that_str(dep_b["marker"]).contains("sys_platform")

def _test_uv_platform_specific_deps(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_platform_specific_deps_impl)

# --- test_virtual_package ---

# buildifier: disable=unused-variable
def _test_uv_virtual_package_impl(env, target):
    project = _project()
    lock = _lock([
        _vpkg("my-app"),
        {"name": "vpkg", "version": "1.0.0", "source": {"virtual": "."}},
    ])
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_int(len(result["packages"])).equals(0)

def _test_uv_virtual_package(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_virtual_package_impl)

# --- test_editable_package ---

# buildifier: disable=unused-variable
def _test_uv_editable_package_impl(env, target):
    project = _project()
    lock = _lock([
        {"name": "my-app", "version": "0.1.0", "source": {"editable": "."}},
        {"name": "epkg", "version": "1.0.0", "source": {"editable": "."}},
    ])
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_int(len(result["packages"])).equals(0)

def _test_uv_editable_package(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_editable_package_impl)

# --- test_wheels_with_urls ---

# buildifier: disable=unused-variable
def _test_uv_wheels_with_urls_impl(env, target):
    project = _project(deps = ["a==1.0"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("a")]),
        _pkg("a", "1.0", wheels = [_whl(url = "https://example.com/a-1.0-py3-none-any.whl", sha256 = "a")]),
    ])
    result = translate_uv(project, lock, _lock_model())
    pkg = result["packages"]["a@1.0"]
    env.expect.that_collection(pkg["files"][0]["urls"]).contains("https://example.com/a-1.0-py3-none-any.whl")

def _test_uv_wheels_with_urls(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_wheels_with_urls_impl)

# --- test_no_static_urls ---

# buildifier: disable=unused-variable
def _test_uv_no_static_urls_impl(env, target):
    project = _project(deps = ["a==1.0"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("a")]),
        _pkg("a", "1.0", wheels = [_whl("a-1.0-py3-none-any.whl", "a")]),
    ])
    result = translate_uv(project, lock, _lock_model())
    pkg = result["packages"]["a@1.0"]
    env.expect.that_int(len(pkg["files"][0].get("urls", []))).equals(0)

def _test_uv_no_static_urls(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_no_static_urls_impl)

# --- test_resolution_markers ---

# buildifier: disable=unused-variable
def _test_uv_resolution_markers_impl(env, target):
    project = _project(deps = ["a"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("a")]),
        _pkg("a", "1.0", wheels = [_whl("a-1.0-py3-none-any.whl", "a")], markers = ["python_full_version == '3.8.0'"]),
        _pkg("a", "2.0", wheels = [_whl("a-2.0-py3-none-any.whl", "a2")], markers = ["python_full_version == '3.9.0'"]),
    ])
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_collection(result["packages"].keys()).contains_at_least(["a@1.0", "a@2.0"])

def _test_uv_resolution_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_resolution_markers_impl)

# --- test_workspace_members ---

# buildifier: disable=unused-variable
def _test_uv_workspace_members_impl(env, target):
    project = _project(deps = ["lib==1.0", "a==1.0"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("lib"), _dep("a")]),
        {"name": "lib", "version": "1.0", "source": {"editable": "lib"}},
        _pkg("a", "1.0", wheels = [_whl("a-1.0-py3-none-any.whl", "a")]),
    ])
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_int(len(result["packages"])).equals(1)
    env.expect.that_collection(result["packages"].keys()).contains("a@1.0")

def _test_uv_workspace_members(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_workspace_members_impl)

# --- test_dev_dependencies_pep735 ---

# buildifier: disable=unused-variable
def _test_uv_dev_dependencies_pep735_impl(env, target):
    project = _project(dep_groups = {"dev": ["b==2.0"]})
    lock = _lock([
        _vpkg("my-app", dev_deps = {"dev": [_dep("b")]}),
        _pkg("b", "2.0", wheels = [_whl("b-2.0-py3-none-any.whl", "b")]),
    ])
    result = translate_uv(project, lock, _lock_model(dependency_groups = ["default", "group:dev"]))
    env.expect.that_int(len(result["packages"])).equals(1)
    env.expect.that_collection(result["packages"].keys()).contains("b@2.0")

def _test_uv_dev_dependencies_pep735(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_dev_dependencies_pep735_impl)

# --- test_optional_dependencies_extras ---

# buildifier: disable=unused-variable
def _test_uv_optional_dependencies_extras_impl(env, target):
    project = _project(deps = ["a[test]==1.0"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("a")]),
        _pkg(
            "a",
            "1.0",
            wheels = [_whl("a-1.0-py3-none-any.whl", "a")],
            opt_deps = {"test": [_dep("b")]},
        ),
        _pkg("b", "2.0", wheels = [_whl("b-2.0-py3-none-any.whl", "b")]),
    ])
    result = translate_uv(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    env.expect.that_int(len(pkg_a["dependencies"])).equals(0)

def _test_uv_optional_dependencies_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_optional_dependencies_extras_impl)

# --- test_extra_variants ---

_CONFLICT_LOCK_PACKAGES = [
    _vpkg("my-app", opt_deps = {
        "cpu": [_dep("torch", "2.6.0")],
        "cu124": [_dep("torch", "2.7.0")],
    }),
    _pkg("torch", "2.6.0", wheels = [_whl("torch-2.6.0-py3-none-any.whl", "aaa")]),
    _pkg("torch", "2.7.0", wheels = [_whl("torch-2.7.0-py3-none-any.whl", "bbb")]),
]

_CONFLICT_CONFLICTS = [[
    {"package": "my-app", "extra": "cpu"},
    {"package": "my-app", "extra": "cu124"},
]]

_CONFLICT_PROJECT = _project(
    opt_deps = {"cpu": ["torch==2.6.0"], "cu124": ["torch==2.7.0"]},
    uv_conflicts = [[{"extra": "cpu"}, {"extra": "cu124"}]],
)

# buildifier: disable=unused-variable
def _test_uv_extra_variants_impl(env, target):
    lock = _lock(_CONFLICT_LOCK_PACKAGES, conflicts = _CONFLICT_CONFLICTS)
    result = translate_uv(_CONFLICT_PROJECT, lock, _lock_model(dependency_groups = ["optional:*"]))
    env.expect.that_int(len(result.get("variants", []))).equals(1)
    vs = result["variants"][0]
    names = ["{}_{}".format(item["kind"], item.get("name", "")) for item in vs["items"]]
    env.expect.that_collection(names).contains_at_least(["extra_cpu", "extra_cu124"])

    # Pins should have variant keys
    torch_pin = result["pins"]["torch"]
    env.expect.that_collection(torch_pin.keys()).contains_at_least(["extra_my-app_cpu", "extra_my-app_cu124"])

    # The repo's own items get `<kind>_<name>` and `<kind>_<project>_<name>` flags.
    flags = {item["name"]: item["flags"] for item in vs["items"]}
    env.expect.that_dict(flags).contains_exactly({
        "cpu": ["extra_cpu", "extra_my-app_cpu"],
        "cu124": ["extra_cu124", "extra_my-app_cu124"],
    })

def _test_uv_extra_variants(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_extra_variants_impl)

# --- test_group_variants ---

# buildifier: disable=unused-variable
def _test_uv_group_variants_impl(env, target):
    project = _project(
        dep_groups = {"test-fast": ["pytest==7.0.0"], "test-slow": ["pytest==8.0.0"]},
        uv_conflicts = [[{"group": "test-fast"}, {"group": "test-slow"}]],
    )
    lock = _lock(
        [
            _vpkg("my-app", dev_deps = {
                "test-fast": [_dep("pytest", "7.0.0")],
                "test-slow": [_dep("pytest", "8.0.0")],
            }),
            _pkg("pytest", "7.0.0", wheels = [_whl("pytest-7.0.0-py3-none-any.whl", "ccc")]),
            _pkg("pytest", "8.0.0", wheels = [_whl("pytest-8.0.0-py3-none-any.whl", "ddd")]),
        ],
        conflicts = [[
            {"package": "my-app", "group": "test-fast"},
            {"package": "my-app", "group": "test-slow"},
        ]],
    )
    result = translate_uv(project, lock, _lock_model(dependency_groups = ["group:*"]))
    env.expect.that_int(len(result.get("variants", []))).equals(1)
    vs = result["variants"][0]
    names = ["{}_{}".format(item["kind"], item.get("name", "")) for item in vs["items"]]
    env.expect.that_collection(names).contains_at_least(["group_test-fast", "group_test-slow"])

def _test_uv_group_variants(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_group_variants_impl)

# --- test_no_variants ---

# buildifier: disable=unused-variable
def _test_uv_no_variants_impl(env, target):
    project = _project(deps = ["requests==2.31.0"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("requests", "2.31.0")]),
        _pkg("requests", "2.31.0", wheels = [_whl("requests-2.31.0-py3-none-any.whl", "abc")]),
    ])
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_int(len(result.get("variants", []))).equals(0)

def _test_uv_no_variants(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_no_variants_impl)

# --- test_dependencies_with_extra ---

# buildifier: disable=unused-variable
def _test_uv_dependencies_with_extra_impl(env, target):
    project = _project()
    lock = _lock([
        _vpkg("my-app", deps = [_dep("a", extra = ["test"])]),
        _pkg("a", "1.0", wheels = [_whl("a-1.0-py3-none-any.whl", "a")], opt_deps = {"test": [_dep("b")]}),
        _pkg("b", "2.0", wheels = [_whl("b-2.0-py3-none-any.whl", "b")]),
    ])
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_collection(result["packages"].keys()).contains("a[test]@1.0")

def _test_uv_dependencies_with_extra(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_dependencies_with_extra_impl)

# --- test_unconditional_pins_are_bare ---

# buildifier: disable=unused-variable
def _test_uv_unconditional_pins_are_bare_impl(env, target):
    project = _project(deps = ["requests==2.31.0"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("requests", "2.31.0")]),
        _pkg("requests", "2.31.0", wheels = [_whl("requests-2.31.0-py3-none-any.whl", "abc")]),
    ])
    result = translate_uv(project, lock, _lock_model())
    requests_pin = result["pins"]["requests"]

    # It should be a string, not a dict
    env.expect.that_str(requests_pin).equals("requests@2.31.0")

def _test_uv_unconditional_pins_are_bare(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_unconditional_pins_are_bare_impl)

# --- test_resolution_marker_fork_conditional_pins ---

# buildifier: disable=unused-variable
def _test_uv_resolution_marker_fork_conditional_pins_impl(env, target):
    """When uv forks to different versions, pins should be conditional."""
    project = _project(deps = ["numpy"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("numpy", "2.3.4"), _dep("numpy", "2.3.3")]),
        _pkg("numpy", "2.3.4", wheels = [_whl("numpy-2.3.4-cp312-cp312-manylinux_2_17_x86_64.whl", "a1")], markers = ["sys_platform == 'linux'"]),
        _pkg("numpy", "2.3.3", wheels = [_whl("numpy-2.3.3-cp312-cp312-macosx_11_0_arm64.whl", "a2")], markers = ["sys_platform == 'darwin'"]),
    ])
    result = translate_uv(project, lock, _lock_model())

    # Both versions should exist
    env.expect.that_collection(result["packages"].keys()).contains_at_least(["numpy@2.3.4", "numpy@2.3.3"])

    # Pin should be conditional (a dict, not a bare string)
    numpy_pin = result["pins"]["numpy"]
    env.expect.that_int(len(numpy_pin)).equals(2)
    env.expect.that_str(numpy_pin["res_numpy_2_3_4"]).equals("numpy@2.3.4")
    env.expect.that_str(numpy_pin["res_numpy_2_3_3"]).equals("numpy@2.3.3")

    # resolution_marker_exprs should have the marker expressions
    exprs = result["resolution_marker_exprs"]
    env.expect.that_str(exprs["res_numpy_2_3_4"]).equals("sys_platform == 'linux'")
    env.expect.that_str(exprs["res_numpy_2_3_3"]).equals("sys_platform == 'darwin'")

def _test_uv_resolution_marker_fork_conditional_pins(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_resolution_marker_fork_conditional_pins_impl)

# --- test_resolution_marker_single_version_no_fork ---

# buildifier: disable=unused-variable
def _test_uv_resolution_marker_single_version_no_fork_impl(env, target):
    """When resolution-markers exist but only one version, no fork needed."""
    project = _project(deps = ["numpy==2.3.4"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("numpy", "2.3.4")]),
        _pkg("numpy", "2.3.4", wheels = [_whl("numpy-2.3.4-cp312-cp312-manylinux_2_17_x86_64.whl", "a1")], markers = ["sys_platform == 'linux'"]),
    ])
    result = translate_uv(project, lock, _lock_model())

    # Pin should be unconditional (a bare string)
    numpy_pin = result["pins"]["numpy"]
    env.expect.that_str(numpy_pin).equals("numpy@2.3.4")

    # No resolution_marker_exprs should be present
    env.expect.that_bool("resolution_marker_exprs" in result).equals(False)

def _test_uv_resolution_marker_single_version_no_fork(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_resolution_marker_single_version_no_fork_impl)

# --- test_resolution_marker_multi_marker_or ---

# buildifier: disable=unused-variable
def _test_uv_resolution_marker_multi_marker_or_impl(env, target):
    """Multiple resolution-markers on a version should be OR'd."""
    project = _project(deps = ["numpy"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("numpy", "2.3.4"), _dep("numpy", "2.3.3")]),
        _pkg(
            "numpy",
            "2.3.4",
            wheels = [_whl("numpy-2.3.4-cp312-cp312-manylinux_2_17_x86_64.whl", "a1")],
            markers = [
                "python_full_version >= '3.12' and sys_platform == 'linux'",
                "python_full_version < '3.12' and sys_platform == 'linux'",
            ],
        ),
        _pkg("numpy", "2.3.3", wheels = [_whl("numpy-2.3.3-cp312-cp312-macosx_11_0_arm64.whl", "a2")], markers = ["sys_platform == 'darwin'"]),
    ])
    result = translate_uv(project, lock, _lock_model())
    exprs = result["resolution_marker_exprs"]

    # 2.3.4 should have its markers OR'd together
    env.expect.that_str(exprs["res_numpy_2_3_4"]).equals(
        "(python_full_version >= '3.12' and sys_platform == 'linux') or (python_full_version < '3.12' and sys_platform == 'linux')",
    )

    # 2.3.3 has a single marker, no parens needed
    env.expect.that_str(exprs["res_numpy_2_3_3"]).equals("sys_platform == 'darwin'")

def _test_uv_resolution_marker_multi_marker_or(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_resolution_marker_multi_marker_or_impl)

# --- test_resolution_marker_fork_optional_group ---

# buildifier: disable=unused-variable
def _test_uv_resolution_marker_fork_optional_group_impl(env, target):
    """Forked dep in an optional group produces compound constraints."""
    project = _project(
        uv_conflicts = [[{"package": "my-app", "extra": "science"}]],
        opt_deps = {"science": ["numpy"]},
    )
    lock = _lock(
        [
            _vpkg("my-app", opt_deps = {"science": [_dep("numpy", "2.3.4"), _dep("numpy", "2.3.3")]}),
            _pkg("numpy", "2.3.4", wheels = [_whl("numpy-2.3.4-cp312-cp312-manylinux_2_17_x86_64.whl", "a1")], markers = ["sys_platform == 'linux'"]),
            _pkg("numpy", "2.3.3", wheels = [_whl("numpy-2.3.3-cp312-cp312-macosx_11_0_arm64.whl", "a2")], markers = ["sys_platform == 'darwin'"]),
        ],
        conflicts = [[{"package": "my-app", "extra": "science"}]],
    )
    result = translate_uv(project, lock, _lock_model(dependency_groups = ["default", "optional:science"]))

    # Pin should have compound constraint names.
    numpy_pin = result["pins"]["numpy"]
    env.expect.that_int(len(numpy_pin)).equals(2)
    env.expect.that_str(numpy_pin["extra_my-app_science_res_numpy_2_3_4"]).equals("numpy@2.3.4")
    env.expect.that_str(numpy_pin["extra_my-app_science_res_numpy_2_3_3"]).equals("numpy@2.3.3")

    # Compound entries should store component info.
    exprs = result["resolution_marker_exprs"]
    compound_2_3_4 = exprs["extra_my-app_science_res_numpy_2_3_4"]
    env.expect.that_str(compound_2_3_4["variant"]).equals("extra_my-app_science")
    env.expect.that_str(compound_2_3_4["marker"]).equals("res_numpy_2_3_4")

    # Simple entries should still be strings.
    env.expect.that_str(exprs["res_numpy_2_3_4"]).equals("sys_platform == 'linux'")

def _test_uv_resolution_marker_fork_optional_group(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_resolution_marker_fork_optional_group_impl)

# --- test_testonly_groups ---

# buildifier: disable=unused-variable
def _test_uv_testonly_groups_impl(env, target):
    """Dev group marked as testonly produces testonly_pins in the raw lock data."""
    project = _project(
        deps = ["requests==2.31.0"],
        dep_groups = {"test": ["pytest==7.0"]},
    )
    lock = _lock([
        _vpkg("my-app", deps = [_dep("requests", "2.31.0")], dev_deps = {"test": [_dep("pytest")]}),
        _pkg("requests", "2.31.0", wheels = [_whl("requests-2.31.0-py3-none-any.whl", "abc")]),
        _pkg("pytest", "7.0", wheels = [_whl("pytest-7.0-py3-none-any.whl", "def")]),
    ])
    result = translate_uv(
        project,
        lock,
        _lock_model(dependency_groups = ["default", "group:test"], testonly_groups = ["group:test"]),
    )

    # Both packages should be resolved
    env.expect.that_collection(result["packages"].keys()).contains("requests@2.31.0")
    env.expect.that_collection(result["packages"].keys()).contains("pytest@7.0")

    # pytest should be in testonly_pins because its group is testonly
    env.expect.that_collection(result["testonly_pins"]).contains("pytest")

    # requests should NOT be in testonly_pins
    env.expect.that_collection(result["testonly_pins"]).contains_none_of(["requests"])

def _test_uv_testonly_groups(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_testonly_groups_impl)

# --- test_testonly_shared_dep_not_testonly ---

# buildifier: disable=unused-variable
def _test_uv_testonly_shared_dep_not_testonly_impl(env, target):
    """A package required by both default and testonly groups is NOT testonly."""
    project = _project(
        deps = ["common==1.0"],
        dep_groups = {"test": ["common==1.0", "pytest==7.0"]},
    )
    lock = _lock([
        _vpkg("my-app", deps = [_dep("common", "1.0")], dev_deps = {"test": [_dep("common"), _dep("pytest")]}),
        _pkg("common", "1.0", wheels = [_whl("common-1.0-py3-none-any.whl", "aaa")]),
        _pkg("pytest", "7.0", wheels = [_whl("pytest-7.0-py3-none-any.whl", "bbb")]),
    ])
    result = translate_uv(
        project,
        lock,
        _lock_model(dependency_groups = ["default", "group:test"], testonly_groups = ["group:test"]),
    )

    # pytest is exclusively testonly
    env.expect.that_collection(result["testonly_pins"]).contains("pytest")

    # common appears in both default and test groups, so NOT testonly
    env.expect.that_collection(result["testonly_pins"]).contains_none_of(["common"])

def _test_uv_testonly_shared_dep_not_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_testonly_shared_dep_not_testonly_impl)

# --- test_testonly_wildcard_with_override ---

# buildifier: disable=unused-variable
def _test_uv_testonly_wildcard_with_override_impl(env, target):
    """['*;testonly', 'group:dev'] -> everything testonly except dev.

    Simulates: dependency_groups = ['*;testonly', 'group:dev']
    Parsed by process_repo as: wildcard_testonly=True, non_testonly_groups=['group:dev']
    """
    project = _project(
        deps = ["requests==2.31.0"],
        dep_groups = {"dev": ["flask==2.0"], "test": ["pytest==7.0"]},
    )
    lock = _lock([
        _vpkg("my-app", deps = [_dep("requests", "2.31.0")], dev_deps = {"dev": [_dep("flask")], "test": [_dep("pytest")]}),
        _pkg("requests", "2.31.0", wheels = [_whl("requests-2.31.0-py3-none-any.whl", "abc")]),
        _pkg("flask", "2.0", wheels = [_whl("flask-2.0-py3-none-any.whl", "def")]),
        _pkg("pytest", "7.0", wheels = [_whl("pytest-7.0-py3-none-any.whl", "ghi")]),
    ])
    result = translate_uv(
        project,
        lock,
        _lock_model(
            dependency_groups = ["default", "group:dev", "group:test"],
            # *;testonly -> wildcard_testonly=True, group:dev overrides to non-testonly
            wildcard_testonly = True,
            non_testonly_groups = ["group:dev"],
        ),
    )

    # pytest is testonly (from wildcard, no override)
    env.expect.that_collection(result["testonly_pins"]).contains("pytest")

    # flask is NOT testonly (group:dev explicitly overridden)
    env.expect.that_collection(result["testonly_pins"]).contains_none_of(["flask"])

def _test_uv_testonly_wildcard_with_override(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_testonly_wildcard_with_override_impl)

# --- test_testonly_wildcard_overrides_earlier ---

# buildifier: disable=unused-variable
def _test_uv_testonly_wildcard_overrides_earlier_impl(env, target):
    """['group:dev;testonly', '*'] -> wildcard last, overrides dev to non-testonly.

    Simulates: dependency_groups = ['group:dev;testonly', '*']
    Parsed by process_repo as: wildcard_testonly=False, testonly_groups=[], non_testonly_groups=[]
    (The * resets overrides, so group:dev;testonly is forgotten)
    """
    project = _project(
        deps = ["requests==2.31.0"],
        dep_groups = {"dev": ["pytest==7.0"]},
    )
    lock = _lock([
        _vpkg("my-app", deps = [_dep("requests", "2.31.0")], dev_deps = {"dev": [_dep("pytest")]}),
        _pkg("requests", "2.31.0", wheels = [_whl("requests-2.31.0-py3-none-any.whl", "abc")]),
        _pkg("pytest", "7.0", wheels = [_whl("pytest-7.0-py3-none-any.whl", "def")]),
    ])
    result = translate_uv(
        project,
        lock,
        _lock_model(
            dependency_groups = ["default", "group:dev"],
            # group:dev;testonly then * -> wildcard_testonly=False, no specific overrides
            wildcard_testonly = False,
            testonly_groups = [],
            non_testonly_groups = [],
        ),
    )

    # Nothing is testonly: * came last and reset everything
    env.expect.that_collection(result["testonly_pins"]).has_size(0)

def _test_uv_testonly_wildcard_overrides_earlier(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_testonly_wildcard_overrides_earlier_impl)

# --- test_uv_root_dependency_markers ---

# buildifier: disable=unused-variable
def _test_uv_root_dependency_markers_impl(env, target):
    project = _project(deps = [
        "foo==1.0",
        "foo[linux-extra]==1.0 ; sys_platform == \"linux\"",
    ])
    lock = _lock([
        _vpkg("my-app", deps = [
            _dep("foo", "1.0"),
            _dep("foo", "1.0", marker = "sys_platform == \"linux\"", extra = ["linux-extra"]),
        ]),
        _pkg("foo", "1.0", wheels = [_whl("foo-1.0-py3-none-any.whl", "foo")], opt_deps = {"linux-extra": []}),
    ])
    result = translate_uv(project, lock, _lock_model())

    # The unmarked base pin is available everywhere. The marked extra remains
    # separate so its marker cannot make the extra available on other platforms.
    markers = result["root_dependency_markers"]
    env.expect.that_collection(markers.keys()).contains("foo[linux-extra]")
    env.expect.that_collection(markers.keys()).contains_none_of(["foo"])
    env.expect.that_str(markers["foo[linux-extra]"][0]).equals("sys_platform == \"linux\"")

# --- test_local_member_dep_keeps_forks_extras_markers ---

# buildifier: disable=unused-variable
def _test_uv_local_member_deps_keep_forks_impl(env, target):
    """Deps reached through an editable member keep forks, extras and markers."""
    project = _project(name = "app", deps = ["lib"])
    lock = _lock([
        _pkg("app", "0.1.0", source = {"editable": "."}, deps = [_dep("lib")]),
        _pkg("lib", "0.1.0", source = {"editable": "lib"}, deps = [
            _dep("numpy", "1.26.4", marker = "python_full_version < '3.10'"),
            _dep("numpy", "2.2.0", marker = "python_full_version >= '3.10'"),
            _dep("uvloop", marker = "sys_platform != 'win32'"),
            _dep("foo", extra = ["bar"]),
        ]),
        _pkg("numpy", "1.26.4", markers = ["python_full_version < '3.10'"], wheels = [_whl("numpy-1.26.4-cp39-cp39-manylinux_2_17_x86_64.whl", "aa")]),
        _pkg("numpy", "2.2.0", markers = ["python_full_version >= '3.10'"], wheels = [_whl("numpy-2.2.0-cp312-cp312-manylinux_2_17_x86_64.whl", "bb")]),
        _pkg("uvloop", "0.21.0", wheels = [_whl("uvloop-0.21.0-cp312-cp312-manylinux_2_17_x86_64.whl", "cc")]),
        _pkg("foo", "1.0", wheels = [_whl("foo-1.0-py3-none-any.whl", "dd")], opt_deps = {"bar": []}),
    ], requires_python = ">=3.9")
    result = translate_uv(project, lock, _lock_model(projects = ["app"]))

    env.expect.that_dict(result["pins"]["numpy"]).contains_exactly({
        "res_numpy_1_26_4": "numpy@1.26.4",
        "res_numpy_2_2_0": "numpy@2.2.0",
    })
    env.expect.that_str(result["pins"]["foo[bar]"]).equals("foo[bar]@1.0")
    env.expect.that_dict(result["root_dependency_markers"]).contains_at_least({
        "uvloop": ["sys_platform != 'win32'"],
    })

def _test_uv_local_member_deps_keep_forks(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_local_member_deps_keep_forks_impl)

# --- test_variants_scoped_to_declaring_project ---

# buildifier: disable=unused-variable
def _test_uv_variants_scoped_to_project_impl(env, target):
    """A conflict on trainer's extras doesn't gate server's same-named extra."""
    project = _project(name = "server")
    lock = _lock(
        [
            _pkg("server", "0.1.0", source = {"editable": "server"}, opt_deps = {"cpu": [_dep("six")]}),
            _pkg("trainer", "0.1.0", source = {"editable": "trainer"}, opt_deps = {"cpu": [_dep("six")], "gpu": [_dep("six")]}),
            _pkg("six", "1.17.0", wheels = [_whl("six-1.17.0-py2.py3-none-any.whl", "dd")]),
        ],
        conflicts = [[{"package": "trainer", "extra": "cpu"}, {"package": "trainer", "extra": "gpu"}]],
    )
    result = translate_uv(project, lock, _lock_model(projects = ["server"], dependency_groups = ["default", "optional:cpu"]))
    env.expect.that_str(result["pins"]["six"]).equals("six@1.17.0")

def _test_uv_variants_scoped_to_project(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_variants_scoped_to_project_impl)

# --- test_same_named_groups_across_members ---

_MEMBER_GROUP_CONFLICT_LOCK = _lock(
    [
        _pkg("app-a", "0.1.0", source = {"editable": "apps/app-a"}),
        _pkg("app-b", "0.1.0", source = {"editable": "apps/app-b"}),
        # No `test` group: a `group:test` repo spanning all members still works.
        _pkg("common", "0.1.0", source = {"editable": "libs/common"}),
        _pkg("pytest", "7.4.4", wheels = [_whl("pytest-7.4.4-py3-none-any.whl", "aaa")]),
        _pkg("pytest", "9.2.0", wheels = [_whl("pytest-9.2.0-py3-none-any.whl", "bbb")]),
    ],
    conflicts = [[{"package": "app-a", "group": "test"}, {"package": "app-b", "group": "test"}]],
)

def _member_group_conflict_lock():
    lock = dict(_MEMBER_GROUP_CONFLICT_LOCK)
    packages = [dict(p) for p in lock["package"]]
    packages[0]["dev-dependencies"] = {"test": [_dep("pytest", "7.4.4")]}
    packages[1]["dev-dependencies"] = {"test": [_dep("pytest", "9.2.0")]}
    lock["package"] = packages
    return lock

# buildifier: disable=unused-variable
def _test_uv_same_named_groups_across_members_impl(env, target):
    """Two members' conflicting `test` groups stay distinct internally; each repo's `group_test` covers its projects."""
    lock = _member_group_conflict_lock()
    result = translate_uv(_project(name = "monorepo"), lock, _lock_model(dependency_groups = ["group:test"]))
    env.expect.that_int(len(result.get("variants", []))).equals(1)
    items = result["variants"][0]["items"]

    # In a repo covering both members, `group_test` enables both members' `test`
    # groups, and `group_<member>_test` enables one.
    env.expect.that_dict({item["package"]: item["flags"] for item in items}).contains_exactly({
        "app-a": ["group_test", "group_app-a_test"],
        "app-b": ["group_test", "group_app-b_test"],
    })

    # Each member's pytest is pinned under its own (package-qualified) variant.
    pytest_pin = result["pins"]["pytest"]
    env.expect.that_dict(pytest_pin).contains_exactly({
        "group_app-a_test": "pytest@7.4.4",
        "group_app-b_test": "pytest@9.2.0",
    })

    # A repo for one member has a `group_test` flag for that member only.
    result_a = translate_uv(_project(name = "app-a"), lock, _lock_model(projects = ["app-a"], dependency_groups = ["group:test"]))
    flags_a = {item["package"]: item.get("flags") for item in result_a["variants"][0]["items"]}
    env.expect.that_dict(flags_a).contains_exactly({"app-a": ["group_test", "group_app-a_test"], "app-b": None})
    env.expect.that_dict(result_a["pins"]["pytest"]).contains_exactly({"group_app-a_test": "pytest@7.4.4"})

# buildifier: disable=unused-variable
def _test_uv_auto_pin_impl(env, target):
    """A repo that requests exactly one item of a conflict set pins it."""
    lock = _member_group_conflict_lock()

    # A test repo for app-a requests only app-a's `test` group, as with
    # `uv sync --package app-a --group test`.
    result = translate_uv(_project(name = "app-a"), lock, _lock_model(projects = ["app-a"], dependency_groups = ["group:test"]))
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("group_app-a_test")
    env.expect.that_str(result["variants"][0].get("repo_default", "")).equals("")

    # A runtime repo for app-a requests no item of the set.
    result = translate_uv(_project(name = "app-a"), lock, _lock_model(projects = ["app-a"], dependency_groups = ["default"]))
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("")

    # A repo spanning both members requests both items.
    result = translate_uv(_project(name = "monorepo"), lock, _lock_model(dependency_groups = ["group:test"]))
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("")

    # The workspace's `__build` repo never pins.
    result = translate_uv(_project(name = "app-a"), lock, _lock_model(projects = ["app-a"], dependency_groups = ["group:test"], is_build_tools_repo = True))
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("")

    # Extras work the same way, as with `uv sync --extra cpu`.
    lock = _lock(
        [
            _pkg("trainer", "0.1.0", source = {"editable": "trainer"}, opt_deps = {"cpu": [_dep("six", "1.16.0")], "gpu": [_dep("six", "1.17.0")]}),
            _pkg("six", "1.16.0", wheels = [_whl("six-1.16.0-py2.py3-none-any.whl", "aa")]),
            _pkg("six", "1.17.0", wheels = [_whl("six-1.17.0-py2.py3-none-any.whl", "bb")]),
        ],
        conflicts = [[{"package": "trainer", "extra": "cpu"}, {"package": "trainer", "extra": "gpu"}]],
    )
    result = translate_uv(_project(name = "trainer"), lock, _lock_model(projects = ["trainer"], dependency_groups = ["default", "optional:cpu"]))
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("extra_trainer_cpu")
    result = translate_uv(_project(name = "trainer"), lock, _lock_model(projects = ["trainer"], dependency_groups = ["default", "optional:*"]))
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("")

# buildifier: disable=unused-variable
def _test_uv_auto_pin_empty_extra_impl(env, target):
    """uv.lock leaves empty extras out of optional-dependencies; they still count as requested."""
    lock = _lock(
        [
            dict(
                _pkg("app", "0.1.0", source = {"editable": "."}, opt_deps = {"gpu": [_dep("six", "1.17.0")]}),
                metadata = {"provides-extras": ["cpu", "gpu"]},
            ),
            _pkg("six", "1.17.0", wheels = [_whl("six-1.17.0-py2.py3-none-any.whl", "bb")]),
        ],
        conflicts = [[{"package": "app", "extra": "cpu"}, {"package": "app", "extra": "gpu"}]],
    )
    result = translate_uv(_project(name = "app"), lock, _lock_model(projects = ["app"], dependency_groups = ["default", "optional:cpu"]))
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("extra_app_cpu")

    # `optional:*` requests both extras, so neither is pinned.
    result = translate_uv(_project(name = "app"), lock, _lock_model(projects = ["app"], dependency_groups = ["default", "optional:*"]))
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("")

def _test_uv_auto_pin_empty_extra(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_auto_pin_empty_extra_impl)

# buildifier: disable=unused-variable
def _test_uv_auto_pin_overlapping_sets_impl(env, target):
    """An item in several sets is pinned only if none of its rivals is requested."""
    lock = _lock(
        [
            dict(
                _pkg("app", "0.1.0", source = {"editable": "."}, opt_deps = {"cpu": [_dep("six", "1.16.0")], "gpu": [_dep("six", "1.17.0")]}),
                **{"dev-dependencies": {"gpu-test": [_dep("six", "1.17.0")]}}
            ),
            _pkg("six", "1.16.0", wheels = [_whl("six-1.16.0-py2.py3-none-any.whl", "aa")]),
            _pkg("six", "1.17.0", wheels = [_whl("six-1.17.0-py2.py3-none-any.whl", "bb")]),
        ],
        conflicts = [
            [{"package": "app", "extra": "cpu"}, {"package": "app", "extra": "gpu"}],
            [{"package": "app", "extra": "cpu"}, {"package": "app", "group": "gpu-test"}],
        ],
    )

    def pins(groups):
        result = translate_uv(_project(name = "app"), lock, _lock_model(projects = ["app"], dependency_groups = groups))
        return [vs.get("repo_pin", "") for vs in result["variants"]]

    # cpu and gpu are both requested: the second set must not pin cpu either.
    env.expect.that_collection(pins(["default", "optional:cpu", "optional:gpu"])).contains_exactly(["", ""]).in_order()
    env.expect.that_collection(pins(["default", "optional:cpu"])).contains_exactly(["extra_app_cpu", "extra_app_cpu"]).in_order()

    # Each set records what the repo requests from it.
    result = translate_uv(_project(name = "app"), lock, _lock_model(projects = ["app"], dependency_groups = ["default", "optional:gpu"]))
    env.expect.that_collection([vs.get("repo_requested", []) for vs in result["variants"]]).contains_exactly([["extra_app_gpu"], []]).in_order()
    env.expect.that_collection(pins(["default", "optional:gpu", "group:gpu-test"])).contains_exactly(["extra_app_gpu", "group_app_gpu-test"]).in_order()

    # Nor does it get a default there: with `default-groups = ["cpu"]` and both
    # `cpu` and `gpu` requested, only the first set defaults to `cpu`.
    lock = _lock(
        [
            dict(
                _pkg("app", "0.1.0", source = {"editable": "."}),
                **{"dev-dependencies": {"cpu": [_dep("six", "1.16.0")], "gpu": [_dep("six", "1.17.0")], "gpu-test": [_dep("six", "1.17.0")]}}
            ),
            _pkg("six", "1.16.0", wheels = [_whl("six-1.16.0-py2.py3-none-any.whl", "aa")]),
            _pkg("six", "1.17.0", wheels = [_whl("six-1.17.0-py2.py3-none-any.whl", "bb")]),
        ],
        conflicts = [
            [{"package": "app", "group": "cpu"}, {"package": "app", "group": "gpu"}],
            [{"package": "app", "group": "cpu"}, {"package": "app", "group": "gpu-test"}],
        ],
    )
    app = {"project": {"name": "app"}, "tool": {"uv": {"default-groups": ["cpu"]}}}
    result = translate_uv(app, lock, _lock_model(projects = ["app"], dependency_groups = ["group:cpu", "group:gpu"]))
    env.expect.that_collection([vs.get("repo_default", "") for vs in result["variants"]]).contains_exactly(["group_app_cpu", ""]).in_order()
    env.expect.that_collection([vs.get("repo_pin", "") for vs in result["variants"]]).contains_exactly(["", ""]).in_order()

def _test_uv_auto_pin_overlapping_sets(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_auto_pin_overlapping_sets_impl)

def _test_uv_auto_pin(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_auto_pin_impl)

# buildifier: disable=unused-variable
def _test_read_project_dict_impl(env, target):
    """A single-project repo reads its member's pyproject.toml; others read the root's."""
    root = Label("//:pyproject.toml")
    member = Label("//:apps/a/pyproject.toml")
    files = {
        str(root): 'project = { name = "monorepo" }',
        str(member): 'project = { name = "App_A" }',
    }
    rctx = struct(
        path = lambda label: struct(exists = str(label) in files, label = str(label)),
        read = lambda path: files[path.label],
    )

    def project_name(projects):
        p = read_project_dict_for_testing(rctx, [root, member], Label("//:uv.lock"), _lock_model(projects = projects))
        return p["project"]["name"]

    env.expect.that_str(project_name(["app-a"])).equals("App_A")
    env.expect.that_str(project_name(["*"])).equals("monorepo")
    env.expect.that_str(project_name(["app-a", "app-b"])).equals("monorepo")
    env.expect.that_str(project_name(["app-b"])).equals("monorepo")

def _test_read_project_dict(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_read_project_dict_impl)

# buildifier: disable=unused-variable
def _test_uv_repo_defaults_impl(env, target):
    """With several items of a set requested, the selected project's default-groups pick one."""
    lock = _lock(
        [
            dict(
                _pkg("app", "0.1.0", source = {"editable": "."}),
                **{"dev-dependencies": {"cpu": [_dep("six", "1.16.0")], "gpu": [_dep("six", "1.17.0")]}}
            ),
            _pkg("six", "1.16.0", wheels = [_whl("six-1.16.0-py2.py3-none-any.whl", "aa")]),
            _pkg("six", "1.17.0", wheels = [_whl("six-1.17.0-py2.py3-none-any.whl", "bb")]),
        ],
        conflicts = [[{"package": "app", "group": "cpu"}, {"package": "app", "group": "gpu"}]],
    )
    both = _lock_model(projects = ["app"], dependency_groups = ["group:cpu", "group:gpu"])

    app = {"project": {"name": "app"}, "tool": {"uv": {"default-groups": ["cpu"]}}}
    result = translate_uv(app, lock, both)
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("")
    env.expect.that_str(result["variants"][0].get("repo_default", "")).equals("group_app_cpu")

    # `default-groups = "all"` names both groups, so neither is the default.
    app_all = {"project": {"name": "app"}, "tool": {"uv": {"default-groups": "all"}}}
    result = translate_uv(app_all, lock, both)
    env.expect.that_str(result["variants"][0].get("repo_default", "")).equals("")

    # A repo spanning all members uses the root pyproject, as `uv sync
    # --all-packages` does, and its default-groups don't name members' groups.
    root = {"project": {"name": "monorepo"}, "tool": {"uv": {"default-groups": ["test"]}}}
    result = translate_uv(root, _member_group_conflict_lock(), _lock_model(dependency_groups = ["group:test"]))
    env.expect.that_str(result["variants"][0].get("repo_default", "")).equals("")

def _test_uv_repo_defaults(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_repo_defaults_impl)

# buildifier: disable=unused-variable
def _test_uv_project_conflicts_impl(env, target):
    """`{package = ...}` conflicts gate each project's deps; single-project repos pin their project."""
    lock = _lock(
        [
            _pkg("a", "0", source = {"virtual": "a"}, deps = [_dep("iniconfig", "1.1.1", marker = "extra == 'project-1-a'")]),
            _pkg("b", "0", source = {"virtual": "b"}, deps = [_dep("iniconfig", "2.0.0", marker = "extra == 'project-1-b'")]),
            _pkg("iniconfig", "1.1.1", wheels = [_whl("iniconfig-1.1.1-py2.py3-none-any.whl", "aaa")]),
            _pkg("iniconfig", "2.0.0", wheels = [_whl("iniconfig-2.0.0-py3-none-any.whl", "bbb")]),
        ],
        conflicts = [[{"package": "a"}, {"package": "b"}]],
    )

    # A repo with both projects pins each project's version under its variant, and
    # has to select one with a flag (no repo pin).
    result = translate_uv(_project(name = "root"), lock, _lock_model())
    env.expect.that_dict(result["pins"]["iniconfig"]).contains_exactly({
        "package_a": "iniconfig@1.1.1",
        "package_b": "iniconfig@2.0.0",
    })
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("")

    # A repo with one project pins that project's variant.
    result = translate_uv(_project(name = "a"), lock, _lock_model(projects = ["a"]))
    env.expect.that_dict(result["pins"]["iniconfig"]).contains_exactly({"package_a": "iniconfig@1.1.1"})
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("package_a")

# buildifier: disable=unused-variable
def _test_uv_project_conflict_mixed_set_impl(env, target):
    """A `{package}` item conflicting with another project's group: pin only when the repo owns just the project."""
    lock = _lock(
        [
            _pkg("a", "0", source = {"virtual": "a"}, deps = [_dep("iniconfig", "1.1.1")]),
            dict(_pkg("b", "0", source = {"virtual": "b"}, deps = [_dep("six", "1.17.0")]), **{"dev-dependencies": {"g": [_dep("iniconfig", "2.0.0")]}}),
            _pkg("iniconfig", "1.1.1", wheels = [_whl("iniconfig-1.1.1-py2.py3-none-any.whl", "aaa")]),
            _pkg("iniconfig", "2.0.0", wheels = [_whl("iniconfig-2.0.0-py3-none-any.whl", "bbb")]),
            _pkg("six", "1.17.0", wheels = [_whl("six-1.17.0-py2.py3-none-any.whl", "ccc")]),
        ],
        conflicts = [[{"package": "a"}, {"package": "b", "group": "g"}]],
    )

    # Spanning both: no pin (a `group_g` flag must still work), but `a` is the default.
    result = translate_uv(_project(name = "root"), lock, _lock_model(dependency_groups = ["default", "group:g"]))
    vs = result["variants"][0]
    env.expect.that_str(vs.get("repo_pin", "")).equals("")
    env.expect.that_str(vs.get("repo_default", "")).equals("package_a")

    # Only `a`: pinned.
    result = translate_uv(_project(name = "a"), lock, _lock_model(projects = ["a"]))
    env.expect.that_str(result["variants"][0].get("repo_pin", "")).equals("package_a")

# buildifier: disable=unused-variable
def _test_uv_project_conflict_edge_split_impl(env, target):
    """A conflicted project's group drops unsatisfiable rival branches, while satisfiable split edges get marker-hashed constraints."""
    lock = _lock(
        [
            dict(
                _pkg("a", "0", source = {"virtual": "a"}, deps = [_dep("iniconfig", "1.1.1", marker = "extra == 'project-1-a'")]),
                **{"dev-dependencies": {"plain": [
                    _dep("iniconfig", "1.1.1", marker = "extra == 'project-1-a'"),
                    _dep("iniconfig", "2.0.0", marker = "extra == 'project-1-b' or extra != 'project-1-a'"),
                ]}}
            ),
            _pkg("b", "0", source = {"virtual": "b"}, deps = [_dep("iniconfig", "2.0.0", marker = "extra == 'project-1-b'")]),
            dict(
                _pkg("c", "0", source = {"virtual": "c"}, deps = [
                    _dep("iniconfig", "1.1.1", marker = "extra == 'project-1-a'"),
                    _dep("iniconfig", "2.0.0", marker = "extra == 'project-1-b' or extra != 'project-1-a'"),
                ]),
                **{"dev-dependencies": {"linux_only": [
                    _dep("iniconfig", "1.1.1", marker = "extra == 'project-1-a' and sys_platform == 'linux'"),
                    _dep("iniconfig", "2.0.0", marker = "(extra == 'project-1-b' or extra != 'project-1-a') and sys_platform == 'linux'"),
                ]}}
            ),
            _pkg("iniconfig", "1.1.1", wheels = [_whl("iniconfig-1.1.1-py2.py3-none-any.whl", "aaa")]),
            _pkg("iniconfig", "2.0.0", wheels = [_whl("iniconfig-2.0.0-py3-none-any.whl", "bbb")]),
        ],
        conflicts = [[{"package": "a"}, {"package": "b"}]],
    )

    # Under project `a`, the `2.0.0` branch (`package_b or != package_a`) is
    # unsatisfiable and pruned, so `package_a` maps cleanly to `1.1.1`.
    result = translate_uv(_project(name = "a"), lock, _lock_model(projects = ["a"], dependency_groups = ["default", "group:plain"]))
    env.expect.that_dict(result["pins"]["iniconfig"]).contains_exactly({"package_a": "iniconfig@1.1.1"})
    env.expect.that_bool("resolution_marker_exprs" in result).equals(False)

    # Under unconflicted project `c`, both versions are satisfiable and get
    # distinct marker-hashed constraints; adding `group:linux_only` ORs in a
    # second marker and produces a distinct hash so repos never collide on merge.
    c_default = translate_uv(_project(name = "c"), lock, _lock_model(projects = ["c"], dependency_groups = ["default"]))
    c_by_ver = {v: k for k, v in c_default["pins"]["iniconfig"].items()}
    env.expect.that_collection(c_by_ver.keys()).contains_exactly(["iniconfig@1.1.1", "iniconfig@2.0.0"])
    c_exprs = c_default["resolution_marker_exprs"]
    env.expect.that_str(c_exprs[c_by_ver["iniconfig@1.1.1"]]).equals("extra == '__variant_package_a'")
    env.expect.that_str(c_exprs[c_by_ver["iniconfig@2.0.0"]]).equals("extra == '__variant_package_b' or extra != '__variant_package_a'")

    c_wider = translate_uv(_project(name = "c"), lock, _lock_model(projects = ["c"], dependency_groups = ["default", "group:linux_only"]))
    wider_key = {v: k for k, v in c_wider["pins"]["iniconfig"].items()}["iniconfig@1.1.1"]
    env.expect.that_bool(wider_key != c_by_ver["iniconfig@1.1.1"]).equals(True)

# buildifier: disable=unused-variable
def _test_uv_project_conflict_redundant_edges_impl(env, target):
    """An unconflicted member's split edge is kept on its own, dropped next to the set's variants."""
    lock = _lock(
        [
            _pkg("a", "0", source = {"virtual": "a"}, deps = [_dep("iniconfig", "1.1.1", marker = "extra == 'project-1-a'")]),
            _pkg("b", "0", source = {"virtual": "b"}, deps = [_dep("iniconfig", "2.0.0", marker = "extra == 'project-1-b'")]),
            _pkg("c", "0", source = {"virtual": "c"}, deps = [
                _dep("iniconfig", "1.1.1", marker = "extra == 'project-1-a'"),
                _dep("iniconfig", "2.0.0", marker = "extra == 'project-1-b' or extra != 'project-1-a'"),
            ]),
            _pkg("iniconfig", "1.1.1", wheels = [_whl("iniconfig-1.1.1-py2.py3-none-any.whl", "aaa")]),
            _pkg("iniconfig", "2.0.0", wheels = [_whl("iniconfig-2.0.0-py3-none-any.whl", "bbb")]),
        ],
        conflicts = [[{"package": "a"}, {"package": "b"}]],
    )

    # Only `c`: its split edges are the pin (valid with no variant selected).
    result = translate_uv(_project(name = "c"), lock, _lock_model(projects = ["c"]))
    env.expect.that_collection(result["pins"]["iniconfig"].values()).contains_exactly(["iniconfig@1.1.1", "iniconfig@2.0.0"])
    env.expect.that_collection(result["pins"]["iniconfig"].keys()).not_contains("package_a")

    # All members: the variant entries cover it, so unselected is a clean error.
    result = translate_uv(_project(name = "root"), lock, _lock_model())
    env.expect.that_dict(result["pins"]["iniconfig"]).contains_exactly({
        "package_a": "iniconfig@1.1.1",
        "package_b": "iniconfig@2.0.0",
    })

# buildifier: disable=unused-variable
def _test_uv_project_conflict_asymmetric_edges_impl(env, target):
    """When only some items of the set depend on the package, the edge entry is narrowed, not dropped."""
    lock = _lock(
        [
            _pkg("a", "0", source = {"virtual": "a"}, deps = [_dep("iniconfig", "1.1.1", marker = "extra == 'project-1-a'")]),
            _pkg("b", "0", source = {"virtual": "b"}),
            _pkg("c", "0", source = {"virtual": "c"}, deps = [
                _dep("iniconfig", "1.1.1", marker = "extra == 'project-1-a'"),
                _dep("iniconfig", "2.3.1", marker = "extra == 'project-1-b' or extra != 'project-1-a'"),
            ]),
            _pkg("iniconfig", "1.1.1", wheels = [_whl("iniconfig-1.1.1-py2.py3-none-any.whl", "aaa")]),
            _pkg("iniconfig", "2.3.1", wheels = [_whl("iniconfig-2.3.1-py3-none-any.whl", "bbb")]),
        ],
        conflicts = [[{"package": "a"}, {"package": "b"}]],
    )
    result = translate_uv(_project(name = "root"), lock, _lock_model())
    pin = result["pins"]["iniconfig"]
    exprs = result["resolution_marker_exprs"]
    env.expect.that_str(pin["package_a"]).equals("iniconfig@1.1.1")

    # `b` has no entry, so c's 2.3.1 edge stays, guarded only on the uncovered item `b`
    # so it never collides with `package_a`.
    narrowed = [k for k, v in pin.items() if v == "iniconfig@2.3.1"]
    env.expect.that_collection(narrowed).has_size(1)
    env.expect.that_str(exprs[narrowed[0]]).equals(
        "(extra == '__variant_package_b') and (extra == '__variant_package_b' or extra != '__variant_package_a')",
    )

    # Double-quoted conflict markers are also detected and narrowed cleanly.
    lock_dq = _lock(
        [
            _pkg("a", "0", source = {"virtual": "a"}, deps = [_dep("iniconfig", "1.1.1", marker = 'extra == "project-1-a"')]),
            _pkg("b", "0", source = {"virtual": "b"}),
            _pkg("c", "0", source = {"virtual": "c"}, deps = [
                _dep("iniconfig", "1.1.1", marker = 'extra == "project-1-a"'),
                _dep("iniconfig", "2.3.1", marker = 'extra != "project-1-a"'),
            ]),
            _pkg("iniconfig", "1.1.1", wheels = [_whl("iniconfig-1.1.1-py2.py3-none-any.whl", "aaa")]),
            _pkg("iniconfig", "2.3.1", wheels = [_whl("iniconfig-2.3.1-py3-none-any.whl", "bbb")]),
        ],
        conflicts = [[{"package": "a"}, {"package": "b"}]],
    )
    result_dq = translate_uv(_project(name = "root"), lock_dq, _lock_model())
    narrowed_dq = [k for k, v in result_dq["pins"]["iniconfig"].items() if v == "iniconfig@2.3.1"]
    env.expect.that_collection(narrowed_dq).has_size(1)
    env.expect.that_str(result_dq["resolution_marker_exprs"][narrowed_dq[0]]).contains("(extra == '__variant_package_b') and ")
    edges_111 = [k for k, v in result_dq["pins"]["iniconfig"].items() if v == "iniconfig@1.1.1" and k != "package_a"]
    for edge_key in edges_111:
        env.expect.that_str(result_dq["resolution_marker_exprs"][edge_key]).contains("(extra == '__variant_package_b') and ")

def _test_uv_project_conflict_asymmetric_edges(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_project_conflict_asymmetric_edges_impl)

def _test_uv_project_conflict_redundant_edges(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_project_conflict_redundant_edges_impl)

def _test_uv_project_conflict_mixed_set(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_project_conflict_mixed_set_impl)

def _test_uv_project_conflict_edge_split(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_project_conflict_edge_split_impl)

def _test_uv_project_conflicts(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_project_conflicts_impl)

def _test_uv_same_named_groups_across_members(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_same_named_groups_across_members_impl)

# --- test_local_version_exact_matching ---

# buildifier: disable=unused-variable
def _test_uv_local_version_exact_matching_impl(env, target):
    """Exact locked versions (===) distinguish 2.12.0 from 2.12.0+cpu in pins, deps, and extra self-deps."""
    project = _project(
        opt_deps = {
            "cpu": ["torch==2.12.0+cpu"],
            "cuda": ["torch[opt]==2.12.0"],
        },
        uv_conflicts = [[{"package": "my-app", "extra": "cpu"}, {"package": "my-app", "extra": "cuda"}]],
    )
    lock = _lock(
        [
            _vpkg(
                "my-app",
                deps = [_dep("helper", "1.0.0")],
                opt_deps = {
                    "cpu": [_dep("torch", "2.12.0+cpu")],
                    "cuda": [
                        _dep("torch", "2.12.0"),
                        _dep("torch", "2.12.0", extra = ["opt"]),
                    ],
                },
            ),
            _pkg(
                "helper",
                "1.0.0",
                wheels = [_whl("helper-1.0.0-py3-none-any.whl", "h1")],
                deps = [_dep("torch", "2.12.0")],
            ),
            _pkg(
                "helper",
                "1.0.0+local",
                wheels = [_whl("helper-1.0.0%2Blocal-py3-none-any.whl", "h2")],
            ),
            _pkg(
                "torch",
                "2.12.0",
                wheels = [_whl("torch-2.12.0-cp312-cp312-linux_x86_64.whl", "t1")],
                opt_deps = {"opt": []},
            ),
            _pkg(
                "torch",
                "2.12.0+cpu",
                wheels = [_whl("torch-2.12.0%2Bcpu-cp312-cp312-linux_x86_64.whl", "t2")],
                opt_deps = {"opt": []},
            ),
        ],
        conflicts = [[{"package": "my-app", "extra": "cpu"}, {"package": "my-app", "extra": "cuda"}]],
    )
    result = translate_uv(project, lock, _lock_model(dependency_groups = ["default", "optional:*"]))

    # Root pins: 2.12.0 -> torch@2.12.0 (not +cpu), 2.12.0+cpu -> torch@2.12.0+cpu
    env.expect.that_str(result["pins"]["helper"]).equals("helper@1.0.0")
    env.expect.that_str(result["pins"]["torch"]["extra_my-app_cuda"]).equals("torch@2.12.0")
    env.expect.that_str(result["pins"]["torch"]["extra_my-app_cpu"]).equals("torch@2.12.0+cpu")
    env.expect.that_str(result["pins"]["torch[opt]"]["extra_my-app_cuda"]).equals("torch[opt]@2.12.0")

    # Package dependency edge with explicit version 2.12.0 resolves to 2.12.0 (not 2.12.0+cpu)
    helper_deps = result["packages"]["helper@1.0.0"]["dependencies"]
    env.expect.that_int(len(helper_deps)).equals(1)
    env.expect.that_str(helper_deps[0]["name"]).equals("torch")
    env.expect.that_str(helper_deps[0]["version"]).equals("2.12.0")

    # Self-dependency of torch[opt]@2.12.0 resolves to 2.12.0 (not 2.12.0+cpu)
    torch_opt_deps = result["packages"]["torch[opt]@2.12.0"]["dependencies"]
    env.expect.that_int(len(torch_opt_deps)).equals(1)
    env.expect.that_str(torch_opt_deps[0]["name"]).equals("torch")
    env.expect.that_str(torch_opt_deps[0]["version"]).equals("2.12.0")

def _test_uv_local_version_exact_matching(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_local_version_exact_matching_impl)

# --- test_issue_1510_verbatim_lock ---

_ISSUE_1510_PYPROJECT_TOML = """\
[project]
name = "native-torch-probe"
version = "0.0.0"
requires-python = ">=3.12,<3.13"

[dependency-groups]
cpu = ["torch==2.12.0"]
cuda = ["torch==2.12.0; sys_platform == 'linux'"]

[tool.uv]
package = false
environments = [
    "sys_platform == 'linux' and platform_machine == 'x86_64'",
    "sys_platform == 'darwin' and platform_machine == 'arm64'",
]
conflicts = [[{group = "cpu"}, {group = "cuda"}]]

[tool.uv.sources]
torch = [{index = "pytorch-cpu", group = "cpu", marker = "sys_platform == 'linux'"}]

[[tool.uv.index]]
name = "pytorch-cpu"
url = "https://download.pytorch.org/whl/cpu"
explicit = true
"""

_ISSUE_1510_UV_LOCK = """\
version = 1
revision = 3
requires-python = "==3.12.*"
resolution-markers = [
    "platform_machine == 'x86_64' and sys_platform == 'linux'",
    "platform_machine == 'arm64' and sys_platform == 'darwin'",
]
supported-markers = [
    "platform_machine == 'x86_64' and sys_platform == 'linux'",
    "platform_machine == 'arm64' and sys_platform == 'darwin'",
]
conflicts = [[
    { package = "native-torch-probe", group = "cpu" },
    { package = "native-torch-probe", group = "cuda" },
]]

[[package]]
name = "cuda-bindings"
version = "13.3.1"
source = { registry = "https://pypi.org/simple" }
dependencies = [
    { name = "cuda-pathfinder", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
wheels = [
    { url = "https://files.pythonhosted.org/packages/39/2a/6d2e9047d1fb243dbaa364b01e0297534b9ed7fd27dba1c9f361519cf69b/cuda_bindings-13.3.1-cp312-cp312-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl", hash = "sha256:e32d08f71ebcdf00f0f41eab2eb37e8da94c8ed411cc9f7f7a019ce6b34abe3a", size = 6657965, upload-time = "2026-05-29T23:11:52.227Z" },
]

[[package]]
name = "cuda-pathfinder"
version = "1.8.0"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/a1/b1/ef21259ec74fe0b265ed201379de1d0ef7c14178313ee03705952f1b7093/cuda_pathfinder-1.8.0-py3-none-any.whl", hash = "sha256:c44e574dc997fae2814721d1ae97d0fd6db76db82decbe9b753bf75de53f515e", size = 62539, upload-time = "2026-08-27T21:33:03.229Z" },
]

[[package]]
name = "cuda-toolkit"
version = "13.0.2"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/57/b2/453099f5f3b698d7d0eab38916aac44c7f76229f451709e2eb9db6615dcd/cuda_toolkit-13.0.2-py2.py3-none-any.whl", hash = "sha256:b198824cf2f54003f50d64ada3a0f184b42ca0846c1c94192fa269ecd97a66eb", size = 2364, upload-time = "2025-12-19T23:24:07.328Z" },
]

[package.optional-dependencies]
cudart = [
    { name = "nvidia-cuda-runtime", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
cufft = [
    { name = "nvidia-cufft", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
cufile = [
    { name = "nvidia-cufile", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
cupti = [
    { name = "nvidia-cuda-cupti", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
curand = [
    { name = "nvidia-curand", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
cusolver = [
    { name = "nvidia-cusolver", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
cusparse = [
    { name = "nvidia-cusparse", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
nvjitlink = [
    { name = "nvidia-nvjitlink", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
nvrtc = [
    { name = "nvidia-cuda-nvrtc", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
nvtx = [
    { name = "nvidia-nvtx", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]

[[package]]
name = "filelock"
version = "3.32.4"
source = { registry = "https://pypi.org/simple" }
sdist = { url = "https://files.pythonhosted.org/packages/6d/30/03b03951873a1a0ffc7e8ca0e10c15597b59e8d0e39260704cd2ea087bc4/filelock-3.32.4.tar.gz", hash = "sha256:2bde2e4cf732e0153406d8a7bc80620ecf5e621fe0d25e41143c4e3b4733ff30", size = 222126, upload-time = "2026-08-23T17:37:55.363Z" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/01/a4/9b63d595d748e3aff8812b65eacc1a2c4bd90b7c2012e08e72373b4835eb/filelock-3.32.4-py3-none-any.whl", hash = "sha256:22e58ca3b1ae3b98993b762d7338367ae64fe50252bf78d59da3bfebcdf1cedd", size = 99864, upload-time = "2026-08-23T17:37:53.913Z" },
]

[[package]]
name = "fsspec"
version = "2026.7.0"
source = { registry = "https://pypi.org/simple" }
sdist = { url = "https://files.pythonhosted.org/packages/00/78/f34251dadb8f3921264a1d9b8946f5e542014ee2614b285261b4e40e6775/fsspec-2026.7.0.tar.gz", hash = "sha256:c803c40f4cf860b49dea58ee3e1c33cb9c790520e233537e1340049f89b82a88", size = 317040, upload-time = "2026-07-28T16:34:51.052Z" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/fd/3c/6a2bf344106328fd04963664a60b9bb6496fc25df8e962fcdc1367285fb9/fsspec-2026.7.0-py3-none-any.whl", hash = "sha256:b57ddbafedfaef7018c1ecab32aa200a9d7ca26b77965f64e48b70061249d279", size = 206583, upload-time = "2026-07-28T16:34:49.538Z" },
]

[[package]]
name = "jinja2"
version = "3.1.6"
source = { registry = "https://pypi.org/simple" }
dependencies = [
    { name = "markupsafe", marker = "(platform_machine == 'arm64' and sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'darwin' and sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
sdist = { url = "https://files.pythonhosted.org/packages/df/bf/f7da0350254c0ed7c72f3e33cef02e048281fec7ecec5f032d4aac52226b/jinja2-3.1.6.tar.gz", hash = "sha256:0137fb05990d35f1275a587e9aee6d56da821fc83491a0fb838183be43f66d6d", size = 245115, upload-time = "2025-03-05T20:05:02.478Z" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/62/a1/3d680cbfd5f4b8f15abc1d571870c5fc3e594bb582bc3b64ea099db13e56/jinja2-3.1.6-py3-none-any.whl", hash = "sha256:85ece4451f492d0c13c5dd7c13a64681a86afae63a5f347908daf103ce6d2f67", size = 134899, upload-time = "2025-03-05T20:05:00.369Z" },
]

[[package]]
name = "markupsafe"
version = "3.0.3"
source = { registry = "https://pypi.org/simple" }
sdist = { url = "https://files.pythonhosted.org/packages/7e/99/7690b6d4034fffd95959cbe0c02de8deb3098cc577c67bb6a24fe5d7caa7/markupsafe-3.0.3.tar.gz", hash = "sha256:722695808f4b6457b320fdc131280796bdceb04ab50fe1795cd540799ebe1698", size = 80313, upload-time = "2025-09-27T18:37:40.426Z" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/9a/81/7e4e08678a1f98521201c3079f77db69fb552acd56067661f8c2f534a718/markupsafe-3.0.3-cp312-cp312-macosx_11_0_arm64.whl", hash = "sha256:1872df69a4de6aead3491198eaf13810b565bdbeec3ae2dc8780f14458ec73ce", size = 12020, upload-time = "2025-09-27T18:36:31.971Z" },
    { url = "https://files.pythonhosted.org/packages/3c/2e/8d0c2ab90a8c1d9a24f0399058ab8519a3279d1bd4289511d74e909f060e/markupsafe-3.0.3-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl", hash = "sha256:d6dd0be5b5b189d31db7cda48b91d7e0a9795f31430b7f271219ab30f1d3ac9d", size = 22947, upload-time = "2025-09-27T18:36:33.86Z" },
    { url = "https://files.pythonhosted.org/packages/89/e0/4486f11e51bbba8b0c041098859e869e304d1c261e59244baa3d295d47b7/markupsafe-3.0.3-cp312-cp312-musllinux_1_2_x86_64.whl", hash = "sha256:77f0643abe7495da77fb436f50f8dab76dbc6e5fd25d39589a0f1fe6548bfa2b", size = 23015, upload-time = "2025-09-27T18:36:37.868Z" },
]

[[package]]
name = "mpmath"
version = "1.3.0"
source = { registry = "https://pypi.org/simple" }
sdist = { url = "https://files.pythonhosted.org/packages/e0/47/dd32fa426cc72114383ac549964eecb20ecfd886d1e5ccf5340b55b02f57/mpmath-1.3.0.tar.gz", hash = "sha256:7a28eb2a9774d00c7bc92411c19a89209d5da7c4c9a9e227be8330a23a25b91f", size = 508106, upload-time = "2023-03-07T16:47:11.061Z" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/43/e3/7d92a15f894aa0c9c4b49b8ee9ac9850d6e63b03c9c32c0367a13ae62209/mpmath-1.3.0-py3-none-any.whl", hash = "sha256:a0b2b9fe80bbcd81a6647ff13108738cfb482d481d826cc0e02f5b35e5c88d2c", size = 536198, upload-time = "2023-03-07T16:47:09.197Z" },
]

[[package]]
name = "native-torch-probe"
version = "0.0.0"
source = { virtual = "." }

[package.dev-dependencies]
cpu = [
    { name = "torch", version = "2.12.0", source = { registry = "https://pypi.org/simple" }, marker = "(platform_machine == 'arm64' and sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine != 'arm64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'darwin' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "torch", version = "2.12.0+cpu", source = { registry = "https://download.pytorch.org/whl/cpu" }, marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
cuda = [
    { name = "torch", version = "2.12.0", source = { registry = "https://pypi.org/simple" }, marker = "platform_machine == 'x86_64' and sys_platform == 'linux'" },
]

[package.metadata]

[package.metadata.requires-dev]
cpu = [
    { name = "torch", marker = "sys_platform != 'linux'", specifier = "==2.12.0" },
    { name = "torch", marker = "sys_platform == 'linux'", specifier = "==2.12.0", index = "https://download.pytorch.org/whl/cpu", conflict = { package = "native-torch-probe", group = "cpu" } },
]
cuda = [{ name = "torch", marker = "sys_platform == 'linux'", specifier = "==2.12.0" }]

[[package]]
name = "networkx"
version = "3.6.1"
source = { registry = "https://pypi.org/simple" }
sdist = { url = "https://files.pythonhosted.org/packages/6a/51/63fe664f3908c97be9d2e4f1158eb633317598cfa6e1fc14af5383f17512/networkx-3.6.1.tar.gz", hash = "sha256:26b7c357accc0c8cde558ad486283728b65b6a95d85ee1cd66bafab4c8168509", size = 2517025, upload-time = "2025-12-08T17:02:39.908Z" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/9e/c9/b2622292ea83fbb4ec318f5b9ab867d0a28ab43c5717bb85b0a5f6b3b0a4/networkx-3.6.1-py3-none-any.whl", hash = "sha256:d47fbf302e7d9cbbb9e2555a0d267983d2aa476bac30e90dfbe5669bd57f3762", size = 2068504, upload-time = "2025-12-08T17:02:38.159Z" },
]

[[package]]
name = "nvidia-cublas"
version = "13.1.1.3"
source = { registry = "https://pypi.org/simple" }
dependencies = [
    { name = "nvidia-cuda-nvrtc", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
wheels = [
    { url = "https://files.pythonhosted.org/packages/3b/cd/154ca20c38269e05eff77c1464e6c1da89f50a6390b565e9d82e06bc11e1/nvidia_cublas-13.1.1.3-py3-none-manylinux_2_27_x86_64.whl", hash = "sha256:37936a16db8fe4ac1f065c2139360608a543a09275cb1a1af612e08cfa065436", size = 423138758, upload-time = "2026-04-08T18:46:58.655Z" },
]

[[package]]
name = "nvidia-cuda-cupti"
version = "13.0.85"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/33/6d/737d164b4837a9bbd202f5ae3078975f0525a55730fe871d8ed4e3b952b0/nvidia_cuda_cupti-13.0.85-py3-none-manylinux_2_25_x86_64.whl", hash = "sha256:4eb01c08e859bf924d222250d2e8f8b8ff6d3db4721288cf35d14252a4d933c8", size = 10715597, upload-time = "2025-09-04T08:26:51.312Z" },
]

[[package]]
name = "nvidia-cuda-nvrtc"
version = "13.0.88"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/c3/68/483a78f5e8f31b08fb1bb671559968c0ca3a065ac7acabfc7cee55214fd6/nvidia_cuda_nvrtc-13.0.88-py3-none-manylinux2010_x86_64.manylinux_2_12_x86_64.whl", hash = "sha256:ad9b6d2ead2435f11cbb6868809d2adeeee302e9bb94bcf0539c7a40d80e8575", size = 90215200, upload-time = "2025-09-04T08:28:44.204Z" },
]

[[package]]
name = "nvidia-cuda-runtime"
version = "13.0.96"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/2e/24/d1558f3b68b1d26e706813b1d10aa1d785e4698c425af8db8edc3dced472/nvidia_cuda_runtime-13.0.96-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl", hash = "sha256:7f82250d7782aa23b6cfe765ecc7db554bd3c2870c43f3d1821f1d18aebf0548", size = 2243632, upload-time = "2025-10-09T08:55:36.117Z" },
]

[[package]]
name = "nvidia-cudnn-cu13"
version = "9.20.0.48"
source = { registry = "https://pypi.org/simple" }
dependencies = [
    { name = "nvidia-cublas", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
wheels = [
    { url = "https://files.pythonhosted.org/packages/6e/5e/edb9c0ae051602c3ccaffe424256463636d639e27d7f302dde9975ef9e7a/nvidia_cudnn_cu13-9.20.0.48-py3-none-manylinux_2_27_x86_64.whl", hash = "sha256:0c45dd8eeb50b603f07995b1b300c62ffe6a1980482b82b3bcf94a4ca9d49304", size = 366173588, upload-time = "2026-03-09T19:29:34.474Z" },
]

[[package]]
name = "nvidia-cufft"
version = "12.0.0.61"
source = { registry = "https://pypi.org/simple" }
dependencies = [
    { name = "nvidia-nvjitlink", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
wheels = [
    { url = "https://files.pythonhosted.org/packages/a8/2f/7b57e29836ea8714f81e9898409196f47d772d5ddedddf1592eadb8ab743/nvidia_cufft-12.0.0.61-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl", hash = "sha256:6c44f692dce8fd5ffd3e3df134b6cdb9c2f72d99cf40b62c32dde45eea9ddad3", size = 214085489, upload-time = "2025-09-04T08:31:56.044Z" },
]

[[package]]
name = "nvidia-cufile"
version = "1.15.1.6"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/3f/70/4f193de89a48b71714e74602ee14d04e4019ad36a5a9f20c425776e72cd6/nvidia_cufile-1.15.1.6-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl", hash = "sha256:08a3ecefae5a01c7f5117351c64f17c7c62efa5fffdbe24fc7d298da19cd0b44", size = 1223672, upload-time = "2025-09-04T08:32:22.779Z" },
]

[[package]]
name = "nvidia-curand"
version = "10.4.0.35"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/a5/9f/be0a41ca4a4917abf5cb9ae0daff1a6060cc5de950aec0396de9f3b52bc5/nvidia_curand-10.4.0.35-py3-none-manylinux_2_27_x86_64.whl", hash = "sha256:1aee33a5da6e1db083fe2b90082def8915f30f3248d5896bcec36a579d941bfc", size = 59544258, upload-time = "2025-08-04T10:22:03.992Z" },
]

[[package]]
name = "nvidia-cusolver"
version = "12.0.4.66"
source = { registry = "https://pypi.org/simple" }
dependencies = [
    { name = "nvidia-cublas", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "nvidia-cusparse", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "nvidia-nvjitlink", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
wheels = [
    { url = "https://files.pythonhosted.org/packages/5f/67/cba3777620cdacb99102da4042883709c41c709f4b6323c10781a9c3aa34/nvidia_cusolver-12.0.4.66-py3-none-manylinux_2_27_x86_64.whl", hash = "sha256:0a759da5dea5c0ea10fd307de75cdeb59e7ea4fcb8add0924859b944babf1112", size = 200941980, upload-time = "2025-09-04T08:33:22.767Z" },
]

[[package]]
name = "nvidia-cusparse"
version = "12.6.3.3"
source = { registry = "https://pypi.org/simple" }
dependencies = [
    { name = "nvidia-nvjitlink", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
wheels = [
    { url = "https://files.pythonhosted.org/packages/fa/18/623c77619c31d62efd55302939756966f3ecc8d724a14dab2b75f1508850/nvidia_cusparse-12.6.3.3-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl", hash = "sha256:2b3c89c88d01ee0e477cb7f82ef60a11a4bcd57b6b87c33f789350b59759360b", size = 145942937, upload-time = "2025-09-04T08:33:58.029Z" },
]

[[package]]
name = "nvidia-cusparselt-cu13"
version = "0.8.1"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/34/7d/2661f2fb3ac4302f3a246f5fc030213ac60c1fe0bce84f9783dbd831dbb7/nvidia_cusparselt_cu13-0.8.1-py3-none-manylinux2014_x86_64.whl", hash = "sha256:786ce87568c303fadb5afcc7102d454cd3040d75f6f8626f5db460d1871f4dd0", size = 170148586, upload-time = "2025-09-05T18:50:50.248Z" },
]

[[package]]
name = "nvidia-nccl-cu13"
version = "2.29.7"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/67/f4/58e4e91b6919367c7aafb8e36fce9aad1a3047e536bf7e2fd560927d3a4c/nvidia_nccl_cu13-2.29.7-py3-none-manylinux_2_18_x86_64.whl", hash = "sha256:edd81538446786ec3b73972543e53bb43bcaf0bfc8ef76cb679fcc390ffe136d", size = 205976000, upload-time = "2026-03-03T05:36:24.472Z" },
]

[[package]]
name = "nvidia-nvjitlink"
version = "13.0.88"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/56/7a/123e033aaff487c77107195fa5a2b8686795ca537935a24efae476c41f05/nvidia_nvjitlink-13.0.88-py3-none-manylinux2010_x86_64.manylinux_2_12_x86_64.whl", hash = "sha256:13a74f429e23b921c1109976abefacc69835f2f433ebd323d3946e11d804e47b", size = 40713933, upload-time = "2025-09-04T08:35:43.553Z" },
]

[[package]]
name = "nvidia-nvshmem-cu13"
version = "3.4.5"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/3c/35/a9bf80a609e74e3b000fef598933235c908fcefcef9026042b8e6dfde2a9/nvidia_nvshmem_cu13-3.4.5-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl", hash = "sha256:290f0a2ee94c9f3687a02502f3b9299a9f9fe826e6d0287ee18482e78d495b80", size = 60412546, upload-time = "2025-09-06T00:32:41.564Z" },
]

[[package]]
name = "nvidia-nvtx"
version = "13.0.85"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/c2/f3/d86c845465a2723ad7e1e5c36dcd75ddb82898b3f53be47ebd429fb2fa5d/nvidia_nvtx-13.0.85-py3-none-manylinux1_x86_64.manylinux_2_5_x86_64.whl", hash = "sha256:4936d1d6780fbe68db454f5e72a42ff64d1fd6397df9f363ae786930fd5c1cd4", size = 148047, upload-time = "2025-09-04T08:29:01.761Z" },
]

[[package]]
name = "setuptools"
version = "81.0.0"
source = { registry = "https://pypi.org/simple" }
sdist = { url = "https://files.pythonhosted.org/packages/0d/1c/73e719955c59b8e424d015ab450f51c0af856ae46ea2da83eba51cc88de1/setuptools-81.0.0.tar.gz", hash = "sha256:487b53915f52501f0a79ccfd0c02c165ffe06631443a886740b91af4b7a5845a", size = 1198299, upload-time = "2026-02-06T21:10:39.601Z" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/e1/e3/c164c88b2e5ce7b24d667b9bd83589cf4f3520d97cad01534cd3c4f55fdb/setuptools-81.0.0-py3-none-any.whl", hash = "sha256:fdd925d5c5d9f62e4b74b30d6dd7828ce236fd6ed998a08d81de62ce5a6310d6", size = 1062021, upload-time = "2026-02-06T21:10:37.175Z" },
]

[[package]]
name = "sympy"
version = "1.14.0"
source = { registry = "https://pypi.org/simple" }
dependencies = [
    { name = "mpmath", marker = "(platform_machine == 'arm64' and sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'darwin' and sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
sdist = { url = "https://files.pythonhosted.org/packages/83/d3/803453b36afefb7c2bb238361cd4ae6125a569b4db67cd9e79846ba2d68c/sympy-1.14.0.tar.gz", hash = "sha256:d3d3fe8df1e5a0b42f0e7bdf50541697dbe7d23746e894990c030e2b05e72517", size = 7793921, upload-time = "2025-04-27T18:05:01.611Z" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/a2/09/77d55d46fd61b4a135c444fc97158ef34a095e5681d0a6c10b75bf356191/sympy-1.14.0-py3-none-any.whl", hash = "sha256:e091cc3e99d2141a0ba2847328f5479b05d94a6635cb96148ccb3f34671bd8f5", size = 6299353, upload-time = "2025-04-27T18:04:59.103Z" },
]

[[package]]
name = "torch"
version = "2.12.0"
source = { registry = "https://pypi.org/simple" }
resolution-markers = [
    "platform_machine == 'x86_64' and sys_platform == 'linux'",
    "platform_machine == 'arm64' and sys_platform == 'darwin'",
]
dependencies = [
    { name = "cuda-bindings", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "cuda-toolkit", extra = ["cudart", "cufft", "cufile", "cupti", "curand", "cusolver", "cusparse", "nvjitlink", "nvrtc", "nvtx"], marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "filelock", marker = "(platform_machine == 'arm64' and sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'darwin' and sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "fsspec", marker = "(platform_machine == 'arm64' and sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'darwin' and sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "jinja2", marker = "(platform_machine == 'arm64' and sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'darwin' and sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "networkx", marker = "(platform_machine == 'arm64' and sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'darwin' and sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "nvidia-cublas", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "nvidia-cudnn-cu13", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "nvidia-cusparselt-cu13", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "nvidia-nccl-cu13", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "nvidia-nvshmem-cu13", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "setuptools", marker = "(platform_machine == 'arm64' and sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'darwin' and sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "sympy", marker = "(platform_machine == 'arm64' and sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'darwin' and sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "triton", marker = "(platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (platform_machine != 'x86_64' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
    { name = "typing-extensions", marker = "(platform_machine == 'arm64' and sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu') or (platform_machine == 'x86_64' and sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform != 'darwin' and sys_platform != 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'darwin' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda') or (sys_platform == 'linux' and extra == 'group-18-native-torch-probe-cpu' and extra == 'group-18-native-torch-probe-cuda')" },
]
wheels = [
    { url = "https://files.pythonhosted.org/packages/ef/bb/285d643f254731294c9b595a007eac39db4600a98682d7bca688f42ca164/torch-2.12.0-cp312-cp312-macosx_14_0_arm64.whl", hash = "sha256:b41339df93d491435e790ff8bcbae1c0ce777175889bfd1281d119862793e6a2", size = 88010197, upload-time = "2026-05-13T14:55:35.414Z" },
    { url = "https://files.pythonhosted.org/packages/de/f0/80026028b603c4650ff270fc3785bdef4bd6738765a9cc5a0f5a637d65a2/torch-2.12.0-cp312-cp312-manylinux_2_28_x86_64.whl", hash = "sha256:4b4f64c2c2b11f7510d93dd6412b87025ff6eddd6bb61c3b5a3d892ea20c4756", size = 532261691, upload-time = "2026-05-13T14:52:54.453Z" },
]

[[package]]
name = "torch"
version = "2.12.0+cpu"
source = { registry = "https://download.pytorch.org/whl/cpu" }
resolution-markers = [
    "platform_machine == 'x86_64' and sys_platform == 'linux'",
]
dependencies = [
    { name = "filelock", marker = "platform_machine == 'x86_64' and sys_platform == 'linux'" },
    { name = "fsspec", marker = "platform_machine == 'x86_64' and sys_platform == 'linux'" },
    { name = "jinja2", marker = "platform_machine == 'x86_64' and sys_platform == 'linux'" },
    { name = "networkx", marker = "platform_machine == 'x86_64' and sys_platform == 'linux'" },
    { name = "setuptools", marker = "platform_machine == 'x86_64' and sys_platform == 'linux'" },
    { name = "sympy", marker = "platform_machine == 'x86_64' and sys_platform == 'linux'" },
    { name = "typing-extensions", marker = "platform_machine == 'x86_64' and sys_platform == 'linux'" },
]
wheels = [
    { url = "https://download-r2.pytorch.org/whl/cpu/torch-2.12.0%2Bcpu-cp312-cp312-manylinux_2_28_x86_64.whl", hash = "sha256:5e3dc83725581fa38b7b2e45c58692e30b2a3cde19191af54b675ffcac3840a6", upload-time = "2026-05-12T23:16:48Z" },
]

[[package]]
name = "triton"
version = "3.7.0"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/62/7b/468a576e35beef1426e0828e28e9ba9e65f5474d496f16ee126c15646324/triton-3.7.0-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl", hash = "sha256:8f111161d49bf903c0eaedde3962353a3d841c08a836839b7cc1025b8426efcf", size = 201457567, upload-time = "2026-05-07T18:46:13.505Z" },
]

[[package]]
name = "typing-extensions"
version = "4.16.0"
source = { registry = "https://pypi.org/simple" }
sdist = { url = "https://files.pythonhosted.org/packages/f6/cc/6253133b5bb138fc3306cebfbda2c520f545d36b5be2c7255cc528bb45d6/typing_extensions-4.16.0.tar.gz", hash = "sha256:dc983d19a509c94dba722ee6abd33940f7c05a89e243c47e907eb4db6f1a43e5", size = 113555, upload-time = "2026-07-02T08:40:05.92Z" }
wheels = [
    { url = "https://files.pythonhosted.org/packages/49/d3/b8441a820a491ddfc024b0b0cf0393375b75ea13866d9c66727e54c2fc80/typing_extensions-4.16.0-py3-none-any.whl", hash = "sha256:481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8", size = 45571, upload-time = "2026-07-02T08:40:04.659Z" },
]
"""

# buildifier: disable=unused-variable
def _test_uv_issue_1510_verbatim_lock_impl(env, target):
    """End-to-end pipeline test (translate_uv -> resolve -> render_lock_bzl) on the verbatim #1510 uv.lock."""
    project = decode(_ISSUE_1510_PYPROJECT_TOML)
    lock = decode(_ISSUE_1510_UV_LOCK)
    raw = translate_uv(project, lock, _lock_model(dependency_groups = ["group:*"]))

    # 1. Verify deterministic per-(variant, version) content-hashed fork pins on torch:
    torch_pins = raw["pins"]["torch"]
    exprs = raw["resolution_marker_exprs"]
    env.expect.that_int(len(torch_pins)).equals(3)
    by_variant_target = {}
    for key, target_pkg in torch_pins.items():
        compound = exprs[key]
        marker_key = compound["marker"]
        env.expect.that_str(marker_key).contains("__edge_")
        by_variant_target[(compound["variant"], target_pkg)] = exprs[marker_key]
    env.expect.that_collection(by_variant_target.keys()).contains_exactly([
        ("group_native-torch-probe_cpu", "torch@2.12.0"),
        ("group_native-torch-probe_cpu", "torch@2.12.0+cpu"),
        ("group_native-torch-probe_cuda", "torch@2.12.0"),
    ])
    env.expect.that_str(by_variant_target[("group_native-torch-probe_cpu", "torch@2.12.0")]).contains("extra == '__variant_group_native-torch-probe_cpu'")
    env.expect.that_str(by_variant_target[("group_native-torch-probe_cpu", "torch@2.12.0+cpu")]).contains("extra == '__variant_group_native-torch-probe_cpu'")
    env.expect.that_str(by_variant_target[("group_native-torch-probe_cuda", "torch@2.12.0")]).equals("platform_machine == 'x86_64' and sys_platform == 'linux'")

    # 2. Run resolve() and check torch's availability markers reference __variant_ tokens.
    resolved = resolve(raw, include_transitive = True)
    torch_avail = resolved.packages["torch@2.12.0"]["availability_markers"]
    env.expect.that_int(len(torch_avail)).equals(3)
    env.expect.that_bool(any(["extra == '__variant_group_native-torch-probe_cpu'" in m for m in torch_avail])).equals(True)

    # 3. Render lock.bzl and verify variants = [":_variant_state"] on evaluators.
    repo_map = {k: "@repo//" + k + ":file" for k in resolved.remote_files.keys()}
    rendered_lock = render_lock_bzl(
        {
            "packages": resolved.packages,
            "cycle_groups": resolved.cycle_groups,
            "resolution_marker_exprs": resolved.resolution_marker_exprs,
        },
        repo_map,
        "ws",
        has_variants = True,
    )

    for extra_name in ["cudart", "cufft", "cufile", "cupti", "curand", "cusolver", "cusparse", "nvjitlink", "nvrtc", "nvtx"]:
        env.expect.that_str(rendered_lock).contains('"cuda-toolkit[{}]@13.0.2"'.format(extra_name))

    eval_blocks = [
        b.split("\n    )")[0]
        for b in rendered_lock.split("pycross_pep508_evaluator(\n")[1:]
    ]
    for block in eval_blocks:
        if "__variant_" in block.split('expr = "')[1].split('",')[0]:
            env.expect.that_str(block).contains('variants = [":_variant_state"]')
        else:
            env.expect.that_bool("variants =" in block).equals(False)

    env.expect.that_str(rendered_lock).contains('name = "_wheel_available_torch@2.12.0"')
    env.expect.that_bool(len(resolved.packages["torch@2.12.0"].get("availability_markers", [])) > 0).equals(True)
    env.expect.that_str(rendered_lock).contains("_marker_eval_")

def _test_uv_issue_1510_verbatim_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_issue_1510_verbatim_lock_impl)

def _test_uv_root_dependency_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_root_dependency_markers_impl)

# --- test_uv_url_filenames_decoded ---

# buildifier: disable=unused-variable
def _test_uv_url_filenames_decoded_impl(env, target):
    project = _project(deps = ["torch==2.5.1+cpu"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("torch", "2.5.1+cpu")]),
        _pkg("torch", "2.5.1+cpu", wheels = [
            _whl(url = "https://download.pytorch.org/whl/cpu/torch-2.5.1%2Bcpu-cp312-cp312-linux_x86_64.whl"),
        ]),
    ])
    result = translate_uv(project, lock, _lock_model())
    files = result["packages"]["torch@2.5.1+cpu"]["files"]
    env.expect.that_str(files[0]["name"]).equals("torch-2.5.1+cpu-cp312-cp312-linux_x86_64.whl")
    env.expect.that_collection(files[0]["urls"]).contains_exactly([
        "https://download.pytorch.org/whl/cpu/torch-2.5.1%2Bcpu-cp312-cp312-linux_x86_64.whl",
    ])

def _test_uv_url_filenames_decoded(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_url_filenames_decoded_impl)

# --- test_uv_url_and_git_sources ---

# buildifier: disable=unused-variable
def _test_uv_url_and_git_sources_impl(env, target):
    project = _project(deps = ["boto3", "sub"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("boto3"), _dep("sub")]),
        {
            "name": "boto3",
            "version": "1.35.13",
            "source": {"url": "https://github.com/boto/boto3/archive/refs/tags/1.35.13.zip"},
            "sdist": {"hash": "sha256:abcd"},
        },
        {
            "name": "sub",
            "version": "0.1.0",
            "source": {"git": "https://github.com/example/mono?subdirectory=pkgs%2Fsub&rev=main#0123456789abcdef"},
        },
    ])
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_str(result["packages"]["boto3@1.35.13"]["files"][0]["name"]).equals("boto3-1.35.13.zip")
    sub = result["packages"]["sub@0.1.0"]
    env.expect.that_str(sub["source_dir"]).equals("pkgs/sub")
    env.expect.that_str(sub["files"][0]["name"]).equals("sub-0.1.0.tar.gz")

def _test_uv_url_and_git_sources(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_url_and_git_sources_impl)

# --- test_uv_virtual_and_directory_members ---

# buildifier: disable=unused-variable
def _test_uv_virtual_and_directory_members_impl(env, target):
    lock = _lock([
        _vpkg("root"),
        {"name": "member", "version": "0.1.0", "source": {"virtual": "packages/member"}, "dependencies": [_dep("a")]},
        {"name": "localdep", "version": "0.1.0", "source": {"directory": "packages/localdep"}, "dependencies": [_dep("b")]},
        _pkg("a", "1.0", wheels = [_whl("a-1.0-py3-none-any.whl", "a")]),
        _pkg("b", "1.0", wheels = [_whl("b-1.0-py3-none-any.whl", "b")]),
    ])
    result = translate_uv(_project(name = "root"), lock, _lock_model(projects = ["*"]))

    # The non-root virtual member is a project; the directory dep is local.
    env.expect.that_collection(result["pins"].keys()).contains_exactly(["a"])
    env.expect.that_collection(result["packages"].keys()).contains_exactly(["a@1.0", "b@1.0"])

def _test_uv_virtual_and_directory_members(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_virtual_and_directory_members_impl)

# --- test_fold_variant_marker ---

# buildifier: disable=unused-variable
def _test_fold_variant_marker_impl(env, target):
    sets = [["group_app_cpu", "group_app_cuda"]]
    env.expect.that_str(fold_variant_marker("", active_qnames = ["group_app_cpu"], conflict_sets = sets)).equals("T")
    env.expect.that_str(fold_variant_marker("sys_platform == 'linux'", active_qnames = ["group_app_cpu"], conflict_sets = sets)).equals("N")
    env.expect.that_str(fold_variant_marker("extra == '__variant_group_app_cuda'", active_qnames = ["group_app_cuda"], conflict_sets = sets)).equals("T")
    env.expect.that_str(fold_variant_marker("'__variant_group_app_cuda' == extra", active_qnames = ["group_app_cuda"], conflict_sets = sets)).equals("T")
    env.expect.that_str(fold_variant_marker("extra == '__variant_group_app_cuda'", active_qnames = ["group_app_cpu"], conflict_sets = sets)).equals("F")
    env.expect.that_str(fold_variant_marker("extra != '__variant_group_app_cuda'", active_qnames = ["group_app_cpu"], conflict_sets = sets)).equals("T")
    env.expect.that_str(fold_variant_marker("extra != '__variant_group_app_cpu'", active_qnames = ["group_app_cpu"], conflict_sets = sets)).equals("F")
    env.expect.that_str(fold_variant_marker("extra == '__variant_group_app_cpu' and extra != '__variant_group_app_cpu'", conflict_sets = sets)).equals("F")
    env.expect.that_str(fold_variant_marker(
        "(sys_platform == 'darwin' and extra == '__variant_group_app_cpu') or (extra == '__variant_group_app_cpu' and extra == '__variant_group_app_cuda')",
        active_qnames = ["group_app_cpu"],
        conflict_sets = sets,
    )).equals("N")
    env.expect.that_str(fold_variant_marker(
        "(sys_platform == 'darwin' and extra == '__variant_group_app_cpu') or (extra == '__variant_group_app_cpu' and extra == '__variant_group_app_cuda')",
        active_qnames = ["group_app_cuda"],
        conflict_sets = sets,
    )).equals("F")
    env.expect.that_str(fold_variant_marker(
        "(extra == '__variant_group_app_cpu' and extra == '__variant_group_app_cuda') or (extra != '__variant_group_app_cpu' and extra != '__variant_group_app_cuda')",
        active_qnames = ["group_app_cpu"],
        conflict_sets = sets,
    )).equals("F")
    env.expect.that_str(fold_variant_marker(
        "(extra == '__variant_group_app_cpu' and extra == '__variant_group_app_cuda') or (extra != '__variant_group_app_cpu' and extra != '__variant_group_app_cuda')",
        conflict_sets = sets,
    )).equals("V")
    env.expect.that_str(fold_variant_marker(
        "sys_platform == 'linux' or (extra == '__variant_group_app_cpu' and extra == '__variant_group_app_cuda')",
        conflict_sets = sets,
    )).equals("N")

    # Overlapping conflict sets + nested parens.
    overlapping = [["group_app_a", "group_app_b"], ["group_app_a", "group_app_c"]]
    env.expect.that_str(fold_variant_marker(
        "((extra == '__variant_group_app_b' or extra == '__variant_group_app_c') and sys_platform == 'linux')",
        active_qnames = ["group_app_a"],
        conflict_sets = overlapping,
    )).equals("F")
    env.expect.that_str(fold_variant_marker(
        "extra == '__variant_group_app_b' and extra == '__variant_group_app_c'",
        conflict_sets = overlapping,
    )).equals("V")

    # Joint folding across multiple simultaneous active variants (orthogonal sets) + contradictory active_qnames.
    orthogonal = [["group_app_a", "group_app_b"], ["extra_app_c", "extra_app_d"]]
    env.expect.that_str(fold_variant_marker(
        "extra == '__variant_group_app_b' or extra == '__variant_extra_app_d'",
        active_qnames = ["group_app_a", "extra_app_c"],
        conflict_sets = orthogonal,
    )).equals("F")
    env.expect.that_str(fold_variant_marker(
        "extra == '__variant_group_app_a'",
        active_qnames = ["group_app_a", "group_app_b"],
        conflict_sets = orthogonal,
    )).equals("F")

    # Parenthesized conjunctions (as emitted by combine_markers) still detect contradictions.
    env.expect.that_str(fold_variant_marker(
        "(extra == '__variant_group_app_cpu') and (extra == '__variant_group_app_cuda')",
        conflict_sets = sets,
    )).equals("F")
    env.expect.that_str(fold_variant_marker(
        "(extra == '__variant_group_app_cpu' and sys_platform == 'linux') and (extra != '__variant_group_app_cpu')",
        conflict_sets = sets,
    )).equals("F")

def _test_fold_variant_marker(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_fold_variant_marker_impl)

# --- test_fold_variant_marker_memoization ---

# buildifier: disable=unused-variable
def _test_fold_variant_marker_memoization_impl(env, target):
    sets = [["group_app_cpu", "group_app_cuda"], ["extra_app_x", "extra_app_y"]]
    pairs = variant_conflict_pairs(sets)

    empty_tokens = variant_active_tokens((), sets)
    env.expect.that_dict(empty_tokens.true_tokens).contains_exactly({})
    env.expect.that_dict(empty_tokens.false_tokens).contains_exactly({})
    env.expect.that_bool(empty_tokens.contradicted).equals(False)

    cpu_tokens = variant_active_tokens(["group_app_cpu"], sets)
    env.expect.that_dict(cpu_tokens.true_tokens).contains_exactly({"-variant-group-app-cpu": True})
    env.expect.that_dict(cpu_tokens.false_tokens).contains_exactly({"-variant-group-app-cuda": True})
    env.expect.that_bool(cpu_tokens.contradicted).equals(False)

    cuda_tokens = variant_active_tokens(["group_app_cuda"], sets)
    contradicted_tokens = variant_active_tokens(["group_app_cpu", "group_app_cuda"], sets)
    env.expect.that_bool(contradicted_tokens.contradicted).equals(True)

    # Cached folds with precomputed active_tokens match explicit expected outcomes and uncached folds.
    markers = [
        "",
        "sys_platform == 'linux'",
        "extra == '__variant_group_app_cpu'",
        "(sys_platform == 'darwin' and extra == '__variant_group_app_cpu') or (extra == '__variant_group_app_cpu' and extra == '__variant_group_app_cuda')",
        "((extra == '__variant_group_app_cpu' or extra == '__variant_extra_app_x') and sys_platform == 'linux')",
    ]
    token_cases = [
        ((), empty_tokens, ["T", "N", "V", "V", "V"]),
        (["group_app_cpu"], cpu_tokens, ["T", "N", "T", "N", "N"]),
        (["group_app_cuda"], cuda_tokens, ["T", "N", "F", "F", "V"]),
        (["group_app_cpu", "group_app_cuda"], contradicted_tokens, ["T", "N", "F", "F", "F"]),
    ]
    parse_cache = {}
    ast_snapshots = {}
    for active_qnames, active_tokens, expected_outcomes in token_cases:
        for marker, expected in zip(markers, expected_outcomes):
            uncached = fold_variant_marker(marker, active_qnames = active_qnames, conflict_sets = sets)
            actual = fold_variant_marker(
                marker,
                conflict_pairs = pairs,
                parse_cache = parse_cache,
                active_tokens = active_tokens,
            )
            env.expect.that_str(uncached).equals(expected)
            env.expect.that_str(actual).equals(expected)
            if marker in parse_cache:
                snap = str(parse_cache[marker])
                if marker in ast_snapshots:
                    env.expect.that_str(snap).equals(ast_snapshots[marker])
                else:
                    ast_snapshots[marker] = snap

    # Only variant-bearing markers populate parse_cache (fast-path markers stay uncached).
    env.expect.that_collection(parse_cache.keys()).contains_exactly(markers[2:])

    # Pre-populated parse_cache entries bypass pypackaging.markers.parse.
    sentinel = "invalid syntax __variant_sentinel ==="
    parse_cache[sentinel] = parse_cache["extra == '__variant_group_app_cpu'"]
    env.expect.that_str(fold_variant_marker(
        sentinel,
        conflict_pairs = pairs,
        parse_cache = parse_cache,
        active_tokens = cpu_tokens,
    )).equals("T")
    env.expect.that_str(fold_variant_marker(
        sentinel,
        conflict_pairs = pairs,
        parse_cache = parse_cache,
        active_tokens = cuda_tokens,
    )).equals("F")

def _test_fold_variant_marker_memoization(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_fold_variant_marker_memoization_impl)

# --- test_pin_marker_folder_and_shared_caches ---

# buildifier: disable=unused-variable
def _test_pin_marker_folder_and_shared_caches_impl(env, target):
    conflicts = parse_uv_conflicts(
        [
            [{"package": "app", "group": "cpu"}, {"package": "app", "group": "cuda"}],
            [{"package": "app", "extra": "x"}, {"package": "app", "extra": "y"}],
        ],
        target_projects = ["app"],
    )
    m_cpu = "extra == '__variant_group_app_cpu'"
    m_cuda = "extra == '__variant_group_app_cuda'"
    m_x = "extra == '__variant_extra_app_x'"
    m_cpu_linux = "extra == '__variant_group_app_cpu' and sys_platform == 'linux'"
    m_plain = "sys_platform == 'linux'"

    parse_cache = {}
    tokens_cache = {}
    fold_cache = {}
    folder = make_pin_marker_folder(
        conflicts,
        ["group_app_cpu"],
        parse_cache = parse_cache,
        tokens_cache = tokens_cache,
        fold_cache = fold_cache,
    )

    # Empty and non-variant markers return untouched without populating caches.
    env.expect.that_str(folder("group_app_cpu", "")).equals("")
    env.expect.that_str(folder("group_app_cpu", m_plain)).equals(m_plain)
    env.expect.that_dict(tokens_cache).contains_exactly({})
    env.expect.that_dict(fold_cache).contains_exactly({})

    # "F" -> None (both with and without constraint); "T" with constraint -> "";
    # "T" without constraint keeps marker; "V" and "N" keep marker.
    env.expect.that_bool(folder("group_app_cpu", m_cuda) == None).equals(True)
    env.expect.that_bool(folder("", m_cuda) == None).equals(True)
    env.expect.that_str(folder("group_app_cpu", m_cpu)).equals("")
    env.expect.that_str(folder("", m_cpu)).equals(m_cpu)
    env.expect.that_str(folder("group_app_cpu", m_x)).equals(m_x)
    env.expect.that_str(folder("", m_x)).equals(m_x)
    env.expect.that_str(folder("group_app_cpu", m_cpu_linux)).equals(m_cpu_linux)

    env.expect.that_collection(tokens_cache.keys()).contains_exactly(["group_app_cpu", ""])
    env.expect.that_dict(fold_cache).contains_exactly({
        ("group_app_cpu", m_cuda): "F",
        ("", m_cuda): "F",
        ("group_app_cpu", m_cpu): "T",
        ("", m_cpu): "T",
        ("group_app_cpu", m_x): "V",
        ("", m_x): "V",
        ("group_app_cpu", m_cpu_linux): "N",
    })

    # Pre-populated fold_cache entries bypass parsing inside make_pin_marker_folder.
    sentinel_f = "invalid syntax __variant_cached_f ==="
    sentinel_t = "invalid syntax __variant_cached_t ==="
    fold_cache[("group_app_cpu", sentinel_f)] = "F"
    fold_cache[("group_app_cpu", sentinel_t)] = "T"
    fold_cache[("", sentinel_t)] = "T"
    env.expect.that_bool(folder("group_app_cpu", sentinel_f) == None).equals(True)
    env.expect.that_str(folder("group_app_cpu", sentinel_t)).equals("")
    env.expect.that_str(folder("", sentinel_t)).equals(sentinel_t)
    env.expect.that_collection(parse_cache.keys()).contains_exactly([m_cuda, m_cpu, m_x, m_cpu_linux])

    # Shared tokens_cache and fold_cache flow from make_pin_marker_folder into
    # resolve_uv_pins and _prune_plain_branches without re-parsing.
    shared_parse = {}
    shared_tokens = {}
    shared_fold = {}
    unpinned_folder = make_pin_marker_folder(
        conflicts,
        [],
        parse_cache = shared_parse,
        tokens_cache = shared_tokens,
        fold_cache = shared_fold,
    )
    env.expect.that_str(unpinned_folder("", m_cuda)).equals(m_cuda)
    env.expect.that_str(unpinned_folder("group_app_cuda", m_cuda)).equals("")

    def _edge(pin_name, pkg_key, constraint, pin_marker):
        return struct(
            pin_name = pin_name,
            pkg_key = pkg_key,
            constraint = constraint,
            is_testonly = False,
            pin_marker = pin_marker,
            avail_marker = "",
            from_local = False,
        )

    fresh_parse = {}
    exprs = {}
    resolved = resolve_uv_pins(
        [
            _edge("torch", "torch@1.0", "group_app_cpu", ""),
            _edge("torch", "torch@2.0", "", m_cuda),
        ],
        conflicts = conflicts,
        repo_pins = [],
        fork_constraints = {},
        resolution_marker_exprs = exprs,
        parse_cache = fresh_parse,
        tokens_cache = shared_tokens,
        fold_cache = shared_fold,
    )
    env.expect.that_dict(fresh_parse).contains_exactly({})
    env.expect.that_str(resolved.pinned_keys["torch"]["group_app_cpu"]).equals("torch@1.0")
    plain_keys = [k for k in resolved.pinned_keys["torch"].keys() if k != "group_app_cpu"]
    env.expect.that_collection(plain_keys).has_size(1)
    env.expect.that_str(resolved.pinned_keys["torch"][plain_keys[0]]).equals("torch@2.0")
    env.expect.that_str(exprs[plain_keys[0]]).contains("(extra == '__variant_group_app_cuda') and ")

    # _prune_plain_branches honors fold_cache hits directly for both drop ("F") and narrow ("T").
    sentinel_drop = "extra == '__variant_group_app_cuda' and invalid drop ==="
    sentinel_keep = "extra == '__variant_group_app_cuda' and invalid keep ==="
    prune_parse = {}
    prune_fold = {
        ("", sentinel_drop): "V",
        ("group_app_cuda", sentinel_drop): "F",
        ("", sentinel_keep): "V",
        ("group_app_cuda", sentinel_keep): "T",
    }
    prune_exprs = {}
    pruned = resolve_uv_pins(
        [
            _edge("drop-pkg", "drop-pkg@1.0", "group_app_cpu", ""),
            _edge("drop-pkg", "drop-pkg@2.0", "", sentinel_drop),
            _edge("keep-pkg", "keep-pkg@1.0", "group_app_cpu", ""),
            _edge("keep-pkg", "keep-pkg@2.0", "", sentinel_keep),
        ],
        conflicts = conflicts,
        repo_pins = [],
        fork_constraints = {},
        resolution_marker_exprs = prune_exprs,
        parse_cache = prune_parse,
        tokens_cache = {},
        fold_cache = prune_fold,
    )
    env.expect.that_dict(prune_parse).contains_exactly({})
    env.expect.that_dict(pruned.pinned_keys["drop-pkg"]).contains_exactly({"group_app_cpu": "drop-pkg@1.0"})
    keep_plain_keys = [k for k in pruned.pinned_keys["keep-pkg"].keys() if k != "group_app_cpu"]
    env.expect.that_collection(keep_plain_keys).has_size(1)
    env.expect.that_str(pruned.pinned_keys["keep-pkg"][keep_plain_keys[0]]).equals("keep-pkg@2.0")
    env.expect.that_str(prune_exprs[keep_plain_keys[0]]).equals(
        "(extra == '__variant_group_app_cuda') and ({})".format(sentinel_keep),
    )

def _test_pin_marker_folder_and_shared_caches(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_marker_folder_and_shared_caches_impl)

# --- test_uv_local_member_conflict_markers ---

# buildifier: disable=unused-variable
def _test_uv_local_member_conflict_markers_impl(env, target):
    """Local member conflict-routed deps stay disjoint across root, wildcard, per-variant, and member-only repos."""
    m_darwin_cpu = "(sys_platform == 'darwin' and extra == 'group-14-conflict-repro-cpu') or (extra == 'group-14-conflict-repro-cpu' and extra == 'group-14-conflict-repro-cuda')"
    m_notdarwin_cpu = "(sys_platform != 'darwin' and extra == 'group-14-conflict-repro-cpu') or (extra == 'group-14-conflict-repro-cpu' and extra == 'group-14-conflict-repro-cuda')"
    m_neither = "(extra == 'group-14-conflict-repro-cpu' and extra == 'group-14-conflict-repro-cuda') or (extra != 'group-14-conflict-repro-cpu' and extra != 'group-14-conflict-repro-cuda')"
    m_cuda = "extra == 'group-14-conflict-repro-cuda'"

    project = _project(name = "conflict-repro")
    lock = _lock(
        [
            _vpkg(
                "conflict-repro",
                version = "0.0.0",
                dev_deps = {
                    "cpu": [
                        _dep("lib"),
                        _dep("torch", "2.9.1", marker = m_darwin_cpu),
                        _dep("torch", "2.9.1+cpu", marker = m_notdarwin_cpu),
                    ],
                    "cuda": [
                        _dep("lib"),
                        _dep("torch", "2.9.1+cu129"),
                    ],
                },
            ),
            _pkg(
                "lib",
                "0.1.0",
                source = {"editable": "lib"},
                deps = [
                    _dep("torch", "2.9.1", marker = m_darwin_cpu),
                    _dep("torch", "2.9.1", marker = m_neither),
                    _dep("torch", "2.9.1+cpu", marker = m_notdarwin_cpu),
                    _dep("torch", "2.9.1+cu129", marker = m_cuda),
                ],
            ),
            _pkg("torch", "2.9.1", markers = ["sys_platform == 'darwin'"], wheels = [_whl("torch-2.9.1-cp312-none-macosx_11_0_arm64.whl", "a1")]),
            _pkg("torch", "2.9.1", wheels = [_whl("torch-2.9.1-cp312-cp312-manylinux_2_28_x86_64.whl", "a2")]),
            _pkg("torch", "2.9.1+cpu", markers = ["sys_platform != 'darwin'"], wheels = [_whl("torch-2.9.1%2Bcpu-cp312-cp312-manylinux_2_28_x86_64.whl", "b1")]),
            _pkg("torch", "2.9.1+cu129", wheels = [_whl("torch-2.9.1%2Bcu129-cp312-cp312-manylinux_2_28_x86_64.whl", "c1")]),
        ],
        conflicts = [[
            {"package": "conflict-repro", "group": "cpu"},
            {"package": "conflict-repro", "group": "cuda"},
        ]],
    )

    def _pin_summary(res):
        exprs = res.get("resolution_marker_exprs", {})
        items = []
        for key, target_pkg in res["pins"]["torch"].items():
            expr = exprs.get(key)
            if type(expr) == "dict":
                items.append((expr["variant"], target_pkg, True))
            else:
                items.append((key, target_pkg, False))
        return items

    expected_both = [
        ("group_conflict-repro_cpu", "torch@2.9.1", True),
        ("group_conflict-repro_cpu", "torch@2.9.1+cpu", True),
        ("group_conflict-repro_cuda", "torch@2.9.1+cu129", False),
    ]

    # 1. Root project with both conflict groups.
    root_both = translate_uv(project, lock, _lock_model(projects = ["conflict-repro"], dependency_groups = ["default", "group:cpu", "group:cuda"]))
    env.expect.that_collection(_pin_summary(root_both)).contains_exactly(expected_both)

    # 2. Wildcard projects with both conflict groups: plain __edge_ entries from lib are pruned.
    all_both = translate_uv(project, lock, _lock_model(projects = ["*"], dependency_groups = ["default", "group:cpu", "group:cuda"]))
    env.expect.that_collection(_pin_summary(all_both)).contains_exactly(expected_both)
    env.expect.that_dict(all_both["pins"]["torch"]).contains_exactly(root_both["pins"]["torch"])

    # 3. CPU-only repo with wildcard projects: no CUDA branch or plain __edge_ entries.
    all_cpu = translate_uv(project, lock, _lock_model(projects = ["*"], dependency_groups = ["default", "group:cpu"]))
    env.expect.that_collection(_pin_summary(all_cpu)).contains_exactly([
        ("group_conflict-repro_cpu", "torch@2.9.1", True),
        ("group_conflict-repro_cpu", "torch@2.9.1+cpu", True),
    ])

    # 4. CUDA-only repo with wildcard projects: only the CUDA variant branch.
    all_cuda = translate_uv(project, lock, _lock_model(projects = ["*"], dependency_groups = ["default", "group:cuda"]))
    env.expect.that_dict(all_cuda["pins"]["torch"]).contains_exactly({
        "group_conflict-repro_cuda": "torch@2.9.1+cu129",
    })

    # 5. Member-only repo without conflict groups: keeps all three conflict-routed __edge_ branches.
    lib_only = translate_uv(_project(name = "lib"), lock, _lock_model(projects = ["lib"], dependency_groups = ["default"]))
    lib_torch = lib_only["pins"]["torch"]
    env.expect.that_collection(lib_torch.values()).contains_exactly(["torch@2.9.1", "torch@2.9.1+cpu", "torch@2.9.1+cu129"])
    by_ver = {v: k for k, v in lib_torch.items()}
    for ver in ["torch@2.9.1", "torch@2.9.1+cpu", "torch@2.9.1+cu129"]:
        env.expect.that_str(by_ver[ver]).contains("__edge_")
    env.expect.that_str(lib_only["resolution_marker_exprs"][by_ver["torch@2.9.1"]]).contains("extra != '__variant_group_conflict-repro_cpu'")

def _test_uv_local_member_conflict_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_local_member_conflict_markers_impl)

# --- test_uv_local_member_chain_and_empty_pin_pruning ---

# buildifier: disable=unused-variable
def _test_uv_local_member_chain_and_empty_pin_pruning_impl(env, target):
    """Multi-hop local member expansion prunes unsatisfiable conflict branches and drops emptied pins."""
    m_cpu = "extra == 'group-4-root-cpu'"
    m_cuda = "extra == 'group-4-root-cuda'"
    lock = _lock(
        [
            _vpkg("root", dev_deps = {"cpu": [_dep("lib-a")], "cuda": [_dep("lib-a")]}),
            _pkg("lib-a", "0.1.0", source = {"editable": "a"}, deps = [_dep("lib-b")]),
            _pkg(
                "lib-b",
                "0.1.0",
                source = {"editable": "b"},
                deps = [
                    _dep("torch", "2.9.1+cpu", marker = m_cpu),
                    _dep("torch", "2.9.1+cu129", marker = m_cuda),
                    _dep("triton", "3.5.1", marker = m_cuda),
                ],
            ),
            _pkg("torch", "2.9.1+cpu", wheels = [_whl("torch-2.9.1%2Bcpu-cp312-cp312-manylinux_2_28_x86_64.whl", "aa")]),
            _pkg("torch", "2.9.1+cu129", wheels = [_whl("torch-2.9.1%2Bcu129-cp312-cp312-manylinux_2_28_x86_64.whl", "bb")]),
            _pkg("triton", "3.5.1", wheels = [_whl("triton-3.5.1-cp312-cp312-manylinux_2_28_x86_64.whl", "cc")]),
        ],
        conflicts = [[
            {"package": "root", "group": "cpu"},
            {"package": "root", "group": "cuda"},
        ]],
    )

    both = translate_uv(_project(name = "root"), lock, _lock_model(projects = ["root"], dependency_groups = ["default", "group:cpu", "group:cuda"]))
    env.expect.that_dict(both["pins"]["torch"]).contains_exactly({
        "group_root_cpu": "torch@2.9.1+cpu",
        "group_root_cuda": "torch@2.9.1+cu129",
    })
    env.expect.that_dict(both["pins"]["triton"]).contains_exactly({
        "group_root_cuda": "triton@3.5.1",
    })

    # In a CPU-only wildcard repo, triton is only satisfiable under cuda so its
    # pin and root_dependency_markers entry are both dropped cleanly.
    cpu_only = translate_uv(_project(name = "root"), lock, _lock_model(projects = ["*"], dependency_groups = ["default", "group:cpu"]))
    env.expect.that_dict(cpu_only["pins"]["torch"]).contains_exactly({"group_root_cpu": "torch@2.9.1+cpu"})
    env.expect.that_collection(cpu_only["pins"].keys()).not_contains("triton")
    env.expect.that_collection(cpu_only.get("root_dependency_markers", {}).keys()).not_contains("triton")

def _test_uv_local_member_chain_and_empty_pin_pruning(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_local_member_chain_and_empty_pin_pruning_impl)

# --- test_uv_asymmetric_fork_with_independent_member ---

# buildifier: disable=unused-variable
def _test_uv_asymmetric_fork_with_independent_member_impl(env, target):
    """When a conflict variant only covers one forked version, an independent member's edge for another version is narrowed rather than dropped."""
    m_cpu_darwin = "sys_platform == 'darwin' and extra == 'group-4-root-cpu'"
    m_cpu_other = "sys_platform != 'darwin' and extra == 'group-4-root-cpu'"
    m_cuda_linux = "sys_platform == 'linux' and extra == 'group-4-root-cuda'"
    m_lib_plain = "(sys_platform == 'darwin' and extra == 'group-4-root-cpu') or (sys_platform != 'linux' and extra == 'group-4-root-cuda') or (extra != 'group-4-root-cpu' and extra != 'group-4-root-cuda')"
    lock = _lock(
        [
            _vpkg(
                "root",
                dev_deps = {
                    "cpu": [
                        _dep("torch", "2.9.1", marker = m_cpu_darwin),
                        _dep("torch", "2.9.1+cpu", marker = m_cpu_other),
                    ],
                    "cuda": [
                        _dep("torch", "2.9.1+cu129", marker = m_cuda_linux),
                    ],
                },
            ),
            _pkg(
                "lib",
                "0.1.0",
                source = {"editable": "lib"},
                deps = [
                    _dep("torch", "2.9.1", marker = m_lib_plain),
                    _dep("torch", "2.9.1+cpu", marker = m_cpu_other),
                    _dep("torch", "2.9.1+cu129", marker = m_cuda_linux),
                ],
            ),
            _pkg("torch", "2.9.1", markers = ["sys_platform == 'darwin'"], wheels = [_whl("torch-2.9.1-cp312-none-macosx_11_0_arm64.whl", "a1")]),
            _pkg("torch", "2.9.1+cpu", markers = ["sys_platform != 'darwin'"], wheels = [_whl("torch-2.9.1%2Bcpu-cp312-cp312-manylinux_2_28_x86_64.whl", "b1")]),
            _pkg("torch", "2.9.1+cu129", markers = ["sys_platform == 'linux'"], wheels = [_whl("torch-2.9.1%2Bcu129-cp312-cp312-manylinux_2_28_x86_64.whl", "c1")]),
        ],
        conflicts = [[
            {"package": "root", "group": "cpu"},
            {"package": "root", "group": "cuda"},
        ]],
    )

    result = translate_uv(_project(name = "root"), lock, _lock_model(projects = ["*"], dependency_groups = ["default", "group:cpu", "group:cuda"]))
    torch_pin = result["pins"]["torch"]
    exprs = result["resolution_marker_exprs"]

    # Root's three variant-fork entries stay intact as compound constraints.
    compound_branches = [
        (exprs[k]["variant"], target_pkg)
        for k, target_pkg in torch_pin.items()
        if type(exprs.get(k)) == "dict"
    ]
    env.expect.that_collection(compound_branches).contains_exactly([
        ("group_root_cpu", "torch@2.9.1"),
        ("group_root_cpu", "torch@2.9.1+cpu"),
        ("group_root_cuda", "torch@2.9.1+cu129"),
    ])

    # Lib's 2.9.1 edge stays narrowed to cuda (the only variant that does not
    # already have a 2.9.1 entry), while its 2.9.1+cpu and 2.9.1+cu129 edges are dropped.
    plain_edge_keys = [k for k in torch_pin.keys() if type(exprs.get(k)) == "string" and "__edge_" in k]
    env.expect.that_collection(plain_edge_keys).has_size(1)
    env.expect.that_str(torch_pin[plain_edge_keys[0]]).equals("torch@2.9.1")
    env.expect.that_str(exprs[plain_edge_keys[0]]).contains("(extra == '__variant_group_root_cuda') and ")

def _test_uv_asymmetric_fork_with_independent_member(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_asymmetric_fork_with_independent_member_impl)

# --- test_uv_testonly_local_member_expansion ---

# buildifier: disable=unused-variable
def _test_uv_testonly_local_member_expansion_impl(env, target):
    """Testonly local member deps stay testonly unless reachable from runtime pins, and pruned edges don't strip testonly."""
    lock = _lock(
        [
            _vpkg("app", deps = [_dep("runtime-pkg", "1.0")], dev_deps = {"test": [_dep("test-helper")]}),
            _pkg("test-helper", "0.1.0", source = {"editable": "test-helper"}, deps = [_dep("pytest", "8.0"), _dep("shared", "1.0")]),
            _pkg("runtime-pkg", "1.0", wheels = [_whl("runtime_pkg-1.0-py3-none-any.whl", "r1")], deps = [_dep("shared", "1.0")]),
            _pkg("shared", "1.0", wheels = [_whl("shared-1.0-py3-none-any.whl", "s1")]),
            _pkg("pytest", "8.0", wheels = [_whl("pytest-8.0-py3-none-any.whl", "p1")]),
        ],
    )
    result = translate_uv(
        _project(name = "app"),
        lock,
        _lock_model(projects = ["app"], dependency_groups = ["default", "group:test"], testonly_groups = ["group:test"]),
    )
    env.expect.that_collection(result["testonly_pins"]).contains_exactly(["pytest"])

    # A pruned non-testonly edge from another member does not strip testonly from a surviving testonly pin.
    conflict_lock = _lock(
        [
            _vpkg("root", dev_deps = {"cpu": [_dep("pytest", "8.0")], "cuda": []}),
            _pkg("lib", "0.1.0", source = {"editable": "lib"}, deps = [_dep("pytest", "8.0", marker = "extra == 'group-4-root-cuda'")]),
            _pkg("pytest", "8.0", wheels = [_whl("pytest-8.0-py3-none-any.whl", "p1")]),
        ],
        conflicts = [[{"package": "root", "group": "cpu"}, {"package": "root", "group": "cuda"}]],
    )
    pruned_res = translate_uv(
        _project(name = "root"),
        conflict_lock,
        _lock_model(projects = ["*"], dependency_groups = ["default", "group:cpu"], testonly_groups = ["group:cpu"]),
    )
    env.expect.that_collection(pruned_res["testonly_pins"]).contains_exactly(["pytest"])

def _test_uv_testonly_local_member_expansion(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_testonly_local_member_expansion_impl)

# --- test_uv_local_member_edge_cases ---

# buildifier: disable=unused-variable
def _test_uv_local_member_edge_cases_impl(env, target):
    """Covers local cycles with markers, local+registry name match, all-pruned unversioned forks, and base+extra marker collisions."""

    # 1. Local cycle with markers terminates cleanly, and exact registry version is not hijacked by a local package.
    cycle_lock = _lock([
        _vpkg("root", deps = [_dep("lib-a"), _dep("dual", "2.0.0")]),
        _pkg("lib-a", "0.1.0", source = {"editable": "a"}, deps = [_dep("lib-b", marker = "sys_platform == 'linux'")]),
        _pkg("lib-b", "0.1.0", source = {"editable": "b"}, deps = [_dep("lib-a", marker = "python_version >= '3.10'"), _dep("six", "1.17.0")]),
        _pkg("dual", "0.1.0", source = {"editable": "dual"}),
        _pkg("dual", "2.0.0", wheels = [_whl("dual-2.0.0-py3-none-any.whl", "d2")]),
        _pkg("six", "1.17.0", wheels = [_whl("six-1.17.0-py2.py3-none-any.whl", "s1")]),
    ])
    cycle_res = translate_uv(_project(name = "root"), cycle_lock, _lock_model(projects = ["root"]))
    env.expect.that_str(cycle_res["pins"]["six"]).equals("six@1.17.0")
    env.expect.that_str(cycle_res["pins"]["dual"]).equals("dual@2.0.0")

    # 2. Unversioned local dep to a forked package whose forks are all pruned under the active variant is dropped (not re-emitted unversioned).
    pruned_fork_lock = _lock(
        [
            _vpkg("root", dev_deps = {"cpu": [_dep("lib")], "cuda": [_dep("lib")]}),
            _pkg("lib", "0.1.0", source = {"editable": "lib"}, deps = [_dep("forkpkg")]),
            _pkg("forkpkg", "1.0", markers = ["sys_platform == 'linux' and extra == 'group-4-root-cuda'"], wheels = [_whl("forkpkg-1.0-py3-none-any.whl", "f1")]),
            _pkg("forkpkg", "2.0", markers = ["sys_platform == 'darwin' and extra == 'group-4-root-cuda'"], wheels = [_whl("forkpkg-2.0-py3-none-any.whl", "f2")]),
        ],
        conflicts = [[{"package": "root", "group": "cpu"}, {"package": "root", "group": "cuda"}]],
    )
    cpu_fork_res = translate_uv(_project(name = "root"), pruned_fork_lock, _lock_model(projects = ["root"], dependency_groups = ["default", "group:cpu"]))
    env.expect.that_collection(cpu_fork_res["pins"].keys()).not_contains("forkpkg")

    # 3. Base package and extra at the same forked version with distinct markers under one variant do not clobber each other.
    extra_fork_lock = _lock(
        [
            _vpkg(
                "root",
                dev_deps = {
                    "cpu": [
                        _dep("torch", "2.9.1", marker = "sys_platform == 'darwin' and extra == 'group-4-root-cpu'"),
                        _dep("torch", "2.9.1", extra = ["opt"], marker = "sys_platform == 'linux' and extra == 'group-4-root-cpu'"),
                    ],
                },
            ),
            _pkg("torch", "2.9.1", markers = ["sys_platform == 'darwin'"], wheels = [_whl("torch-2.9.1-py3-none-any.whl", "t1")], opt_deps = {"opt": []}),
            _pkg("torch", "2.9.1+cpu", markers = ["sys_platform != 'darwin'"], wheels = [_whl("torch-2.9.1%2Bcpu-py3-none-any.whl", "t2")], opt_deps = {"opt": []}),
        ],
        conflicts = [[{"package": "root", "group": "cpu"}, {"package": "root", "group": "cuda"}]],
    )
    extra_res = translate_uv(_project(name = "root"), extra_fork_lock, _lock_model(projects = ["root"], dependency_groups = ["default", "group:cpu"]))
    base_k = extra_res["pins"]["torch"].keys()[0]
    opt_k = extra_res["pins"]["torch[opt]"].keys()[0]
    env.expect.that_bool(base_k != opt_k).equals(True)
    env.expect.that_str(extra_res["resolution_marker_exprs"][extra_res["resolution_marker_exprs"][base_k]["marker"]]).contains("darwin")
    env.expect.that_str(extra_res["resolution_marker_exprs"][extra_res["resolution_marker_exprs"][opt_k]["marker"]]).contains("linux")

    # 4. Single-specifier conflicted edge referencing an orthogonal conflict set keeps its variant marker.
    ortho_lock = _lock(
        [
            _vpkg(
                "root",
                dev_deps = {"cpu": [_dep("lib")], "cuda": []},
                opt_deps = {"a": [], "b": [_dep("pkg", "2.0")]},
            ),
            _pkg("lib", "0.1.0", source = {"editable": "lib"}, deps = [_dep("pkg", "1.0", marker = "extra == 'extra-4-root-a'")]),
            _pkg("pkg", "1.0", wheels = [_whl("pkg-1.0-py3-none-any.whl", "p1")]),
            _pkg("pkg", "2.0", wheels = [_whl("pkg-2.0-py3-none-any.whl", "p2")]),
        ],
        conflicts = [
            [{"package": "root", "group": "cpu"}, {"package": "root", "group": "cuda"}],
            [{"package": "root", "extra": "a"}, {"package": "root", "extra": "b"}],
        ],
    )
    ortho_res = translate_uv(
        _project(name = "root"),
        ortho_lock,
        _lock_model(projects = ["root"], dependency_groups = ["default", "group:cpu", "group:cuda", "optional:a", "optional:b"]),
    )
    ortho_pins = ortho_res["pins"]["pkg"]
    ortho_exprs = ortho_res["resolution_marker_exprs"]
    cpu_keys = [k for k, v in ortho_pins.items() if v == "pkg@1.0"]
    env.expect.that_collection(cpu_keys).has_size(1)
    env.expect.that_str(ortho_exprs[cpu_keys[0]]["variant"]).equals("group_root_cpu")
    env.expect.that_str(ortho_exprs[ortho_exprs[cpu_keys[0]]["marker"]]).equals("extra == '__variant_extra_root_a'")
    env.expect.that_str(ortho_pins["extra_root_b"]).equals("pkg@2.0")

    # 5. Two simultaneous repo_pins jointly prune an OR-ed edge referencing rivals from both sets.
    dual_pin_lock = _lock(
        [
            _vpkg("root", dev_deps = {"cpu": [], "cuda": []}, opt_deps = {"a": [], "b": []}),
            _pkg("lib", "0.1.0", source = {"editable": "lib"}, deps = [
                _dep("only-other", "1.0", marker = "extra == 'group-4-root-cuda' or extra == 'extra-4-root-b'"),
            ]),
            _pkg("only-other", "1.0", wheels = [_whl("only_other-1.0-py3-none-any.whl", "o1")]),
        ],
        conflicts = [
            [{"package": "root", "group": "cpu"}, {"package": "root", "group": "cuda"}],
            [{"package": "root", "extra": "a"}, {"package": "root", "extra": "b"}],
        ],
    )
    dual_pin_res = translate_uv(
        _project(name = "root"),
        dual_pin_lock,
        _lock_model(projects = ["*"], dependency_groups = ["default", "group:cpu", "optional:a"]),
    )
    env.expect.that_collection(dual_pin_res["pins"].keys()).not_contains("only-other")

    # 6. Cross-repo marker disambiguation: two repos sharing a `{package = "root"}` constraint
    # with distinct markers on the same forked version produce distinct marker keys.
    cross_repo_lock = _lock(
        [
            _vpkg(
                "root",
                deps = [_dep("torch", "2.9.1", marker = "sys_platform == 'darwin'")],
                dev_deps = {"dev": [_dep("torch", "2.9.1", marker = "sys_platform == 'linux'")]},
            ),
            _vpkg("other", deps = [_dep("torch", "2.9.1+cpu", marker = "sys_platform == 'linux'")]),
            _pkg("torch", "2.9.1", markers = ["sys_platform == 'darwin' or sys_platform == 'linux'"], wheels = [_whl("torch-2.9.1-py3-none-any.whl", "t1")]),
            _pkg("torch", "2.9.1+cpu", markers = ["sys_platform == 'linux'"], wheels = [_whl("torch-2.9.1%2Bcpu-py3-none-any.whl", "t2")]),
        ],
        conflicts = [[{"package": "root"}, {"package": "other"}]],
    )
    repo_a = translate_uv(_project(name = "root"), cross_repo_lock, _lock_model(projects = ["root"], dependency_groups = ["default"]))
    repo_b = translate_uv(_project(name = "root"), cross_repo_lock, _lock_model(projects = ["root"], dependency_groups = ["group:dev"]))
    key_a = repo_a["pins"]["torch"].keys()[0]
    key_b = repo_b["pins"]["torch"].keys()[0]
    env.expect.that_bool(key_a != key_b).equals(True)
    env.expect.that_bool(repo_a["resolution_marker_exprs"][key_a]["marker"] != repo_b["resolution_marker_exprs"][key_b]["marker"]).equals(True)

    # 7. Unpinned multi-hop local chain with contradictory conflict markers prunes the phantom pin,
    # and an unversioned forked `pkg[extra]` dep expands and prunes variant-gated forks.
    chain_extra_lock = _lock(
        [
            _vpkg("root", dev_deps = {"cpu": [], "cuda": []}),
            _pkg("lib-a", "0.1.0", source = {"editable": "a"}, deps = [
                _dep("lib-b", marker = "extra == 'group-4-root-cpu'"),
                _dep("forkpkg", extra = ["opt"]),
            ]),
            _pkg("lib-b", "0.1.0", source = {"editable": "b"}, deps = [
                _dep("phantom", "1.0", marker = "extra == 'group-4-root-cuda'"),
            ]),
            _pkg("phantom", "1.0", wheels = [_whl("phantom-1.0-py3-none-any.whl", "ph1")]),
            _pkg("forkpkg", "1.0", markers = ["extra == 'group-4-root-cpu'"], wheels = [_whl("forkpkg-1.0-py3-none-any.whl", "f1")], opt_deps = {"opt": []}),
            _pkg("forkpkg", "2.0", markers = ["extra == 'group-4-root-cuda'"], wheels = [_whl("forkpkg-2.0-py3-none-any.whl", "f2")], opt_deps = {"opt": []}),
        ],
        conflicts = [[{"package": "root", "group": "cpu"}, {"package": "root", "group": "cuda"}]],
    )
    unpinned_res = translate_uv(_project(name = "lib-a"), chain_extra_lock, _lock_model(projects = ["lib-a"]))
    env.expect.that_collection(unpinned_res["pins"].keys()).not_contains("phantom")
    env.expect.that_collection(unpinned_res["pins"]["forkpkg[opt]"].values()).contains_exactly(["forkpkg[opt]@1.0", "forkpkg[opt]@2.0"])
    cpu_extra_res = translate_uv(_project(name = "root"), chain_extra_lock, _lock_model(projects = ["*"], dependency_groups = ["default", "group:cpu"]))
    env.expect.that_collection(cpu_extra_res["pins"].keys()).not_contains("phantom")
    env.expect.that_dict(cpu_extra_res["pins"]["forkpkg[opt]"]).contains_exactly({"res_forkpkg_1_0": "forkpkg[opt]@1.0"})

def _test_uv_local_member_edge_cases(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_local_member_edge_cases_impl)

# buildifier: disable=unused-variable
def _test_uv_multi_source_same_version_impl(env, target):
    """Verify same (name, version) packages from distinct sources stay separate end-to-end."""

    # 0. Key parsing/formatting helpers preserve ~tag with and without extras.
    parsed = parse_package_key("torch[opt]@2.9.1~abcd1234")
    env.expect.that_str(parsed.name).equals("torch")
    env.expect.that_str(parsed.extra).equals("opt")
    env.expect.that_str(parsed.version).equals("2.9.1")
    env.expect.that_str(parsed.tag).equals("abcd1234")
    env.expect.that_str(format_package_key("torch", "2.9.1", extra = "opt", tag = "abcd1234")).equals("torch[opt]@2.9.1~abcd1234")
    env.expect.that_str(base_package_key("torch[opt]@2.9.1~abcd1234")).equals("torch@2.9.1~abcd1234")
    env.expect.that_dict(base_packages_with_extras({"torch@2.9.1~abcd1234": {}, "torch[opt]@2.9.1~abcd1234": {}})).contains_exactly({
        "torch@2.9.1~abcd1234": ["torch[opt]@2.9.1~abcd1234"],
    })

    # 1. Two registries ship torch==2.9.1 with the same macOS wheel filename and
    #    different sha256 hashes + deps, plus a non-colliding torch==2.9.1+cpu.
    cpu_reg = {"registry": "https://download.pytorch.org/whl/cpu"}
    pypi_reg = {"registry": "https://pypi.org/simple"}
    lock = _lock(
        [
            _vpkg(
                "root",
                deps = [_dep("lib", "0.1.0", source = {"editable": "lib"})],
                dev_deps = {
                    "cpu": [
                        _dep("torch", "2.9.1", source = cpu_reg, marker = "sys_platform == 'darwin' and extra == 'group-4-root-cpu'"),
                        _dep("torch", "2.9.1+cpu", source = cpu_reg, marker = "sys_platform == 'linux' and extra == 'group-4-root-cpu'"),
                    ],
                    "cuda": [
                        _dep("torch", "2.9.1", source = pypi_reg, marker = "extra == 'group-4-root-cuda'"),
                    ],
                },
            ),
            _pkg(
                "lib",
                "0.1.0",
                source = {"editable": "lib"},
                deps = [
                    _dep("torch", "2.9.1", source = cpu_reg, marker = "sys_platform == 'darwin' and extra == 'group-4-root-cpu'"),
                    _dep("torch", "2.9.1+cpu", source = cpu_reg, marker = "sys_platform == 'linux' and extra == 'group-4-root-cpu'"),
                    _dep("torch", "2.9.1", source = pypi_reg, marker = "extra != 'group-4-root-cpu'"),
                ],
            ),
            _pkg(
                "torch",
                "2.9.1",
                source = cpu_reg,
                markers = ["sys_platform == 'darwin' and extra == 'group-4-root-cpu'"],
                wheels = [_whl("torch-2.9.1-cp312-none-macosx_11_0_arm64.whl", "cpu_mac_sha")],
            ),
            _pkg(
                "torch",
                "2.9.1+cpu",
                source = cpu_reg,
                markers = ["sys_platform == 'linux' and extra == 'group-4-root-cpu'"],
                wheels = [_whl("torch-2.9.1%2Bcpu-cp312-cp312-manylinux_2_28_x86_64.whl", "cpu_lin_sha")],
            ),
            _pkg(
                "torch",
                "2.9.1",
                source = pypi_reg,
                markers = ["extra != 'group-4-root-cpu'"],
                deps = [_dep("nvidia-nccl", "2.0.0", source = pypi_reg, marker = "sys_platform == 'linux'")],
                wheels = [
                    _whl("torch-2.9.1-cp312-none-macosx_11_0_arm64.whl", "pypi_mac_sha"),
                    _whl("torch-2.9.1-cp312-cp312-manylinux_2_28_x86_64.whl", "pypi_lin_sha"),
                ],
            ),
            _pkg(
                "nvidia-nccl",
                "2.0.0",
                source = pypi_reg,
                wheels = [_whl("nvidia_nccl-2.0.0-py3-none-manylinux_2_28_x86_64.whl", "nccl_sha")],
            ),
        ],
        conflicts = [[{"package": "root", "group": "cpu"}, {"package": "root", "group": "cuda"}]],
    )

    # Non-colliding version stays plain; colliding 2.9.1 entries get distinct ~<8hex> tags and sources.
    res = translate_uv(_project(name = "root"), lock, _lock_model(projects = ["*"], dependency_groups = ["default", "group:cpu", "group:cuda"]))
    env.expect.that_bool("torch@2.9.1+cpu" in res["packages"]).equals(True)
    env.expect.that_bool("source" in res["packages"]["torch@2.9.1+cpu"]).equals(False)
    env.expect.that_bool("torch@2.9.1" in res["packages"]).equals(False)

    torch_291_keys = sorted([k for k in res["packages"].keys() if k.startswith("torch@2.9.1~")])
    env.expect.that_collection(torch_291_keys).has_size(2)
    by_source = {res["packages"][k]["source"]: k for k in torch_291_keys}
    cpu_key = by_source["https://download.pytorch.org/whl/cpu"]
    pypi_key = by_source["https://pypi.org/simple"]

    # Wheels and deps are isolated per source (identical macOS wheel filenames do NOT collide).
    env.expect.that_collection([f["sha256"] for f in res["packages"][cpu_key]["files"]]).contains_exactly(["cpu_mac_sha"])
    env.expect.that_collection([f["sha256"] for f in res["packages"][pypi_key]["files"]]).contains_exactly(["pypi_mac_sha", "pypi_lin_sha"])
    env.expect.that_collection(res["packages"][cpu_key]["dependencies"]).contains_exactly([])
    env.expect.that_collection([d["name"] for d in res["packages"][pypi_key]["dependencies"]]).contains_exactly(["nvidia-nccl"])

    # Pins select the right tagged key per repo (cpu-only, lib-only, combined).
    cpu_only = translate_uv(_project(name = "root"), lock, _lock_model(projects = ["*"], dependency_groups = ["default", "group:cpu"]))
    env.expect.that_collection(cpu_only["pins"]["torch"].values()).contains_exactly([cpu_key, "torch@2.9.1+cpu"])
    lib_only = translate_uv(_project(name = "lib"), lock, _lock_model(projects = ["lib"], dependency_groups = ["default"]))
    env.expect.that_collection(lib_only["pins"]["torch"].values()).contains_exactly([cpu_key, "torch@2.9.1+cpu", pypi_key])

    # Downstream resolve() + render_lock_bzl() succeed with zero duplicate-wheel collisions.
    resolved = resolve(res)
    repo_map = {fk: "@pypi_{}//:file".format(i) for i, fk in enumerate(sorted(resolved.remote_files.keys()))}
    rendered = render_lock_bzl(
        {
            "packages": resolved.packages,
            "pins": resolved.pins,
            "variants": resolved.variants,
            "resolution_marker_exprs": resolved.resolution_marker_exprs,
        },
        repo_map,
        "ws__pkgs",
    )
    env.expect.that_str(rendered).contains(cpu_key)
    env.expect.that_str(rendered).contains(pypi_key)

    # 2. Local editable member and registry package sharing (name, version) stay distinct.
    local_vs_reg_lock = _lock([
        _vpkg("root", deps = [
            _dep("foo", "1.0.0", source = {"editable": "foo"}),
            _dep("consumer", "1.0.0", source = pypi_reg),
        ]),
        _pkg("foo", "1.0.0", source = {"editable": "foo"}, deps = [_dep("helper", "1.0.0", source = pypi_reg)]),
        _pkg("foo", "1.0.0", source = pypi_reg, wheels = [_whl("foo-1.0.0-py3-none-any.whl", "foo_reg")]),
        _pkg("consumer", "1.0.0", source = pypi_reg, deps = [_dep("foo", "1.0.0", source = pypi_reg)], wheels = [_whl("consumer-1.0.0-py3-none-any.whl", "c1")]),
        _pkg("helper", "1.0.0", source = pypi_reg, wheels = [_whl("helper-1.0.0-py3-none-any.whl", "h1")]),
    ])
    lvr = translate_uv(_project(name = "root"), local_vs_reg_lock, _lock_model(projects = ["root"]))
    reg_foo_keys = [k for k in lvr["packages"].keys() if k.startswith("foo@1.0.0~")]
    env.expect.that_collection(reg_foo_keys).has_size(1)
    env.expect.that_str(lvr["packages"][reg_foo_keys[0]]["source"]).equals("https://pypi.org/simple")
    env.expect.that_str(lvr["pins"]["helper"]).equals("helper@1.0.0")
    env.expect.that_str(lvr["packages"]["consumer@1.0.0"]["dependencies"][0]["key"]).equals(reg_foo_keys[0])

    # 3. Extras stay bound to their own source, and an un-sourced forked dep expands both sources.
    git_a = {"git": "https://example.com/pkg.git#aaaa1111"}
    git_b = {"git": "https://example.com/pkg.git#bbbb2222"}
    git_lock = _lock([
        _vpkg("root", deps = [
            _dep("pkg", "1.0.0", extra = ["opt"], source = git_a),
            _dep("unsourced", "1.0.0", source = pypi_reg),
        ]),
        _pkg("unsourced", "1.0.0", source = pypi_reg, deps = [_dep("pkg", "1.0.0")], wheels = [_whl("unsourced-1.0.0-py3-none-any.whl", "u1")]),
        _pkg("pkg", "1.0.0", source = git_a, markers = ["sys_platform == 'linux'"], opt_deps = {"opt": []}),
        _pkg("pkg", "1.0.0", source = git_b, markers = ["sys_platform == 'darwin'"], opt_deps = {"opt": []}),
    ])
    git_res = translate_uv(_project(name = "root"), git_lock, _lock_model(projects = ["root"]))
    pkg_base_by_src = {
        git_res["packages"][k]["source"]: k
        for k in git_res["packages"].keys()
        if k.startswith("pkg@1.0.0~")
    }
    git_a_base = pkg_base_by_src["https://example.com/pkg.git#aaaa1111"]
    git_b_base = pkg_base_by_src["https://example.com/pkg.git#bbbb2222"]
    git_a_opt = git_res["pins"]["pkg[opt]"]
    if type(git_a_opt) == "dict":
        git_a_opt = git_a_opt.values()[0]
    env.expect.that_str(base_package_key(git_a_opt)).equals(git_a_base)
    env.expect.that_str(git_res["packages"][git_a_opt]["dependencies"][0]["key"]).equals(git_a_base)
    unsourced_dep_keys = [d["key"] for d in git_res["packages"]["unsourced@1.0.0"]["dependencies"]]
    env.expect.that_collection(unsourced_dep_keys).contains_exactly([git_a_base, git_b_base])

    # 4. Empty extra on one source falls back to its base package even when another source defines optional-dependencies.
    asym_extra_lock = _lock([
        _vpkg("root", deps = [
            _dep("pkg", "1.0.0", extra = ["opt"], source = git_b),
            _dep("consumer", "1.0.0", source = pypi_reg),
        ]),
        _pkg(
            "consumer",
            "1.0.0",
            source = pypi_reg,
            deps = [_dep("pkg", "1.0.0", extra = ["opt"], source = git_b)],
            wheels = [_whl("consumer-1.0.0-py3-none-any.whl", "c1")],
        ),
        _pkg("pkg", "1.0.0", source = git_a, opt_deps = {"opt": [_dep("extra-dep", "1.0.0", source = pypi_reg)]}),
        _pkg("pkg", "1.0.0", source = git_b),
        _pkg("extra-dep", "1.0.0", source = pypi_reg, wheels = [_whl("extra_dep-1.0.0-py3-none-any.whl", "e1")]),
    ])
    asym_res = translate_uv(_project(name = "root"), asym_extra_lock, _lock_model(projects = ["root"]))
    asym_b_base = [
        k
        for k, p in asym_res["packages"].items()
        if k.startswith("pkg@1.0.0~") and p.get("source") == "https://example.com/pkg.git#bbbb2222"
    ][0]
    env.expect.that_str(base_package_key(asym_res["pins"]["pkg[opt]"])).equals(asym_b_base)
    env.expect.that_str(asym_res["packages"]["consumer@1.0.0"]["dependencies"][0]["key"]).equals(asym_b_base)
    asym_resolved = resolve(asym_res)
    env.expect.that_collection([md["key"] for md in asym_resolved.packages[asym_res["pins"]["pkg[opt]"]]["marker_dependencies"]]).contains_exactly([asym_b_base])

def _test_uv_multi_source_same_version(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_multi_source_same_version_impl)

# buildifier: disable=unused-variable
def _test_discover_uv_all_members_impl(env, target):
    """Editable members and virtual members with deps are discovered; dependency-free virtual roots are skipped."""
    lock_toml = "\n".join([
        "version = 1",
        "[[package]]",
        'name = "ws-root"',
        'version = "0.1.0"',
        'source = { virtual = "." }',
        "[[package]]",
        'name = "app-a"',
        'version = "0.1.0"',
        'source = { editable = "apps/a" }',
        "[[package]]",
        'name = "virt-b"',
        'version = "0.1.0"',
        'source = { virtual = "apps/b" }',
        'dependencies = [{ name = "six" }]',
        "[[package]]",
        'name = "six"',
        'version = "1.17.0"',
        'source = { registry = "https://pypi.org/simple" }',
    ])
    mctx = struct(
        path = lambda _lbl: struct(exists = True),
        read = lambda _path: lock_toml,
    )
    members = discover_uv_all_members(mctx, Label("//:uv.lock"))
    env.expect.that_collection([(m.name, m.path) for m in members]).contains_exactly([
        ("app-a", "apps/a"),
        ("virt-b", "apps/b"),
    ]).in_order()

def _test_discover_uv_all_members(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_discover_uv_all_members_impl)

# buildifier: disable=unused-variable
def _test_uv_versionless_editable_package_impl(env, target):
    """Editable packages with dynamic versioning (omitted `version` in uv.lock) translate and expand deps."""
    pypi = {"registry": "https://pypi.org/simple"}
    lock = _lock(
        packages = [
            {
                "name": "app",
                "version": "0.1.0",
                "source": {"editable": "."},
                "dependencies": [{"name": "dyn-lib", "extra": ["feat"]}],
            },
            {
                "name": "dyn-lib",
                "source": {"editable": "libs/dyn"},
                "dependencies": [_dep("core", "1.0.0")],
                "optional-dependencies": {
                    "feat": [_dep("extra-dep", "2.0.0")],
                },
            },
            _pkg("core", "1.0.0", source = pypi, wheels = [_whl("core-1.0.0-py3-none-any.whl", "c1")]),
            _pkg("extra-dep", "2.0.0", source = pypi, wheels = [_whl("extra_dep-2.0.0-py3-none-any.whl", "e1")]),
        ],
    )
    raw = translate_uv(_project(name = "app"), lock, _lock_model(projects = ["app"]))
    env.expect.that_dict(raw["pins"]).contains_exactly({
        "core": "core@1.0.0",
        "extra-dep": "extra-dep@2.0.0",
    })
    env.expect.that_collection(raw["packages"].keys()).contains_exactly([
        "core@1.0.0",
        "extra-dep@2.0.0",
    ])

def _test_uv_versionless_editable_package(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_versionless_editable_package_impl)

def _uv_versionless_non_local_subject_impl(_ctx):
    pypi = {"registry": "https://pypi.org/simple"}
    lock = _lock(
        packages = [
            {
                "name": "app",
                "version": "0.1.0",
                "source": {"editable": "."},
                "dependencies": [{"name": "broken"}],
            },
            {
                "name": "broken",
                "source": pypi,
                "wheels": [_whl("broken-1.0.0-py3-none-any.whl", "b1")],
            },
        ],
    )
    translate_uv(_project(name = "app"), lock, _lock_model(projects = ["app"]))
    return []

_uv_versionless_non_local_subject = rule(implementation = _uv_versionless_non_local_subject_impl)

def _test_uv_versionless_non_local_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("Package 'broken' in uv.lock is missing a 'version' field"),
    )

def _test_uv_versionless_non_local_fails(name):
    util.helper_target(_uv_versionless_non_local_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        expect_failure = True,
        impl = _test_uv_versionless_non_local_fails_impl,
    )

# buildifier: disable=unused-variable
def _test_is_external_member_path_impl(env, target):
    """Windows drive letters, UNC/POSIX absolutes, and parent escapes are external; relative paths with colons stay internal."""
    cases = [
        ("C:\\libs\\ext", True),
        ("C:\\..\\ext", True),
        ("C:/foo/../../ext", True),
        ("c:rel", True),
        ("/abs/pkg", True),
        ("\\\\server\\share\\pkg", True),
        ("//server/share/pkg", True),
        ("../ext", True),
        ("..", True),
        ("..\\ext", True),
        ("a/../../ext", True),
        ("./a:b", False),
        ("1:2/pkg", False),
        ("packages/sub", False),
        (".", False),
        ("", False),
        ("..foo", False),
    ]
    for path, expected in cases:
        env.expect.where(path = path).that_bool(is_external_member_path(path)).equals(expected)

def _test_is_external_member_path(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_is_external_member_path_impl)

# buildifier: disable=unused-variable
def _test_uv_manifest_members_and_external_editables_impl(env, target):
    """[manifest].members and parent-escaping editable paths filter workspace members while keeping local dep expansion."""

    # 1. With [manifest].members: only listed members are discovered; non-member editables are skipped.
    manifest_toml = "\n".join([
        "version = 1",
        "[manifest]",
        'members = ["ws-root", "app-a"]',
        "[[package]]",
        'name = "ws-root"',
        'version = "0.1.0"',
        'source = { virtual = "." }',
        "[[package]]",
        'name = "app-a"',
        'version = "0.1.0"',
        'source = { editable = "apps/a" }',
        "[[package]]",
        'name = "vendor-lib"',
        'version = "0.1.0"',
        'source = { editable = "vendor/lib" }',
        "[[package]]",
        'name = "ext-lib"',
        'version = "0.1.0"',
        'source = { editable = "../../libs/ext" }',
    ])
    mctx_manifest = struct(
        path = lambda _lbl: struct(exists = True),
        read = lambda _path: manifest_toml,
    )
    members = discover_uv_all_members(mctx_manifest, Label("//:uv.lock"))
    env.expect.that_collection([(m.name, m.path) for m in members]).contains_exactly([
        ("app-a", "apps/a"),
    ]).in_order()

    # 2. Without [manifest].members: external (../, absolute, drive-letter) editables and non-string
    #    editable/virtual flags are excluded.
    standalone_toml = "\n".join([
        "version = 1",
        "[[package]]",
        'name = "app"',
        'version = "0.1.0"',
        'source = { editable = "." }',
        "[[package]]",
        'name = "ext-rel"',
        'version = "0.1.0"',
        'source = { editable = "../../libs/ext" }',
        "[[package]]",
        'name = "ext-abs"',
        'version = "0.1.0"',
        'source = { editable = "/opt/ext" }',
        "[[package]]",
        'name = "ext-win"',
        'version = "0.1.0"',
        'source = { editable = "..\\\\ext" }',
        "[[package]]",
        'name = "bool-editable"',
        'version = "0.1.0"',
        "source = { editable = true }",
        "[[package]]",
        'name = "bool-virtual"',
        'version = "0.1.0"',
        "source = { virtual = true }",
    ])
    mctx_standalone = struct(
        path = lambda _lbl: struct(exists = True),
        read = lambda _path: standalone_toml,
    )
    standalone_members = discover_uv_all_members(mctx_standalone, Label("//:uv.lock"))
    env.expect.that_collection([(m.name, m.path) for m in standalone_members]).contains_exactly([
        ("app", "."),
    ]).in_order()

    # 3. translate_uv with projects=["*"] excludes external editables and non-string
    #    editable/virtual values from target projects while expanding transitive deps.
    pypi = {"registry": "https://pypi.org/simple"}
    lock = _lock(
        packages = [
            {
                "name": "app",
                "version": "0.1.0",
                "source": {"editable": "."},
                "dependencies": [_dep("ext-used", "0.1.0")],
            },
            {
                "name": "ext-used",
                "version": "0.1.0",
                "source": {"editable": "../../libs/used"},
                "dependencies": [_dep("from-used", "1.0.0")],
            },
            {
                "name": "ext-unused",
                "version": "0.1.0",
                "source": {"editable": "../../libs/unused"},
                "dependencies": [_dep("from-unused", "1.0.0")],
            },
            {
                "name": "bool-editable",
                "version": "0.1.0",
                "source": {"editable": True},
                "dependencies": [_dep("from-unused", "1.0.0")],
            },
            {
                "name": "bool-virtual",
                "version": "0.1.0",
                "source": {"virtual": True},
                "dependencies": [_dep("from-unused", "1.0.0")],
            },
            _pkg("from-used", "1.0.0", source = pypi, wheels = [_whl("from_used-1.0.0-py3-none-any.whl", "u1")]),
            _pkg("from-unused", "1.0.0", source = pypi, wheels = [_whl("from_unused-1.0.0-py3-none-any.whl", "u2")]),
        ],
    )
    raw = translate_uv(_project(name = "app"), lock, _lock_model(projects = ["*"]))
    env.expect.that_dict(raw["pins"]).contains_exactly({"from-used": "from-used@1.0.0"})

    # 4. translate_uv with [manifest].members discovers listed workspace members even when
    #    pyproject.toml names a different root project, and ignores unlisted local editables.
    manifest_lock = _lock(
        packages = [
            {
                "name": "app-a",
                "version": "0.1.0",
                "source": {"editable": "apps/a"},
                "dependencies": [_dep("from-a", "1.0.0")],
            },
            {
                "name": "member-b",
                "version": "0.1.0",
                "source": {"editable": "../sibling/member-b"},
                "dependencies": [_dep("from-b", "1.0.0")],
            },
            {
                "name": "vendor-unused",
                "version": "0.1.0",
                "source": {"editable": "vendor/unused"},
                "dependencies": [_dep("from-vendor", "1.0.0")],
            },
            _pkg("from-a", "1.0.0", source = pypi, wheels = [_whl("from_a-1.0.0-py3-none-any.whl", "m1")]),
            _pkg("from-b", "1.0.0", source = pypi, wheels = [_whl("from_b-1.0.0-py3-none-any.whl", "m2")]),
            _pkg("from-vendor", "1.0.0", source = pypi, wheels = [_whl("from_vendor-1.0.0-py3-none-any.whl", "m3")]),
        ],
        manifest = {"members": ["app-a", "member-b"]},
    )
    manifest_raw = translate_uv(_project(name = "ws-root"), manifest_lock, _lock_model(projects = ["*"]))
    env.expect.that_dict(manifest_raw["pins"]).contains_exactly({
        "from-a": "from-a@1.0.0",
        "from-b": "from-b@1.0.0",
    })

def _test_uv_manifest_members_and_external_editables(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_manifest_members_and_external_editables_impl)

# buildifier: disable=unused-variable
def _test_uv_workspace_cache_and_resolve_workspace_parity_impl(env, target):
    """Hoisted UV workspace translation and resolve_workspace match standalone per-member runs byte-for-byte."""
    pypi = {"registry": "https://pypi.org/simple"}
    lock = _lock(
        packages = [
            {
                "name": "app-a",
                "version": "0.1.0",
                "source": {"editable": "apps/a"},
                "dependencies": [
                    _dep("shared-lib", "0.1.0", source = {"editable": "libs/shared"}),
                    _dep("linux-only", "1.0.0", marker = "sys_platform == 'linux'"),
                ],
                "dev-dependencies": {
                    "cpu": [_dep("accel", "1.0.0", marker = "extra == 'group-5-app-a-cpu'")],
                    "cuda": [_dep("accel", "2.0.0", marker = "extra == 'group-5-app-a-cuda'")],
                },
            },
            {
                "name": "app-b",
                "version": "0.1.0",
                "source": {"editable": "apps/b"},
                "dependencies": [
                    _dep("linux-only", "1.0.0"),
                    _dep("extra-pkg", "1.0.0", extra = ["opt"]),
                ],
                "dev-dependencies": {"test": [_dep("pytest", "8.0.0")]},
            },
            _pkg(
                "shared-lib",
                "0.1.0",
                source = {"editable": "libs/shared"},
                deps = [_dep("core", "1.0.0")],
            ),
            _pkg(
                "accel",
                "1.0.0",
                source = pypi,
                markers = ["extra == 'group-5-app-a-cpu'"],
                wheels = [_whl("accel-1.0.0-py3-none-any.whl", "a1")],
            ),
            _pkg(
                "accel",
                "2.0.0",
                source = pypi,
                markers = ["extra == 'group-5-app-a-cuda'"],
                wheels = [_whl("accel-2.0.0-py3-none-any.whl", "a2")],
            ),
            _pkg("linux-only", "1.0.0", source = pypi, wheels = [_whl("linux_only-1.0.0-py3-none-any.whl", "l1")]),
            _pkg("core", "1.0.0", source = pypi, wheels = [_whl("core-1.0.0-py3-none-any.whl", "c1")]),
            _pkg("extra-pkg", "1.0.0", source = pypi, wheels = [_whl("extra_pkg-1.0.0-py3-none-any.whl", "e1")]),
            _pkg("pytest", "8.0.0", source = pypi, wheels = [_whl("pytest-8.0.0-py3-none-any.whl", "p1")]),
        ],
        conflicts = [[
            {"package": "app-a", "group": "cpu"},
            {"package": "app-a", "group": "cuda"},
        ]],
    )
    proj_a = _project(name = "app-a", uv_default_groups = ["cpu"])
    proj_b = _project(name = "app-b")
    proj_root = _project(name = "ws-root")

    cases = [
        ("app_a_both", proj_a, _lock_model(projects = ["app-a"], dependency_groups = ["default", "group:cpu", "group:cuda"]), False, False, False),
        ("app_a_cpu", proj_a, _lock_model(projects = ["app-a"], dependency_groups = ["default", "group:cpu"]), False, False, False),
        ("app_b", proj_b, _lock_model(projects = ["app-b"], dependency_groups = ["default", "group:test"], testonly_groups = ["group:test"], non_testonly_groups = ["default"]), True, True, False),
        ("ws__build", proj_root, _lock_model(projects = ["*"], dependency_groups = ["*"], is_build_tools_repo = True), True, False, True),
    ]

    ws_cache = {}
    cached_raw = {}
    member_entries = []
    for repo_name, proj, model, inc_trans, trans_testonly, ungated in cases:
        cached = translate_uv(proj, lock, model, workspace_cache = ws_cache)
        cached_raw[repo_name] = cached
        member_entries.append(struct(
            name = repo_name,
            lock_model_data = cached,
            include_transitive = inc_trans,
            transitive_testonly = trans_testonly,
            ungated_fallback = ungated,
        ))

    env.expect.that_bool(ws_cache.get("shared_packages", False)).equals(True)
    env.expect.that_collection(ws_cache.get("marker_parse_cache", {}).keys()).contains_at_least([
        "extra == '__variant_group_app-a_cpu'",
        "extra == '__variant_group_app-a_cuda'",
    ])

    # Compare only after all cached translations finish so any cross-repo mutation
    # of an earlier repo's returned dicts or lists is caught.
    standalone_raw = {}
    for repo_name, proj, model, _inc_trans, _trans_testonly, _ungated in cases:
        standalone = translate_uv(proj, lock, model)
        env.expect.that_str(json.encode(cached_raw[repo_name])).equals(json.encode(standalone))
        standalone_raw[repo_name] = standalone

    annotations = {"core": {"wheel_library_tags": ["my-tag"]}}
    hoisted_resolved = resolve_workspace(
        member_entries,
        annotations_data = annotations,
        shared_packages = True,
    )
    for repo_name, _proj, _model, inc_trans, trans_testonly, ungated in cases:
        standalone_res = resolve(
            standalone_raw[repo_name],
            annotations_data = annotations,
            include_transitive = inc_trans,
            transitive_testonly = trans_testonly,
            ungated_fallback = ungated,
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

def _test_uv_workspace_cache_and_resolve_workspace_parity(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_workspace_cache_and_resolve_workspace_parity_impl)

# --- Test suite ---

def uv_translator_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_uv_minimal_lock,
            _test_uv_distribution_compat,
            _test_uv_multiple_packages_with_deps,
            _test_uv_platform_specific_deps,
            _test_uv_virtual_package,
            _test_uv_editable_package,
            _test_uv_wheels_with_urls,
            _test_uv_no_static_urls,
            _test_uv_resolution_markers,
            _test_uv_workspace_members,
            _test_uv_dev_dependencies_pep735,
            _test_uv_optional_dependencies_extras,
            _test_uv_extra_variants,
            _test_uv_group_variants,
            _test_uv_no_variants,
            _test_uv_dependencies_with_extra,
            _test_uv_unconditional_pins_are_bare,
            _test_uv_resolution_marker_fork_conditional_pins,
            _test_uv_resolution_marker_single_version_no_fork,
            _test_uv_resolution_marker_multi_marker_or,
            _test_uv_resolution_marker_fork_optional_group,
            _test_uv_testonly_groups,
            _test_uv_testonly_shared_dep_not_testonly,
            _test_uv_testonly_wildcard_with_override,
            _test_uv_testonly_wildcard_overrides_earlier,
            _test_uv_root_dependency_markers,
            _test_uv_url_filenames_decoded,
            _test_uv_url_and_git_sources,
            _test_uv_virtual_and_directory_members,
            _test_uv_local_member_deps_keep_forks,
            _test_uv_variants_scoped_to_project,
            _test_uv_same_named_groups_across_members,
            _test_uv_auto_pin,
            _test_uv_auto_pin_empty_extra,
            _test_uv_auto_pin_overlapping_sets,
            _test_uv_repo_defaults,
            _test_read_project_dict,
            _test_uv_project_conflicts,
            _test_uv_project_conflict_mixed_set,
            _test_uv_project_conflict_edge_split,
            _test_uv_project_conflict_redundant_edges,
            _test_uv_project_conflict_asymmetric_edges,
            _test_uv_local_version_exact_matching,
            _test_uv_issue_1510_verbatim_lock,
            _test_fold_variant_marker,
            _test_fold_variant_marker_memoization,
            _test_pin_marker_folder_and_shared_caches,
            _test_uv_local_member_conflict_markers,
            _test_uv_local_member_chain_and_empty_pin_pruning,
            _test_uv_asymmetric_fork_with_independent_member,
            _test_uv_testonly_local_member_expansion,
            _test_uv_local_member_edge_cases,
            _test_uv_multi_source_same_version,
            _test_discover_uv_all_members,
            _test_uv_versionless_editable_package,
            _test_uv_versionless_non_local_fails,
            _test_is_external_member_path,
            _test_uv_manifest_members_and_external_editables,
            _test_uv_workspace_cache_and_resolve_workspace_parity,
        ],
    )
