"""Build profile for Flit-based Python packages."""

load("//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library")
load("//pycross/profiles:util.bzl", "glean_repo_name")

def flit_build(name, sdist = None, build_deps = None, tool_deps = {}, repo = None, **kwargs):
    """Build profile for Flit-based packages.

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

    build_name = name + "_build"
    if "manual" not in tags:
        tags.append("manual")

    # If repo is not explicitly passed, try to glean it from sdist
    if not repo:
        repo_name = glean_repo_name(sdist)
        repo = "@" + repo_name if repo_name else None

    # Ensure repo has a leading '@' if defined
    if repo and not repo.startswith("@"):
        repo = "@" + repo

    # Define standard built-in default targets for flit
    default_tools = {
        "flit-core": repo + "//_builtins:flit-core" if repo else "//:flit-core",
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
            tools["flit-core"],
        ]

    merged_deps = []
    seen = {}
    for d in (build_deps or []) + (deps or []):
        if d not in seen:
            seen[d] = True
            merged_deps.append(d)

    pycross_wheel_build(
        name = build_name,
        sdist = sdist,
        deps = merged_deps,
        visibility = ["//visibility:public"],
        tags = tags,
        **kwargs
    )

    pycross_wheel_library(
        name = name,
        wheel = ":" + build_name,
        deps = deps,
        visibility = visibility,
    )

    native.alias(
        name = "wheel",
        actual = ":" + build_name,
        visibility = ["//visibility:public"],
        tags = tags,
    )
