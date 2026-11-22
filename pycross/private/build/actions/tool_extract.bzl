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

def register_bin_extract_action(ctx, wheel_dir, binary_name):
    """Extracts an executable (native binary or console script) from a wheel's bin/ directory.

    Args:
        ctx: The rule or aspect context.
        wheel_dir: File, the tree artifact of the installed wheel directory.
        binary_name: str, name of the binary or console script.

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
_WHEEL_TOOL_NAMES = {
    "cmake": "cmake",
    "meson": "meson",
    "ninja": "ninja",
}

def _extract_wheel_tool_aspect_impl(target, ctx):
    if PycrossPackageInfo not in target or PycrossExtractedWheelInfo not in target:
        return []

    tool_name = _WHEEL_TOOL_NAMES.get(target[PycrossPackageInfo].package_name)
    if not tool_name:
        return []

    wheel_dir = target[PycrossExtractedWheelInfo].site_packages
    tool = register_bin_extract_action(ctx, wheel_dir, tool_name)

    return [PycrossExtractedToolInfo(name = tool.name, file = tool.file)]

extract_wheel_tool_aspect = aspect(
    implementation = _extract_wheel_tool_aspect_impl,
    attrs = {
        "_extract_wheel_bin": attr.label(
            default = Label("//pycross/private/tools:extract_wheel_bin"),
            executable = True,
            cfg = "exec",
        ),
    },
)
