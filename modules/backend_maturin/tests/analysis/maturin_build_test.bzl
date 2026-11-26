"""Tests for maturin_build.bzl."""

load("@rules_pycross//pycross:backend.bzl", "PycrossExtractedWheelInfo", "PycrossPackageInfo")
load("@rules_python//python:defs.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("//private:cargo.bzl", "find_cargo_lock_in_sdist")
load("//private:rust_common_sdist_hook.bzl", "rust_common_sdist_hook")
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

def _fake_path(rel_path, files):
    exists = rel_path == "" or rel_path in files or any([p.startswith(rel_path + "/") for p in files])
    is_dir = rel_path == "" or any([p.startswith(rel_path + "/") for p in files])
    return struct(
        path = rel_path,
        exists = exists,
        is_dir = is_dir,
        get_child = lambda name: _fake_path((rel_path + "/" + name) if rel_path else name, files),
        readdir = lambda: [_fake_path(rel_path + "/ws-1.0", files)] if rel_path == "cargo_lock_check_tmp" else [],
    )

def _test_rust_sdist_hook_uses_hook_files_dir_without_extract(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_rust_sdist_hook_uses_hook_files_dir_without_extract_impl,
    )

# buildifier: disable=unused-variable
def _test_rust_sdist_hook_uses_hook_files_dir_without_extract_impl(env, target):
    # 1. Workspace upward walk from maturin manifest-path finds root Cargo.lock.
    workspace_files = {
        "pyproject.toml": '[tool.maturin]\nmanifest-path = "crates/py/Cargo.toml"\n',
        "Cargo.lock": '[[package]]\nname = "demo"\nversion = "0.1.0"\n',
    }
    fake_rctx = struct(
        name = "test_sdist_repo",
        attr = struct(source_dir = ""),
        read = lambda p: workspace_files[p.path],
        report_progress = lambda _msg: None,
        delete = lambda _p: None,
        extract = lambda **_kwargs: fail("rust_common_sdist_hook must not re-extract sdist archive"),
    )
    found_ws = find_cargo_lock_in_sdist(fake_rctx, _fake_path("", workspace_files))
    env.expect.that_str(found_ws.path).equals("Cargo.lock")

    # 2. Nested setuptools-rust lock next to Cargo.toml is preferred over workspace root.
    sr_files = {
        "pyproject.toml": '[[tool.setuptools-rust.ext-modules]]\npath = "src/rust/Cargo.toml"\n',
        "Cargo.lock": "root\n",
        "src/rust/Cargo.lock": "nested\n",
    }
    sr_rctx = struct(read = lambda p: sr_files[p.path])
    found_sr = find_cargo_lock_in_sdist(sr_rctx, _fake_path("", sr_files))
    env.expect.that_str(found_sr.path).equals("src/rust/Cargo.lock")

    # 3. source_dir inside a Cargo workspace reads py/pyproject.toml and walks up to root Cargo.lock.
    sub_ws_files = {
        "Cargo.lock": '[[package]]\nname = "demo"\nversion = "0.1.0"\n',
        "py/pyproject.toml": '[tool.maturin]\nmanifest-path = "Cargo.toml"\n',
        "bindings/py/pyproject.toml": '[tool.maturin]\nmanifest-path = "../rust/Cargo.toml"\n',
        "bindings/rust/Cargo.lock": '[[package]]\nname = "demo"\nversion = "0.2.0"\n',
    }
    sub_ws_rctx = struct(
        name = "test_sub_ws_repo",
        attr = struct(source_dir = "py"),
        read = lambda p: sub_ws_files[p.path],
        report_progress = lambda _msg: None,
        delete = lambda _p: None,
        extract = lambda **_kwargs: fail("rust_common_sdist_hook must not re-extract sdist archive"),
    )
    env.expect.that_str(
        find_cargo_lock_in_sdist(sub_ws_rctx, _fake_path("", sub_ws_files), source_dir = "py").path,
    ).equals("Cargo.lock")
    env.expect.that_str(
        find_cargo_lock_in_sdist(sub_ws_rctx, _fake_path("", sub_ws_files), source_dir = "bindings/py").path,
    ).equals("bindings/rust/Cargo.lock")

    # 4. rust_common_sdist_hook consumes result.hook_files_dir (with source_dir) without touching rctx.extract.
    hook_res = rust_common_sdist_hook(
        sub_ws_rctx,
        struct(
            applied_override_config = {},
            hook_files_dir = _fake_path("", sub_ws_files),
        ),
    )
    env.expect.that_str(hook_res.extra_attrs["vendored_crates"]).equals('":vendored_crates"')

    # 5. Version-skew fallback: if result omits hook_files_dir, falls back to rctx.extract.
    extracted_calls = []
    fallback_files = {
        "cargo_lock_check_tmp/ws-1.0/Cargo.lock": '[[package]]\nname = "demo"\nversion = "0.1.0"\n',
        "cargo_lock_check_tmp/ws-1.0/py/pyproject.toml": '[tool.maturin]\nmanifest-path = "Cargo.toml"\n',
        "Cargo.lock.extracted": '[[package]]\nname = "demo"\nversion = "0.1.0"\n',
    }
    fallback_rctx = struct(
        name = "test_fallback_repo",
        attr = struct(sdist = "@fake//:sdist.tar.gz", source_dir = "py"),
        path = lambda p: _fake_path(p, fallback_files),
        file = lambda _p, _content: None,
        read = lambda p: fallback_files[p.path],
        report_progress = lambda _msg: None,
        delete = lambda _p: None,
        extract = lambda **kwargs: extracted_calls.append(kwargs),
    )
    fallback_res = rust_common_sdist_hook(fallback_rctx, struct(applied_override_config = {}))
    env.expect.that_int(len(extracted_calls)).equals(1)
    env.expect.that_str(fallback_res.extra_attrs["vendored_crates"]).equals('":vendored_crates"')

def maturin_build_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_maturin_build_basic,
            _test_maturin_build_resources,
            _test_maturin_build_missing_tools,
            _test_maturin_build_tool_deps_aspect,
            _test_maturin_build_vendored_crates_path,
            _test_rust_sdist_hook_uses_hook_files_dir_without_extract,
        ],
    )
