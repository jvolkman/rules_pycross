"""Module docstring for tests."""

load("@rules_python//python:py_info.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo", "PycrossPackageInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private:proxy.bzl", "pycross_file_proxy", "pycross_library_proxy")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_library.bzl", "pycross_unsupported_wheel")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/rules:common_attrs.bzl", "get_unzipped_wheel", "group_tool_deps", "resolve_path_tools")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/rules:path_tool.bzl", "pycross_path_tool")

TestingInfo = provider(doc = "TestingInfo", fields = ["result", "site_packages"])

def _mock_pkg_impl(ctx):
    site_dir = ctx.actions.declare_directory(ctx.label.name + "_site")
    ctx.actions.run_shell(
        outputs = [site_dir],
        command = "mkdir -p \"$1\"",
        arguments = [site_dir.path],
        mnemonic = "MockSitePackages",
    )
    return [
        DefaultInfo(files = depset([site_dir])),
        PyInfo(transitive_sources = depset()),
        PycrossPackageInfo(package_name = ctx.attr.package_name),
        PycrossExtractedWheelInfo(site_packages = site_dir),
    ]

mock_pkg = rule(
    implementation = _mock_pkg_impl,
    attrs = {
        "package_name": attr.string(mandatory = True),
    },
    provides = [DefaultInfo, PyInfo],
)

# buildifier: disable=unused-variable
def _mock_other_impl(ctx):
    return []

mock_other = rule(
    implementation = _mock_other_impl,
)

def _test_rule_impl(ctx):
    dep1 = ctx.attr.dep1
    dep2 = ctx.attr.dep2
    dep3 = ctx.attr.dep3
    other = ctx.attr.other

    result = group_tool_deps([d for d in [dep1, dep2, dep3, other] if d != None])
    site_packages = {}
    for name, targets in result.items():
        site_packages[name] = get_unzipped_wheel(targets[0]).basename

    # Store result to be accessed by the test
    return [TestingInfo(result = result, site_packages = site_packages)]

group_tool_deps_subject = rule(
    implementation = _test_rule_impl,
    attrs = {
        "dep1": attr.label(),
        "dep2": attr.label(),
        "dep3": attr.label(),
        "other": attr.label(),
    },
)

# buildifier: disable=unused-variable
def _group_tool_deps_test_impl(env, target):
    result = target[TestingInfo].result

    env.expect.that_int(len(result)).equals(2)

    env.expect.that_int(len(result.get("pkg_a", []))).equals(2)
    env.expect.that_int(len(result.get("pkg_b", []))).equals(1)

def group_tool_deps_test(name):
    """Test group_tool_deps.

    Args:
        name: Name of the test
    """
    mock_pkg(name = name + "_dep1", package_name = "pkg_a")
    mock_pkg(name = name + "_dep2", package_name = "pkg_b")
    mock_pkg(name = name + "_dep3", package_name = "pkg_a")
    mock_other(name = name + "_other")

    group_tool_deps_subject(
        name = name + "_subject",
        dep1 = ":" + name + "_dep1",
        dep2 = ":" + name + "_dep2",
        dep3 = ":" + name + "_dep3",
        other = ":" + name + "_other",
    )

    analysis_test(
        name = name,
        target = ":" + name + "_subject",
        impl = _group_tool_deps_test_impl,
    )

# buildifier: disable=unused-variable
def _group_tool_deps_empty_impl(env, target):
    res = group_tool_deps([])
    env.expect.that_dict(res).contains_exactly({})

def _group_tool_deps_empty_test(name):
    group_tool_deps_subject(name = name + "_subject")
    analysis_test(name = name, target = ":" + name + "_subject", impl = _group_tool_deps_empty_impl)

# buildifier: disable=unused-variable
def _group_tool_deps_no_pkg_impl(env, target):
    res = target[TestingInfo].result
    env.expect.that_dict(res).contains_exactly({})

def _group_tool_deps_no_pkg_test(name):
    mock_other(name = name + "_other1")
    mock_other(name = name + "_other2")
    group_tool_deps_subject(
        name = name + "_subject",
        other = ":" + name + "_other1",
        dep1 = ":" + name + "_other2",
    )
    analysis_test(name = name, target = ":" + name + "_subject", impl = _group_tool_deps_no_pkg_impl)

# buildifier: disable=unused-variable
def _group_tool_deps_single_impl(env, target):
    res = target[TestingInfo].result
    env.expect.that_int(len(res)).equals(1)
    env.expect.that_int(len(res.get("pkg_a", []))).equals(1)

