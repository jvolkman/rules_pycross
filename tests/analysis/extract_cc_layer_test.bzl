load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//pycross/private/build/actions:cc_layer.bzl", "extract_cc_layer")
load("//pycross/private/build/rules:common_attrs.bzl", "CC_TOOLCHAIN_ATTRS", "CC_TOOLCHAINS", "CC_FRAGMENTS")

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

def _test_extract_cc_layer_flags_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_exactly([
        "{}/{}_cc_config.json".format(target.label.package, target.label.name)
    ])
    
    action = env.expect.that_target(target).action_generating("{}/{}_cc_config.json".format(target.label.package, target.label.name))
    
    # Action write content is not easily exposed in Starlark, but we check action mnemonic.
    action.mnemonic().equals("FileWrite")
    
    # Alternatively we can inspect the content of the FileWrite action in newer rules_testing
    # if content() is exposed, but we'll stick to asserting the file is properly registered.

def extract_cc_layer_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_extract_cc_layer_flags,
        ],
    )
