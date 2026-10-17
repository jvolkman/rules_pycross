"""Implementation of the setuptools_rust_build rule."""

load(
    "@rules_pycross//pycross:backend.bzl",
    "group_tool_deps",
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

def _setuptools_rust_build_impl(ctx):
    tool_executables = resolve_path_tools(ctx)
    tool_deps = group_tool_deps(ctx.attr.tool_deps)

    return run_rust_pep517_build(
        ctx,
        tool_deps = tool_deps,
        tool_executables = tool_executables,
        tool_pkg_names = ["setuptools", "setuptools-rust", "wheel"],
    )

setuptools_rust_build = rule(
    implementation = _setuptools_rust_build_impl,
    attrs = RUST_BUILD_COMMON_ATTRS | {
        "tool_deps": rust_tool_deps_attr(
            "Python build tool packages (`setuptools`, `setuptools-rust` and `wheel`). " +
            "The generated `@<repo>//_backend` macro fills these in from the lock file.",
        ),
        "_builder": attr.label(
            default = "@rules_pycross_backend_maturin//private/tools:setuptools_rust_builder",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = RUST_BUILD_TOOLCHAINS,
    fragments = RUST_BUILD_FRAGMENTS,
)
