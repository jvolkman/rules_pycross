"""Rule for repairing wheels by bundling native shared libraries."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//pycross/private/build:wheel_shared_libraries.bzl", "collect_wheel_shared_libraries")
load("//pycross/private/build/actions:repair_action.bzl", "register_repair_action")
load("//pycross/private/build/rules:common_attrs.bzl", "REPAIR_BUILD_ATTRS")

def _pycross_repaired_wheel_impl(ctx):
    input_wheel_dir = ctx.files.wheel[0]

    target_environment = None
    if ctx.files.target_environment:
        target_environment = ctx.files.target_environment[0]

    repair_result = register_repair_action(
        ctx,
        input_wheel_dir = input_wheel_dir,
        native_deps = ctx.attr.native_deps,
        repair_tool = ctx.executable._repair_tool,
        target_environment = target_environment,
        repair_exclude_globs = ctx.attr.repair_exclude_globs,
    )

    return [DefaultInfo(files = depset([repair_result.wheel_dir]))]

pycross_repaired_wheel = rule(
    implementation = _pycross_repaired_wheel_impl,
    attrs = REPAIR_BUILD_ATTRS | {
        "wheel": attr.label(
            doc = "The input wheel to repair.",
            mandatory = True,
            allow_files = True,
        ),
        "native_deps": attr.label_list(
            doc = "Native dependencies providing shared libraries to bundle.",
            providers = [CcInfo],
            aspects = [collect_wheel_shared_libraries],
        ),
        "whldir_name": attr.string(
            doc = "Name for the output .whldir TreeArtifact directory. If empty, defaults to '{name}.whldir'.",
        ),
    },
)
