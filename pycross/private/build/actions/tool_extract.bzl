"""Action logic for extracting executables from wheel tree artifacts."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//pycross/private:providers.bzl", "PycrossExtractedWheelInfo", "PycrossPackageInfo")

PycrossExtractedToolInfo = provider(
    doc = "Extracted tool executable from a wheel package target.",
    fields = {
        "name": "str: executable name to place on PATH.",
        "file": "File: extracted executable file.",
    },
)

def register_console_script_extract_action(ctx, site_packages, script_name):
    """Extracts a console script from a wheel as an executable file.

    Args:
        ctx: The rule or aspect context.
        site_packages: File, the tree artifact of the extracted site_packages directory.
        script_name: str, name of the console script.

    Returns:
        struct(
            name = str,
            file = File,
        )
    """
    out_file = ctx.actions.declare_file(paths.join(ctx.label.name + "_tools", script_name))

    args = ctx.actions.args()
    args.add_all([site_packages], before_each = "--site-packages", expand_directories = False)
    args.add("--script", script_name)
    args.add("--out", out_file)

    ctx.actions.run(
        executable = ctx.executable._extract_console_script,
        arguments = [args],
        inputs = [site_packages],
        outputs = [out_file],
        mnemonic = "PycrossExtractConsoleScript",
        execution_requirements = {"supports-path-mapping": "1"},
        progress_message = "Extracting console script %s" % script_name,
    )

    return struct(
        name = script_name,
        file = out_file,
    )

def register_bin_extract_action(ctx, wheel_dir, binary_name):
    """Extracts a native binary from a wheel's bin/ directory.

    Args:
        ctx: The rule or aspect context.
        wheel_dir: File, the tree artifact of the unzipped wheel.
        binary_name: str, name of the binary.

    Returns:
        struct(
            name = str,
            file = File,
        )
    """
    out_file = ctx.actions.declare_file(paths.join(ctx.label.name + "_tools", binary_name))

    args = ctx.actions.args()
    args.add_all([wheel_dir], expand_directories = False)
    args.add(binary_name)
    args.add(out_file)

    ctx.actions.run(
        inputs = [wheel_dir],
        outputs = [out_file],
        executable = ctx.executable._extract_wheel_bin,
        arguments = [args],
        mnemonic = "PycrossExtractWheelBin",
        execution_requirements = {"supports-path-mapping": "1"},
        progress_message = "Extracting binary %s" % binary_name,
    )

    return struct(
        name = binary_name,
        file = out_file,
    )

# Known build tool packages whose executables are extracted once on the tool
# target itself rather than re-extracted per sdist build target.
_WHEEL_TOOL_SPECS = {
    "cmake": ("console_script", "cmake"),
    "meson": ("console_script", "meson"),
    "ninja": ("bin", "ninja"),
}

def _extract_wheel_tool_aspect_impl(target, ctx):
    if PycrossPackageInfo not in target or PycrossExtractedWheelInfo not in target:
        return []

    spec = _WHEEL_TOOL_SPECS.get(target[PycrossPackageInfo].package_name)
    if not spec:
        return []

    kind, tool_name = spec
    wheel_dir = target[PycrossExtractedWheelInfo].site_packages
    if kind == "console_script":
        tool = register_console_script_extract_action(ctx, wheel_dir, tool_name)
    else:
        tool = register_bin_extract_action(ctx, wheel_dir, tool_name)

    return [PycrossExtractedToolInfo(name = tool.name, file = tool.file)]

extract_wheel_tool_aspect = aspect(
    implementation = _extract_wheel_tool_aspect_impl,
    attrs = {
        "_extract_console_script": attr.label(
            default = Label("//pycross/private/tools:extract_console_script"),
            executable = True,
            cfg = "exec",
        ),
        "_extract_wheel_bin": attr.label(
            default = Label("//pycross/private/tools:extract_wheel_bin"),
            executable = True,
            cfg = "exec",
        ),
    },
)
