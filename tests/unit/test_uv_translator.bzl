"""Tests for the Starlark UV translator."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:uv_lock_model.bzl", "translate_uv")

def _lock_model(
        projects = ["*"],
        dependency_groups = ["default"],
        testonly_groups = [],
        non_testonly_groups = [],
        wildcard_testonly = False):
    return struct(
        projects = projects,
        dependency_groups = dependency_groups,
        testonly_groups = testonly_groups,
        non_testonly_groups = non_testonly_groups,
        wildcard_testonly = wildcard_testonly,
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

def _lock(packages, requires_python = ">=3.8", conflicts = None):
    d = {"version": 1, "requires-python": requires_python, "package": packages}
    if conflicts:
        d["conflicts"] = conflicts
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

def _dep(name, version = None, marker = None, extra = None):
    d = {"name": name}
    if version:
        d["version"] = version
    if marker:
        d["marker"] = marker
    if extra:
        d["extra"] = extra
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
    env.expect.that_collection(torch_pin.keys()).contains_at_least(["extra_cpu", "extra_cu124"])

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

# --- test_requires_python_propagation ---

# buildifier: disable=unused-variable
def _test_uv_requires_python_propagation_impl(env, target):
    project = _project(deps = ["a==1.0"])
    lock = _lock([
        _vpkg("my-app", deps = [_dep("a")]),
        _pkg("a", "1.0", wheels = [_whl("a-1.0-py3-none-any.whl", "a")], markers = ["python_full_version >= '3.10'"]),
    ], requires_python = ">=3.8")
    result = translate_uv(project, lock, _lock_model())
    env.expect.that_str(result.get("python_versions", "")).equals(">=3.8")
    pkg_a = result["packages"]["a@1.0"]
    env.expect.that_str(pkg_a.get("python_versions", "")).equals(">= 3.10")

def _test_uv_requires_python_propagation(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_uv_requires_python_propagation_impl)

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
    env.expect.that_str(numpy_pin["extra_science_res_numpy_2_3_4"]).equals("numpy@2.3.4")
    env.expect.that_str(numpy_pin["extra_science_res_numpy_2_3_3"]).equals("numpy@2.3.3")

    # Compound entries should store component info.
    exprs = result["resolution_marker_exprs"]
    compound_2_3_4 = exprs["extra_science_res_numpy_2_3_4"]
    env.expect.that_str(compound_2_3_4["variant"]).equals("extra_science")
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
            _test_uv_requires_python_propagation,
            _test_uv_unconditional_pins_are_bare,
            _test_uv_resolution_marker_fork_conditional_pins,
            _test_uv_resolution_marker_single_version_no_fork,
            _test_uv_resolution_marker_multi_marker_or,
            _test_uv_resolution_marker_fork_optional_group,
            _test_uv_testonly_groups,
            _test_uv_testonly_shared_dep_not_testonly,
            _test_uv_testonly_wildcard_with_override,
            _test_uv_testonly_wildcard_overrides_earlier,
        ],
    )
