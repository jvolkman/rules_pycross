"""Module docstring for tests."""

load("@rules_cc//cc:defs.bzl", "cc_import", "cc_library")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_library.bzl", "pycross_wheel_library")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private/build:cc_toolchain_util.bzl",
    "absolutize_additional_input_paths_for_testing",
    "convert_flags_for_testing",
)

# buildifier: disable=bzl-visibility
load("//pycross/private/build:wheel_cc_import.bzl", "pycross_wheel_cc_import")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/actions:cc_layer.bzl", "extract_cc_layer")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/rules:common_attrs.bzl", "CC_FRAGMENTS", "CC_TOOLCHAINS", "CC_TOOLCHAIN_ATTRS")

def _mock_cc_layer_impl(ctx):
    cc_layer = extract_cc_layer(
        ctx = ctx,
        native_deps = ctx.attr.native_deps,
        copts = ctx.attr.copts,
        linkopts = ctx.attr.linkopts,
        meson_properties = {},
    )
    return [
        DefaultInfo(files = depset([cc_layer.config_json])),
        OutputGroupInfo(transitive_files = cc_layer.transitive_files),
    ]

_mock_cc_layer = rule(
    implementation = _mock_cc_layer_impl,
    attrs = dict(CC_TOOLCHAIN_ATTRS, **{
        "native_deps": attr.label_list(),
        "copts": attr.string_list(),
        "linkopts": attr.string_list(),
    }),
    fragments = CC_FRAGMENTS,
    toolchains = CC_TOOLCHAINS,
)

def _test_extract_cc_layer_flags(name):
    util.helper_target(
        _mock_cc_layer,
        name = name + "_subject",
        copts = ["-O3", "-fno-strict-aliasing"],
        linkopts = ["-Wl,-strip-all"],
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_extract_cc_layer_flags_impl,
    )

# buildifier: disable=unused-variable
def _test_extract_cc_layer_flags_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_exactly([
        "{}/{}_cc_config.json".format(target.label.package, target.label.name),
    ])

    action = env.expect.that_target(target).action_generating("{}/{}_cc_config.json".format(target.label.package, target.label.name))

    action.mnemonic().equals("FileWrite")

    content = action.content()
    content.contains('"CC"')
    content.contains('"CXX"')
    content.contains('"AR"')
    content.contains('"CFLAGS"')
    content.contains('"LDFLAGS"')
    content.contains("-O3")
    content.contains("-fno-strict-aliasing")
    content.contains("-Wl,-strip-all")

    arflags = _cc_config(target)["ARFLAGS"]
    env.expect.that_bool(bool(arflags)).equals(True)
    env.expect.that_bool("__PYCROSS_ARCHIVER_OUTPUT__" in arflags).equals(False)

def _cc_config(target):
    for action in target.actions:
        for output in action.outputs.to_list():
            if output.basename.endswith("_cc_config.json"):
                return json.decode(action.content)
    fail("no cc_config.json action")

