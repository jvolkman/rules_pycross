"""Rule for repairing wheels by bundling native shared libraries."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//pycross/private:providers.bzl", "PycrossWheelInfo")
load("//pycross/private/build/actions:repair_action.bzl", "register_repair_action")

def _pycross_repaired_wheel_impl(ctx):
    # Resolve input wheel file and name file.
    input_wheel_directory = None
    if PycrossWheelInfo in ctx.attr.wheel:
        wheel_info = ctx.attr.wheel[PycrossWheelInfo]
        input_wheel = wheel_info.wheel_file
        input_name_file = wheel_info.name_file
        input_wheel_directory = getattr(wheel_info, "wheel_directory", None)
    else:
        whl_files = [f for f in ctx.files.wheel if f.path.endswith(".whl")]
        if len(whl_files) != 1:
            fail("wheel target must produce exactly one .whl file, got: %s" % [f.path for f in ctx.files.wheel])
        input_wheel = whl_files[0]
        name_files = [f for f in ctx.files.wheel if f.path.endswith(".whl.name")]
        input_name_file = name_files[0] if name_files else None

    target_environment = None
    if ctx.files.target_environment:
        target_environment = ctx.files.target_environment[0]

    repair_result = register_repair_action(
        ctx,
        input_wheel = input_wheel,
        input_name_file = input_name_file,
        input_wheel_directory = input_wheel_directory,
        native_deps = ctx.attr.native_deps,
        repair_tool = ctx.executable._repair_tool,
        target_environment = target_environment,
    )

    return [
        PycrossWheelInfo(
            wheel_file = repair_result.wheel,
            name_file = repair_result.name_file,
            wheel_directory = repair_result.wheel_directory,
        ),
        DefaultInfo(
            files = depset([repair_result.wheel, repair_result.wheel_directory]),
        ),
    ]

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
