"""A minimal MSVC toolchain for analysis testing action environments."""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:cc_toolchain_config_lib.bzl", "action_config", "env_entry", "env_set", "feature", "tool")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/actions:cc_layer.bzl", "extract_cc_layer")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/rules:common_attrs.bzl", "CC_FRAGMENTS", "CC_TOOLCHAINS", "CC_TOOLCHAIN_ATTRS")

def _probe_impl(ctx):
    result = extract_cc_layer(ctx, [], [], [])
    return [DefaultInfo(files = depset([result.config_json]))]

probe = rule(
    implementation = _probe_impl,
    attrs = CC_TOOLCHAIN_ATTRS,
    fragments = CC_FRAGMENTS,
    toolchains = CC_TOOLCHAINS,
)

def _config_impl(ctx):
    compile_actions = [ACTION_NAMES.c_compile, ACTION_NAMES.cpp_compile]
    link_actions = [ACTION_NAMES.cpp_link_dynamic_library]
    actions = compile_actions + link_actions + [ACTION_NAMES.cpp_link_executable, ACTION_NAMES.cpp_link_static_library]
    features = [feature(name = "no_legacy_features")]
    style = ctx.attr.env_style
    if style == "not_found":
        features.append(feature(name = "wrapper_environment", enabled = True, env_sets = [
            env_set(actions = compile_actions, env_entries = [
                env_entry(key = "PATH", value = "msvc_not_found"),
                env_entry(key = "INCLUDE", value = "MSVC_NOT_FOUND"),
            ]),
            env_set(actions = link_actions, env_entries = [
                env_entry(key = "LIB", value = "msvc_not_found;msvc_not_found"),
            ]),
        ]))
    elif style == "mixed_not_found":
        features.append(feature(name = "wrapper_environment", enabled = True, env_sets = [
            env_set(actions = compile_actions, env_entries = [
                env_entry(key = "PATH", value = "external/review_msvc/bin;msvc_not_found"),
                env_entry(key = "INCLUDE", value = "external/msvc_not_found_sdk/include"),
            ]),
            env_set(actions = link_actions, env_entries = [
                env_entry(key = "LIB", value = "msvc_not_found"),
            ]),
        ]))
    elif style != "none":
        mixed_case = style in ["mixed", "partial"]
        keys = ["Path", "Include", "Lib"] if mixed_case else ["PATH", "INCLUDE", "LIB"]
        compile_entries = [
            env_entry(key = keys[0], value = "external/review_msvc/bin"),
            env_entry(key = keys[1], value = "external/review_msvc/include"),
        ]
        features.append(feature(name = "wrapper_environment", enabled = True, env_sets = [
            env_set(actions = compile_actions, env_entries = compile_entries),
            env_set(
                actions = link_actions,
                env_entries = [] if style == "partial" else [env_entry(key = keys[2], value = "external/review_msvc/lib")],
            ),
        ]))
    return [cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "msvc-review",
        host_system_name = "local",
        target_system_name = "local",
        target_cpu = "x64_windows",
        target_libc = "msvcrt",
        compiler = "msvc-cl",
        abi_version = "local",
        abi_libc_version = "local",
        action_configs = [action_config(action_name = action, enabled = True, tools = [tool(path = "wrapper")]) for action in actions],
        features = features,
    )]

probe_config = rule(implementation = _config_impl, attrs = {"env_style": attr.string(default = "none")})
