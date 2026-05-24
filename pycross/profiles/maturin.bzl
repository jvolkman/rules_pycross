"""Build profile for Maturin and PyO3 based Python extensions."""

load(
    "//pycross:defs.bzl",
    "pycross_cc_mixin",
    "pycross_pep517_build",
    "pycross_repaired_wheel",
    "pycross_rust_mixin",
    "pycross_wheel_bin_tool",
    "pycross_wheel_library",
)
load("//pycross/profiles:util.bzl", "glean_repo_name")

def maturin_build(name, sdist = None, build_deps = None, tool_deps = {}, repo = None, **kwargs):
    """Build profile for maturin-based packages.

    Args:
        name: Name of the target.
        sdist: The sdist label to build.
        build_deps: Build dependencies required for PEP 517 package.
        tool_deps: Overrides for standard build tools.
        repo: Optional central lock repository name.
        **kwargs: Additional arguments passed to pycross_wheel_build.
    """
    deps = kwargs.pop("deps", [])
    visibility = kwargs.pop("visibility", None)
    tags = list(kwargs.pop("tags", []))

    if "manual" not in tags:
        tags.append("manual")

    # If repo is not explicitly passed, try to glean it from sdist
    if not repo:
        repo_name = glean_repo_name(sdist)
        repo = "@" + repo_name if repo_name else None

    # Ensure repo has a leading '@' if defined
    if repo and not repo.startswith("@"):
        repo = "@" + repo

    # Define standard built-in default targets for maturin
    default_tools = {
        "maturin": repo + "//_builtins:maturin" if repo else "//:maturin",
    }

    # Merge user-provided overrides
    tools = {}
    for tool, default_target in default_tools.items():
        if tool in tool_deps:
            tools[tool] = tool_deps[tool]
        else:
            tools[tool] = default_target

    # Compute build_deps if not explicitly provided
    if not build_deps:
        build_deps = [
            tools["maturin"],
        ]

    # Merge and deduplicate build_deps and runtime deps
    merged_deps = []
    seen = {}
    for d in (build_deps or []) + (deps or []):
        if d not in seen:
            seen[d] = True
            merged_deps.append(d)

    # Automate maturin binary tool wrapper so 'maturin' command is on PATH inside the sandbox
    actual_path_tools = list(kwargs.pop("path_tools", []))
    has_maturin = False
    for tool in actual_path_tools:
        if "maturin" in str(tool).lower():
            has_maturin = True
            break

    if not has_maturin:
        maturin_wrapper_name = name + "_maturin_wrapper"
        pycross_wheel_bin_tool(
            name = maturin_wrapper_name,
            wheel = tools["maturin"],
            binary_name = "maturin",
            visibility = ["//visibility:private"],
        )
        actual_path_tools.append(":" + maturin_wrapper_name)

    # Extract extra mixin and compiler config attributes
    native_deps = kwargs.pop("native_deps", [])
    copts = kwargs.pop("copts", [])
    linkopts = kwargs.pop("linkopts", [])
    mixins = list(kwargs.pop("mixins", []))

    cc_deps = list(native_deps)

    # Stage 1: Create C++ toolchain mixin if C++ options or dependencies exist
    cc_mixin_name = name + "_cc_mixin"
    if cc_deps or copts or linkopts:
        pycross_cc_mixin(
            name = cc_mixin_name,
            deps = cc_deps,
            copts = copts,
            linkopts = linkopts,
            visibility = ["//visibility:private"],
        )
        mixins.append(":" + cc_mixin_name)

    # Stage 1.5: Create Rust toolchain mixin for Maturin build
    rust_mixin_name = name + "_rust_mixin"
    pycross_rust_mixin(
        name = rust_mixin_name,
        visibility = ["//visibility:private"],
    )
    mixins.append(":" + rust_mixin_name)

    needs_repair = bool(cc_deps)
    build_name = name + "_build"

    # Stage 2: Build wheel via PEP 517 and pluggable maturin_builder
    pycross_pep517_build(
        name = build_name,
        sdist = sdist,
        builder = "@rules_pycross//pycross/private/build/tools:maturin_builder",
        mixins = mixins,
        deps = merged_deps,
        path_tools = actual_path_tools,
        visibility = ["//visibility:private" if needs_repair else "//visibility:public"],
        tags = tags,
        **kwargs
    )

    # Stage 3: Repair wheel if C++ dependencies are linked
    if needs_repair:
        repaired_wheel_name = name + "_repaired"
        pycross_repaired_wheel(
            name = repaired_wheel_name,
            wheel = ":" + build_name,
            native_deps = cc_deps,
            visibility = ["//visibility:public"],
        )
        actual_wheel = ":" + repaired_wheel_name
    else:
        actual_wheel = ":" + build_name

    # Stage 4: Expose final wheel library
    pycross_wheel_library(
        name = name,
        wheel = actual_wheel,
        deps = deps,
        visibility = visibility,
    )