def _group_tool_deps_single_test(name):
    mock_pkg(name = name + "_dep1", package_name = "pkg_a")
    group_tool_deps_subject(
        name = name + "_subject",
        dep1 = ":" + name + "_dep1",
    )
    analysis_test(name = name, target = ":" + name + "_subject", impl = _group_tool_deps_single_impl)

# buildifier: disable=unused-variable
def _group_tool_deps_same_impl(env, target):
    res = target[TestingInfo].result
    env.expect.that_int(len(res)).equals(1)
    env.expect.that_int(len(res.get("pkg_a", []))).equals(3)

def _group_tool_deps_same_test(name):
    mock_pkg(name = name + "_dep1", package_name = "pkg_a")
    mock_pkg(name = name + "_dep2", package_name = "pkg_a")
    mock_pkg(name = name + "_dep3", package_name = "pkg_a")
    group_tool_deps_subject(
        name = name + "_subject",
        dep1 = ":" + name + "_dep1",
        dep2 = ":" + name + "_dep2",
        dep3 = ":" + name + "_dep3",
    )
    analysis_test(name = name, target = ":" + name + "_subject", impl = _group_tool_deps_same_impl)

# buildifier: disable=unused-variable
def _group_tool_deps_via_library_proxy_impl(env, target):
    info = target[TestingInfo]
    env.expect.that_int(len(info.result)).equals(2)
    env.expect.that_int(len(info.result.get("setuptools", []))).equals(1)
    env.expect.that_int(len(info.result.get("maturin", []))).equals(1)
    env.expect.that_str(info.site_packages.get("setuptools", "")).contains("_raw_setuptools_site")
    env.expect.that_str(info.site_packages.get("maturin", "")).contains("_raw_maturin_site")

def _group_tool_deps_via_library_proxy_test(name):
    mock_pkg(name = name + "_raw_setuptools", package_name = "setuptools")
    mock_pkg(name = name + "_raw_maturin", package_name = "maturin")
    pycross_library_proxy(
        name = name + "_proxy_setuptools",
        actual = ":" + name + "_raw_setuptools",
    )
    pycross_library_proxy(
        name = name + "_proxy_maturin",
        actual = ":" + name + "_raw_maturin",
    )
    group_tool_deps_subject(
        name = name + "_subject",
        dep1 = ":" + name + "_proxy_setuptools",
        dep2 = ":" + name + "_proxy_maturin",
    )
    analysis_test(name = name, target = ":" + name + "_subject", impl = _group_tool_deps_via_library_proxy_impl)

def _mock_py_lib_impl(ctx):
    f = ctx.actions.declare_file(ctx.label.name + ".py")
    ctx.actions.write(f, "")
    return [
        DefaultInfo(
            files = depset([f]),
            runfiles = ctx.runfiles(files = [f]),
        ),
        PyInfo(
            transitive_sources = depset([f]),
            imports = depset([ctx.attr.import_path]),
            uses_shared_libraries = False,
        ),
    ]

_mock_py_lib = rule(
    implementation = _mock_py_lib_impl,
    attrs = {"import_path": attr.string(mandatory = True)},
    provides = [DefaultInfo, PyInfo],
)

def _proxy_deps_only_empty_impl(env, target):
    env.expect.that_collection(target[PyInfo].transitive_sources.to_list()).contains_exactly([])
    env.expect.that_collection(target[PyInfo].imports.to_list()).contains_exactly([])
    env.expect.that_bool(target[PyInfo].uses_shared_libraries).equals(False)
    env.expect.that_collection(target[DefaultInfo].default_runfiles.files.to_list()).contains_exactly([])

def _proxy_deps_only_single_impl(env, target):
    env.expect.that_collection(target[PyInfo].imports.to_list()).contains_exactly(["mod_a"])
    env.expect.that_int(len(target[PyInfo].transitive_sources.to_list())).equals(1)
    env.expect.that_bool(target[PyInfo].uses_shared_libraries).equals(False)
    env.expect.that_int(len(target[DefaultInfo].default_runfiles.files.to_list())).equals(1)

def _proxy_deps_only_multi_impl(env, target):
    env.expect.that_collection(target[PyInfo].imports.to_list()).contains_exactly(["mod_a", "mod_b"])
    env.expect.that_int(len(target[PyInfo].transitive_sources.to_list())).equals(2)
    env.expect.that_bool(target[PyInfo].uses_shared_libraries).equals(False)
    env.expect.that_int(len(target[DefaultInfo].default_runfiles.files.to_list())).equals(2)

def _proxy_deps_only_empty_test(name):
    pycross_library_proxy(name = name + "_subject", deps = [])
    analysis_test(name = name, target = ":" + name + "_subject", impl = _proxy_deps_only_empty_impl)

