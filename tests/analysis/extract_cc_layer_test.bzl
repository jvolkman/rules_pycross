"""Module docstring for tests."""

load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

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
    ]

_mock_cc_layer = rule(
    implementation = _mock_cc_layer_impl,
    attrs = dict(CC_TOOLCHAIN_ATTRS, **{
        # Defines from `deps` end up in the toolchain flags.
        "deps": attr.label_list(),
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
        deps = [name + "_defines"],
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
    env.expect.that_collection(include_dirs).contains("$$EXT_BUILD_ROOT$$//tests/analysis")
    for inc in include_dirs:
        env.expect.where(include_dir = inc).that_bool(inc.startswith("$$EXT_BUILD_ROOT$$/")).equals(True)

def extract_cc_layer_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_extract_cc_layer_flags,
            _test_extract_cc_layer_user_flags,
            _test_extract_cc_layer_main_repo_includes,
        ],
    )
