"""Implementation of the maturin_build rule."""

load(
    "@rules_pycross//pycross:backend.bzl",
    "PycrossExtractedWheelInfo",
    "PycrossPackageInfo",
    "TOOL_EXTRACT_ATTRS",
    "defer_build_error",
    "get_unzipped_wheel",
    "group_tool_deps",
    "register_bin_extract_action",
    "resolve_path_tools",
)
load(
    "//private:rust_layer.bzl",
    "RUST_BUILD_COMMON_ATTRS",
    "RUST_BUILD_FRAGMENTS",
    "RUST_BUILD_TOOLCHAINS",
    "run_rust_pep517_build",
    "rust_tool_deps_attr",
)

_MaturinToolInfo = provider(
    doc = "Extracted maturin executable from a maturin wheel target.",
    fields = {
        "name": "str: executable name.",
        "file": "File: extracted executable file.",
    },
)

def _extract_maturin_aspect_impl(target, ctx):
    if PycrossPackageInfo not in target or PycrossExtractedWheelInfo not in target:
        return []
    if target[PycrossPackageInfo].package_name != "maturin":
        return []
    tool = register_bin_extract_action(
        ctx,
        wheel_dir = target[PycrossExtractedWheelInfo].site_packages,
        binary_name = "maturin",
    )
    return [_MaturinToolInfo(name = tool.name, file = tool.file)]

_extract_maturin_aspect = aspect(
    implementation = _extract_maturin_aspect_impl,
    attrs = TOOL_EXTRACT_ATTRS,
)

def _maturin_build_impl(ctx):
    tool_executables = resolve_path_tools(ctx)
    has_maturin = any(["maturin" in t.name.lower() for t in tool_executables])
    tool_deps = group_tool_deps(ctx.attr.tool_deps)

    if not has_maturin:
        if "maturin" not in tool_deps:
            return defer_build_error(ctx, ["Missing 'maturin' in tool_deps"])
        maturin_target = tool_deps["maturin"][0]
        if _MaturinToolInfo in maturin_target:
            info = maturin_target[_MaturinToolInfo]
            tool_executables.append(struct(name = info.name, file = info.file))
        else:
            # Validates PycrossExtractedWheelInfo and fails with a clear message if missing.
            get_unzipped_wheel(maturin_target)
            fail("Expected _MaturinToolInfo on 'maturin' tool target {}".format(maturin_target.label))

    return run_rust_pep517_build(
        ctx,
        tool_deps = tool_deps,
        tool_executables = tool_executables,
        tool_pkg_names = ["maturin"],
    )

maturin_build = rule(
    implementation = _maturin_build_impl,
    attrs = RUST_BUILD_COMMON_ATTRS | {
        "tool_deps": rust_tool_deps_attr(
            "Python build tool packages (`maturin`). " +
            "The generated `@<repo>//_backend` macro fills these in from the lock file.",
            aspects = [_extract_maturin_aspect],
        ),
        "_builder": attr.label(
            default = "@rules_pycross_backend_maturin//private/tools:maturin_builder",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = RUST_BUILD_TOOLCHAINS,
    fragments = RUST_BUILD_FRAGMENTS,
)