def _test_extract_cc_layer_user_flags(name):
    util.helper_target(cc_library, name = name + "_defines", defines = ["PYCROSS_TEST_DUP"])
    util.helper_target(
        _mock_cc_layer,
        name = name + "_subject",
        native_deps = [name + "_defines"],
        copts = ["-DPYCROSS_TEST_DUP", "-DPYCROSS_TEST_STR=\"a b\"", "-isystem", "/opt/userinc"],
        linkopts = ["-Wl,-rpath,$$ORIGIN"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_extract_cc_layer_user_flags_impl)

def _test_extract_cc_layer_user_flags_impl(env, target):
    cflags = _cc_config(target)["CFLAGS"]

    # User copts are appended verbatim, even if a token also appears in the
    # toolchain flags, and tokens with quotes/spaces are shell-quoted.
    env.expect.that_bool(
        cflags.endswith(" -DPYCROSS_TEST_DUP '-DPYCROSS_TEST_STR=\"a b\"' -isystem /opt/userinc"),
    ).equals(True)
    env.expect.that_int(cflags.count("-DPYCROSS_TEST_DUP")).equals(2)

    # `$` is left unquoted.
    env.expect.that_bool(_cc_config(target)["LDFLAGS"].endswith(" -Wl,-rpath,$ORIGIN")).equals(True)

def _test_extract_cc_layer_main_repo_includes(name):
    util.helper_target(cc_library, name = name + "_hdrs", hdrs = ["mock.h"], includes = ["."])
    util.helper_target(
        _mock_cc_layer,
        name = name + "_subject",
        native_deps = [name + "_hdrs"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_extract_cc_layer_main_repo_includes_impl)

def _test_extract_cc_layer_main_repo_includes_impl(env, target):
    include_dirs = _cc_config(target)["include_dirs"]
    env.expect.that_collection(include_dirs).contains("$$EXT_BUILD_ROOT$$/tests/analysis")
    for inc in include_dirs:
        env.expect.where(include_dir = inc).that_bool(inc.startswith("$$EXT_BUILD_ROOT$$/")).equals(True)
        env.expect.where(include_dir = inc).that_bool("//" in inc).equals(False)

def _test_extract_cc_layer_native_libraries(name):
    # These imports only provide CcInfo for analysis; the placeholder files are
    # never linked. Keep both library extensions in the same test so it runs
    # independently of the host platform.
    util.helper_target(cc_import, name = name + "_archive", static_library = "mock_native.a")
    util.helper_target(
        cc_import,
        name = name + "_pic_archive",
        static_library = "mock_both.a",
        pic_static_library = "mock_both.pic.a",
    )
    util.helper_target(cc_import, name = name + "_static_lib", static_library = "mock_native_static.lib")
    util.helper_target(
        cc_import,
        name = name + "_interface_lib",
        interface_library = "mock_native_interface.lib",
        shared_library = "mock_native.dll",
    )
    util.helper_target(
        _mock_cc_layer,
        name = name + "_subject",
        native_deps = [
            name + "_archive",
            name + "_pic_archive",
            name + "_static_lib",
            name + "_interface_lib",
        ],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_extract_cc_layer_native_libraries_impl)

def _test_extract_cc_layer_native_libraries_impl(env, target):
    static_libs = _cc_config(target)["static_libs"]
    for path in [
        "$$EXT_BUILD_ROOT$$/tests/analysis/mock_native.a",
        "$$EXT_BUILD_ROOT$$/tests/analysis/mock_both.pic.a",
        "$$EXT_BUILD_ROOT$$/tests/analysis/mock_native_static.lib",
        "$$EXT_BUILD_ROOT$$/tests/analysis/mock_native_interface.lib",
    ]:
        env.expect.that_collection(static_libs).contains(path)
    env.expect.that_collection(static_libs).contains_none_of(["$$EXT_BUILD_ROOT$$/tests/analysis/mock_both.a"])

def _mock_template_var_impl(_ctx):
    return [platform_common.TemplateVariableInfo({"CUSTOM_CC_FLAG": "-DCUSTOM_VAR_OK"})]

_mock_template_var = rule(implementation = _mock_template_var_impl)

def _test_extract_cc_layer_template_vars(name):
    util.helper_target(_mock_template_var, name = name + "_vars")
    util.helper_target(
        _mock_cc_layer,
        name = name + "_subject",
        native_deps = [name + "_vars"],
        copts = ["$(CUSTOM_CC_FLAG)"],
        linkopts = ["-Wl,$(CUSTOM_CC_FLAG)"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_extract_cc_layer_template_vars_impl)

def _test_extract_cc_layer_template_vars_impl(env, target):
    cfg = _cc_config(target)
    env.expect.that_str(cfg["CFLAGS"]).contains("-DCUSTOM_VAR_OK")
    env.expect.that_str(cfg["LDFLAGS"]).contains("-Wl,-DCUSTOM_VAR_OK")

def _test_extract_cc_layer_copts_no_shadowing(name):
    util.helper_target(
        _mock_cc_layer,
        name = name + "_subject",
        copts = ["-DUSER_COPT"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:copt": ["-DCMD_COPT"],
            "//command_line_option:conlyopt": ["-DCMD_CONLY"],
            "//command_line_option:cxxopt": ["-DCMD_CXX"],
        },
        impl = _test_extract_cc_layer_copts_no_shadowing_impl,
    )

def _test_extract_cc_layer_copts_no_shadowing_impl(env, target):
    cfg = _cc_config(target)
    cflags = cfg["CFLAGS"]
    cxxflags = cfg["CXXFLAGS"]
    env.expect.that_int(cflags.count("-DCMD_COPT")).equals(1)
    env.expect.that_int(cflags.count("-DCMD_CONLY")).equals(1)
    env.expect.that_int(cflags.count("-DCMD_CXX")).equals(0)
    env.expect.that_int(cxxflags.count("-DCMD_COPT")).equals(1)
    env.expect.that_int(cxxflags.count("-DCMD_CONLY")).equals(0)
    env.expect.that_int(cxxflags.count("-DCMD_CXX")).equals(1)
    env.expect.that_int(cxxflags.count("-DUSER_COPT")).equals(1)

def _test_convert_msvc_flags(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_convert_msvc_flags_impl)

# buildifier: disable=unused-variable
def _test_convert_msvc_flags_impl(env, target):
    # Verify MSVC flag conversion rewrites only the leading `/` without corrupting paths.
    converted = convert_flags_for_testing("msvc-cl", ["/nologo", "/IC:/Users/foo/include", "-O2"])
    env.expect.that_collection(converted).contains_exactly(["-nologo", "-IC:/Users/foo/include", "-O2"]).in_order()

def _test_extract_cc_layer_native_link_flags(name):
    util.helper_target(
        cc_library,
        name = name + "_base",
        additional_linker_inputs = ["mock.h"],
        linkopts = [
            "-lbase_dep",
            "-framework",
            "Accelerate",
            "-Wl,--version-script=$(execpath mock.h)",
        ],
    )
    util.helper_target(
        cc_library,
        name = name + "_left",
        linkopts = ["-lleft_dep"],
        deps = [name + "_base"],
    )
    util.helper_target(
        cc_library,
        name = name + "_right",
        linkopts = ["-lright_dep"],
        deps = [name + "_base"],
    )
    util.helper_target(
        pycross_wheel_library,
        name = name + "_wheel_lib",
        wheel = "test-1.0-py3-none-any.whl",
    )
    util.helper_target(
        pycross_wheel_cc_import,
        name = name + "_wheel_cc",
        includes = ["pkg/include"],
        linkopts = ["-Wl,-rpath,$ORIGIN/../pkg/lib"],
        wheel_library = name + "_wheel_lib",
    )
    util.helper_target(
        _mock_cc_layer,
        name = name + "_subject",
        native_deps = [name + "_left", name + "_right", name + "_wheel_cc"],
        linkopts = ["-lrule_last"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_extract_cc_layer_native_link_flags_impl,
    )

def _test_extract_cc_layer_native_link_flags_impl(env, target):
    cfg = _cc_config(target)
    for key in ("LDFLAGS", "LDSHAREDFLAGS"):
        val = cfg[key]
        env.expect.where(key = key).that_str(val).contains("-lleft_dep")
        env.expect.where(key = key).that_str(val).contains("-lright_dep")
        env.expect.where(key = key).that_str(val).contains("-lbase_dep -framework Accelerate -Wl,--version-script=$$EXT_BUILD_ROOT$$/tests/analysis/mock.h")
        env.expect.where(key = key).that_str(val).contains("-Wl,-rpath,$ORIGIN/../pkg/lib")
        env.expect.where(key = key).that_bool(val.endswith(" -lrule_last")).equals(True)

        # Topological link order: dependents precede shared dependency, and diamond `_base` is deduplicated.
        env.expect.where(key = key).that_bool(val.index("-lleft_dep") < val.index("-lbase_dep")).equals(True)
        env.expect.where(key = key).that_bool(val.index("-lright_dep") < val.index("-lbase_dep")).equals(True)
        env.expect.where(key = key).that_int(val.count("-lbase_dep")).equals(1)

    transitive_paths = [f.short_path for f in target[OutputGroupInfo].transitive_files.to_list()]
    env.expect.that_collection(transitive_paths).contains("tests/analysis/mock.h")

def _test_absolutize_additional_input_paths(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_absolutize_additional_input_paths_impl)

# buildifier: disable=unused-variable
def _test_absolutize_additional_input_paths_impl(env, target):
    paths = ["a/pkg/foo.lds", "pkg/foo.lds.bak", "pkg/foo.lds", "external/repo/a.lds", "bazel-out/k8-opt/bin/x.def"]
    cases = [
        ("pkg/foo.lds", "$$EXT_BUILD_ROOT$$/pkg/foo.lds"),
        ("-Tpkg/foo.lds", "-T$$EXT_BUILD_ROOT$$/pkg/foo.lds"),
        ("-Wl,-Tpkg/foo.lds", "-Wl,-T$$EXT_BUILD_ROOT$$/pkg/foo.lds"),
        ("-Wl,-T,pkg/foo.lds", "-Wl,-T,$$EXT_BUILD_ROOT$$/pkg/foo.lds"),
        ("-Wl,--version-script=pkg/foo.lds", "-Wl,--version-script=$$EXT_BUILD_ROOT$$/pkg/foo.lds"),
        ("/DEF:bazel-out/k8-opt/bin/x.def", "/DEF:$$EXT_BUILD_ROOT$$/bazel-out/k8-opt/bin/x.def"),
        ("@pkg/foo.lds", "@$$EXT_BUILD_ROOT$$/pkg/foo.lds"),
        # buildifier: disable=external-path
        ("-Wl,--version-script=external/repo/a.lds", "-Wl,--version-script=$$EXT_BUILD_ROOT$$/external/repo/a.lds"),
        # Trailing boundary check avoids prefix-matching `pkg/foo.lds` inside `pkg/foo.lds.bak`.
        ("-Wl,--version-script=pkg/foo.lds.bak", "-Wl,--version-script=$$EXT_BUILD_ROOT$$/pkg/foo.lds.bak"),
        # Longest-first avoids matching `pkg/foo.lds` inside `a/pkg/foo.lds`.
        ("-Wl,--version-script=a/pkg/foo.lds", "-Wl,--version-script=$$EXT_BUILD_ROOT$$/a/pkg/foo.lds"),
        # Already-prefixed and absolute paths stay unchanged.
        ("-Wl,--version-script=$$EXT_BUILD_ROOT$$/pkg/foo.lds", "-Wl,--version-script=$$EXT_BUILD_ROOT$$/pkg/foo.lds"),
        ("-Wl,--version-script=/abs/pkg/foo.lds", "-Wl,--version-script=/abs/pkg/foo.lds"),
        ("-Wl,-rpath,$ORIGIN/../lib", "-Wl,-rpath,$ORIGIN/../lib"),
    ]
    for flag, expected in cases:
        got = absolutize_additional_input_paths_for_testing(flag, paths)
        env.expect.where(flag = flag).that_str(got).equals(expected)

def _test_extract_cc_layer_msvc_environment(name):
    native.test_suite(
        name = name,
        tests = ["//tests/analysis/msvc_env:tests"],
    )

def extract_cc_layer_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_extract_cc_layer_flags,
            _test_extract_cc_layer_user_flags,
            _test_extract_cc_layer_main_repo_includes,
            _test_extract_cc_layer_native_libraries,
            _test_extract_cc_layer_native_link_flags,
            _test_absolutize_additional_input_paths,
            _test_extract_cc_layer_template_vars,
            _test_extract_cc_layer_copts_no_shadowing,
            _test_convert_msvc_flags,
            _test_extract_cc_layer_msvc_environment,
        ],
    )
