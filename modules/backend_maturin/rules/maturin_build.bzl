"""Implementation of the maturin_build rule."""

load(
    "@rules_pycross//pycross:backend.bzl",
    "defer_build_error",
    "extract_wheel_tools",
    "group_tool_deps",
    "make_wheel_tool_aspect",
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

_maturin_tool_aspect = make_wheel_tool_aspect(("maturin",))

def _maturin_build_impl(ctx):
    tool_executables = resolve_path_tools(ctx)
    has_maturin = any(["maturin" in t.name.lower() for t in tool_executables])
    tool_deps = group_tool_deps(ctx.attr.tool_deps)

    if not has_maturin:
        extracted, missing_errors = extract_wheel_tools(tool_deps, ("maturin",))
        if missing_errors:
            return defer_build_error(ctx, missing_errors)
        tool_executables.extend(extracted)

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
            aspects = [_maturin_tool_aspect],
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
