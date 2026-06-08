"""Rule for repairing wheels by bundling native shared libraries."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//pycross/private/build/actions:repair_action.bzl", "register_repair_action")

def _pycross_repaired_wheel_impl(ctx):
    input_wheelhouse = ctx.files.wheel[0]

    target_environment = None
    if ctx.files.target_environment:
        target_environment = ctx.files.target_environment[0]

    repair_result = register_repair_action(
        ctx,
        input_wheelhouse = input_wheelhouse,
        native_deps = ctx.attr.native_deps,
        repair_tool = ctx.executable._repair_tool,
        target_environment = target_environment,
    )

    return [DefaultInfo(files = depset([repair_result.wheelhouse]))]

pycross_repaired_wheel = rule(
    implementation = _pycross_repaired_wheel_impl,
    attrs = {
        "wheel": attr.label(
            doc = "The input wheel to repair.",
            mandatory = True,
            allow_files = True,
        ),
        "native_deps": attr.label_list(
            doc = "Native dependencies providing shared libraries to bundle.",
            providers = [CcInfo],
        ),
        "target_environment": attr.label(
            doc = "The target environment mapping JSON (resolved dynamically via alias filegroup).",
            default = Label("@pycross_environments//:current"),
            allow_files = True,
        ),
        "_repair_tool": attr.label(
            default = Label("//pycross/private/build/tools:repair_wheel_hook"),
            executable = True,
            cfg = "exec",
        ),
    },
)
