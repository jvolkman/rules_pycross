"""Action logic for extracting executables from wheel tree artifacts."""

load("@bazel_skylib//lib:paths.bzl", "paths")

def register_console_script_extract_action(ctx, wheel, script_name):
    """Extracts a console script from a wheel as an executable file.

    Args:
        ctx: The rule context.
        wheel: File, the tree artifact of the unzipped wheel.
        script_name: str, name of the console script.

    Returns:
        struct(
            name = str,
            file = File,
        )
    """
    out_file = ctx.actions.declare_file(paths.join(ctx.attr.name + "_tools", script_name))

    args = ctx.actions.args()
    args.add(wheel.path)
    args.add(script_name)
    args.add(out_file.path)

    ctx.actions.run(
        executable = ctx.executable._extract_console_script,
        arguments = [args],
        inputs = [wheel],
        outputs = [out_file],
        mnemonic = "PycrossExtractConsoleScript",
        progress_message = "Extracting console script %s" % script_name,
    )

    return struct(
        name = script_name,
        file = out_file,
    )

def register_bin_extract_action(ctx, wheel_dir, binary_name):
    """Extracts a native binary from a wheel's bin/ directory.

    Args:
        ctx: The rule context.
        wheel_dir: File, the tree artifact of the unzipped wheel.
        binary_name: str, name of the binary.

    Returns:
        struct(
            name = str,
            file = File,
        )
    """
    out_file = ctx.actions.declare_file(paths.join(ctx.attr.name + "_tools", binary_name))

    ctx.actions.run_shell(
        inputs = [wheel_dir],
        outputs = [out_file],
        command = "cp \"$1/bin/$2\" \"$3\" && chmod +x \"$3\"",
        arguments = [wheel_dir.path, binary_name, out_file.path],
        mnemonic = "PycrossExtractWheelBin",
        progress_message = "Extracting binary %s" % binary_name,
    )

    return struct(
        name = binary_name,
        file = out_file,
    )
