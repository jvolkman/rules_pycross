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
    args.add("extract-bin")
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

def _extract_wheel_tool_aspect_impl(target, ctx):
    if PycrossPackageInfo not in target or PycrossExtractedWheelInfo not in target:
        return []

    tool_name = target[PycrossPackageInfo].package_name
    if tool_name not in ctx.attr._tool_names:
        return []

    wheel_dir = target[PycrossExtractedWheelInfo].site_packages
    tool = register_bin_extract_action(ctx, wheel_dir, tool_name)

    return [PycrossExtractedToolInfo(name = tool.name, file = tool.file)]

def make_wheel_tool_aspect(tool_names):
    """Creates an aspect that extracts named executables from wheel tool_deps.

    Assign the returned aspect to a top-level symbol in your `.bzl` file and
    attach it to the rule's `tool_deps` attribute so each tool binary is
    extracted once per tool target rather than once per sdist build target.

    Args:
        tool_names: sequence[str], PEP 503 normalized package/binary names to extract.

    Returns:
        An aspect providing `PycrossExtractedToolInfo` on matching targets.
    """
    return aspect(
        implementation = _extract_wheel_tool_aspect_impl,
        attrs = {
            "_tool_names": attr.string_list(default = list(tool_names)),
            "_extract_wheel_bin": attr.label(
                default = Label("//pycross/private/tools:wheel_file_op"),
                executable = True,
                cfg = "exec",
            ),
        },
    )

def extract_wheel_tools(tool_deps, required_names):
    """Collects aspect-extracted tool executables from grouped tool_deps.

    Args:
        tool_deps: dict[str, list[Target]], targets grouped by `group_tool_deps()`.
        required_names: sequence[str], required tool package names to extract.

    Returns:
        A tuple `(tool_executables, missing_errors)` where `tool_executables` is a
        list of `struct(name, file)` and `missing_errors` is a list of error strings
        for any required tools absent from `tool_deps`.
    """
    missing_errors = ["Missing '{}' in tool_deps".format(t) for t in required_names if t not in tool_deps]
    if missing_errors:
        return ([], missing_errors)

    tool_executables = []
    for tool_pkg in required_names:
        dep = tool_deps[tool_pkg][0]
        if PycrossExtractedToolInfo in dep:
            info = dep[PycrossExtractedToolInfo]
            tool_executables.append(struct(name = info.name, file = info.file))
        elif PycrossExtractedWheelInfo not in dep:
            fail("Target {} does not provide a site_packages directory. Make sure it is wrapped in a pycross_wheel_library.".format(dep.label))
        else:
            fail("Expected PycrossExtractedToolInfo on '{}' tool target {}".format(tool_pkg, dep.label))

    return (tool_executables, [])

# Shared aspect for built-in CMake/Meson tool packages so common tools (e.g.
# ninja) are extracted once across both backends without action conflicts.
extract_wheel_tool_aspect = make_wheel_tool_aspect(("cmake", "meson", "ninja"))
