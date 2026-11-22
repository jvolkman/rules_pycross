"""Tests for maturin_build.bzl."""

load("@rules_pycross//pycross:backend.bzl", "PycrossExtractedWheelInfo", "PycrossPackageInfo")
load("@rules_python//python:defs.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("//rules:maturin_build.bzl", "maturin_build")

def _mock_pkg_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_dir")
    ctx.actions.run_shell(outputs = [out], command = "mkdir -p $1", arguments = [out.path])
    return [
        PycrossPackageInfo(package_name = ctx.attr.package_name, package_version = "1.0"),
        DefaultInfo(files = depset([out])),
        PyInfo(has_py2_only_sources = False, has_py3_only_sources = True, transitive_sources = depset([])),
        PycrossExtractedWheelInfo(site_packages = out),
    ]

_mock_pkg = rule(
    implementation = _mock_pkg_impl,
    attrs = {"package_name": attr.string()},
)

def _mock_executable_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(out, "#!/bin/sh\nexit 0", is_executable = True)
    return [DefaultInfo(executable = out)]

_mock_executable = rule(
    implementation = _mock_executable_impl,
    executable = True,
)

def _test_maturin_build_basic(name):
    util.helper_target(
        native.filegroup,
        name = name + "_sdist",
        srcs = ["test-sdist.tar.gz"],
    )

    util.helper_target(
        _mock_executable,
        name = name + "_mock_maturin",
    )

    util.helper_target(
        maturin_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        path_tools = [name + "_mock_maturin"],
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_maturin_build_basic_impl,
    )

def _test_maturin_build_basic_impl(env, target):
    env.expect.that_target(target).has_provider(DefaultInfo)
    env.expect.that_target(target).has_provider(OutputGroupInfo)

    rust_cfg_action = [
        a
        for a in target.actions
        if any([o.basename.endswith("_rust_config.json") for o in a.outputs.to_list()])
    ][0]
    rust_cfg = json.decode(rust_cfg_action.content)
    env.expect.that_bool(bool(rust_cfg.get("host_rustlib_dir"))).equals(True)
    env.expect.that_bool(bool(rust_cfg.get("target_rustlib_dir"))).equals(True)
    env.expect.that_str(rust_cfg["host_rustlib_dir"]).contains("/lib/rustlib/")
    env.expect.that_str(rust_cfg["target_rustlib_dir"]).contains("/lib/rustlib/")

def _test_maturin_build_resources(name):
    util.helper_target(
        native.filegroup,
        name = name + "_sdist",
        srcs = ["test-sdist.tar.gz"],
    )

    util.helper_target(
        _mock_executable,
        name = name + "_mock_maturin",
    )

    util.helper_target(
        maturin_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        path_tools = [name + "_mock_maturin"],
        resource_size = "medium",
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_maturin_build_resources_impl,
    )

def _test_maturin_build_resources_impl(env, target):
    action = env.expect.that_target(target).action_named("PycrossPep517Build")
    action.env().contains_at_least({
        "CARGO_BUILD_JOBS": "6",
        "MAKEFLAGS": "-j6",
    })

def _test_maturin_build_missing_tools(name):
    util.helper_target(
        native.filegroup,
        name = name + "_sdist",
        srcs = ["test-sdist.tar.gz"],
    )

    util.helper_target(
        maturin_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        whldir_name = "maturinpkg-1.0.whldir",
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_maturin_build_missing_tools_impl,
    )

def _test_maturin_build_missing_tools_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    env.expect.that_bool(wheel_dir.is_directory).equals(True)
    action = env.expect.that_target(target).action_generating(wheel_dir.short_path)
    action.mnemonic().equals("PycrossSdistBuildConfigError")
    action.env().contains_exactly({
        "PYCROSS_ERROR": "Cannot build test-sdist.tar.gz from source:\nMissing 'maturin' in tool_deps",
    })

def _test_maturin_build_tool_deps_aspect(name):
    util.helper_target(
        native.filegroup,
        name = name + "_sdist",
        srcs = ["test-sdist.tar.gz"],
    )
    util.helper_target(
        _mock_pkg,
        name = name + "_maturin",
        package_name = "maturin",
    )
    util.helper_target(
        maturin_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        tool_deps = [name + "_maturin"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_maturin_build_tool_deps_aspect_impl,
    )

def _test_maturin_build_tool_deps_aspect_impl(env, target):
    mnemonics = [a.mnemonic for a in target.actions]
    env.expect.that_collection(mnemonics).not_contains("PycrossExtractWheelBin")

    build_action = env.expect.that_target(target).action_named("PycrossPep517Build")
    build_action.inputs().contains_predicate(matching.file_path_matches("*_maturin_tools/maturin"))

def _mock_vendored_crates_impl(ctx):
    # Include a deeply nested fixture .cargo-checksum.json before the shallow crate one
    # to verify _resolve_vendored_crates_dir picks the shallowest vendor root.
    nested = ctx.actions.declare_file(ctx.label.name + "/custom_vendor/cargo-0.70/tests/fixtures/f/.cargo-checksum.json")
    top = ctx.actions.declare_file(ctx.label.name + "/custom_vendor/serde-1.0/.cargo-checksum.json")
    ctx.actions.write(nested, "{}")
    ctx.actions.write(top, "{}")
    return [DefaultInfo(files = depset([nested, top]))]

_mock_vendored_crates = rule(implementation = _mock_vendored_crates_impl)

def _test_maturin_build_vendored_crates_path(name):
    util.helper_target(native.filegroup, name = name + "_sdist", srcs = ["test-sdist.tar.gz"])
    util.helper_target(_mock_executable, name = name + "_mock_maturin")
    util.helper_target(_mock_vendored_crates, name = name + "_vendor")
    util.helper_target(
        maturin_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        path_tools = [name + "_mock_maturin"],
        vendored_crates = name + "_vendor",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_maturin_build_vendored_crates_path_impl,
    )

def _test_maturin_build_vendored_crates_path_impl(env, target):
    build_action = env.expect.that_target(target).action_named("PycrossPep517Build")
    vendor_env = build_action.actual.env.get("CARGO_VENDORED_SOURCES", "")
    env.expect.that_bool(vendor_env.endswith("/custom_vendor")).equals(True)

def maturin_build_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_maturin_build_basic,
            _test_maturin_build_resources,
            _test_maturin_build_missing_tools,
            _test_maturin_build_tool_deps_aspect,
            _test_maturin_build_vendored_crates_path,
        ],
    )