def _proxy_deps_only_single_test(name):
    _mock_py_lib(name = name + "_a", import_path = "mod_a")
    pycross_library_proxy(name = name + "_subject", deps = [":" + name + "_a"])
    analysis_test(name = name, target = ":" + name + "_subject", impl = _proxy_deps_only_single_impl)

def _proxy_deps_only_multi_test(name):
    _mock_py_lib(name = name + "_a", import_path = "mod_a")
    _mock_py_lib(name = name + "_b", import_path = "mod_b")
    pycross_library_proxy(name = name + "_subject", deps = [":" + name + "_a", ":" + name + "_b"])
    analysis_test(name = name, target = ":" + name + "_subject", impl = _proxy_deps_only_multi_impl)

_PathToolResultInfo = provider(doc = "Resolved path tool info", fields = ["tools"])

def _mock_exec_tool_impl(ctx):
    exe = ctx.actions.declare_file(ctx.label.name + "_bin")
    data = ctx.actions.declare_file(ctx.label.name + "_data.txt")
    ctx.actions.write(exe, "#!/bin/sh\n", is_executable = True)
    ctx.actions.write(data, "payload")
    return [
        DefaultInfo(
            executable = exe,
            files = depset([exe]),
            runfiles = ctx.runfiles(files = [data]),
        ),
    ]

_mock_exec_tool = rule(
    implementation = _mock_exec_tool_impl,
    executable = True,
)

def _resolve_path_tools_subject_impl(ctx):
    return [_PathToolResultInfo(tools = resolve_path_tools(ctx))]

_resolve_path_tools_subject = rule(
    implementation = _resolve_path_tools_subject_impl,
    attrs = {"path_tools": attr.label_list()},
)

def _path_tool_propagates_files_to_run_impl(env, target):
    tools = target[_PathToolResultInfo].tools
    env.expect.that_int(len(tools)).equals(1)
    env.expect.that_str(tools[0].name).equals("custom_name")
    env.expect.that_bool(tools[0].files_to_run.executable != None).equals(True)
    env.expect.that_str(tools[0].files_to_run.executable.basename).contains("_bin")
    env.expect.that_bool(tools[0].files_to_run.runfiles_manifest != None).equals(True)

def _path_tool_propagates_files_to_run_test(name):
    _mock_exec_tool(name = name + "_raw_tool")
    pycross_path_tool(
        name = name + "_wrapped_tool",
        tool = ":" + name + "_raw_tool",
        executable_name = "custom_name",
    )
    _resolve_path_tools_subject(
        name = name + "_subject",
        path_tools = [":" + name + "_wrapped_tool"],
    )
    analysis_test(
        name = name,
        target = ":" + name + "_subject",
        impl = _path_tool_propagates_files_to_run_impl,
    )

def _proxy_unsupported_wheel_names_package_impl(env, target):
    actions = [a for a in target.actions if a.mnemonic == "PycrossUnsupportedPackage"]
    env.expect.that_int(len(actions)).equals(1)
    env.expect.that_str(actions[0].env.get("PYCROSS_ERROR", "")).contains(str(target.label))
    env.expect.that_str(actions[0].env.get("PYCROSS_ERROR", "")).contains("no matching platform marker, artifact, or variant branch")

def _proxy_library_unsupported_wheel_test(name):
    pycross_unsupported_wheel(name = name + "_no_match", tags = ["manual"])
    pycross_library_proxy(name = name + "_subject", actual = ":" + name + "_no_match", tags = ["manual"])
    analysis_test(
        name = name,
        target = ":" + name + "_subject",
        impl = _proxy_unsupported_wheel_names_package_impl,
    )

def _proxy_file_unsupported_wheel_test(name):
    pycross_unsupported_wheel(name = name + "_no_match", tags = ["manual"])
    pycross_file_proxy(name = name + "_subject", actual = ":" + name + "_no_match", tags = ["manual"])
    analysis_test(
        name = name,
        target = ":" + name + "_subject",
        impl = _proxy_unsupported_wheel_names_package_impl,
    )

def common_attrs_test_suite(name):
    test_suite(
        name = name,
        tests = [
            group_tool_deps_test,
            _group_tool_deps_empty_test,
            _group_tool_deps_no_pkg_test,
            _group_tool_deps_single_test,
            _group_tool_deps_same_test,
            _group_tool_deps_via_library_proxy_test,
            _proxy_deps_only_empty_test,
            _proxy_deps_only_single_test,
            _proxy_deps_only_multi_test,
            _path_tool_propagates_files_to_run_test,
            _proxy_library_unsupported_wheel_test,
            _proxy_file_unsupported_wheel_test,
        ],
    )
