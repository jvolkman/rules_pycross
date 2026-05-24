"""Build profile for Meson-based Python packages.

This profile generates pycross_wheel_build + pycross_wheel_library targets
configured for packages that use meson-python (mesonpy) as their build backend.
"""

load(
    "//pycross:defs.bzl",
    "pycross_cc_mixin",
    "pycross_console_script_binary",
    "pycross_pep517_build",
    "pycross_repaired_wheel",
    "pycross_wheel_bin_tool",
    "pycross_wheel_library",
)
load(
    "//pycross/profiles:util.bzl",
    "glean_repo_name",
)

def meson_build(
        name,
        sdist,
        native_deps = [],
        copts = [],
        linkopts = [],
        build_deps = None,
        deps = [],
        path_tools = [],
        tool_deps = {},
        repo = None,
        config_settings = {},
        pkg_config_files = [],
        sdist_python_paths = [],
        visibility = None,
        tags = []):
    """Build profile for Meson-based Python packages.

    This profile generates a 3-stage compilation/link/repair pipeline
    and registers the final wheel as a library.

    Args:
      name: Name of the final library target.
      sdist: The sdist label to build.
      native_deps: CC dependencies to link against.
      copts: Extra C++ compiler options.
      linkopts: Extra linker options.
      build_deps: Build dependencies required for PEP 517 package.
      deps: Additional Python runtime dependencies.
      path_tools: Executable tools to put on PATH during build.
      tool_deps: Custom overrides for standard build tools.
      repo: Optional central lock repository name.
      config_settings: Meson setup configuration arguments.
      pkg_config_files: Pkg-config files to copy to package directory.
      sdist_python_paths: Sdist-relative paths to add to PYTHONPATH during the build.
      visibility: Target visibility.
      tags: Target tags.
    """
    mixins = []
    cc_mixin_name = name + "_cc_mixin"
    build_name = name + "_build"

    # If repo is not explicitly passed, try to glean it from sdist
    if not repo:
        repo_name = glean_repo_name(sdist)
        repo = "@" + repo_name if repo_name else None

    # Ensure repo has a leading '@' if defined
    if repo and not repo.startswith("@"):
        repo = "@" + repo

    # Define standard built-in default targets
    default_tools = {
        "meson": repo + "//_builtins:meson" if repo else "//:meson",
        "meson-python": repo + "//_builtins:meson-python" if repo else "//:meson-python",
        "ninja": repo + "//_builtins:ninja" if repo else "//:ninja",
    }

    # Merge user-provided overrides
    tools = {}
    for tool, default_target in default_tools.items():
        if tool in tool_deps:
            tools[tool] = tool_deps[tool]
        else:
            tools[tool] = default_target

    # 1. Compute build_deps
    if not build_deps:
        build_deps = [
            tools["meson"],
            tools["meson-python"],
        ]

    # 2. Automate ninja wrapper
    has_ninja = False
    for tool in path_tools:
        if "ninja" in str(tool).lower():
            has_ninja = True
            break

    actual_path_tools = list(path_tools)
    if not has_ninja:
        ninja_wrapper_name = name + "_ninja_wrapper"

        # Extract the raw pre-compiled ninja binary directly from the installed
        # wheel library (e.g., @uv//_builtins:ninja -> @uv//:ninja site-packages).
        pycross_wheel_bin_tool(
            name = ninja_wrapper_name,
            wheel = tools["ninja"],
            binary_name = "ninja",
            visibility = ["//visibility:private"],
        )
        actual_path_tools.append(":" + ninja_wrapper_name)

    # 3. Automate meson wrapper
    has_meson = False
    for tool in path_tools:
        if "meson" in str(tool).lower() and "meson-python" not in str(tool).lower():
            has_meson = True
            break

    if not has_meson:
        meson_wrapper_name = "meson"
        if repo:
            meson_wheel = repo + "//meson:wheel"
            meson_dep = repo + "//:meson"
        else:
            meson_wheel = "//meson:wheel"
            meson_dep = "//:meson"

        pycross_console_script_binary(
            name = meson_wrapper_name,
            wheel = meson_wheel,
            script = "meson",
            deps = [meson_dep],
            visibility = ["//visibility:private"],
        )
        actual_path_tools.append(":" + meson_wrapper_name)

    # 4. Automate cython wrapper (only if cython is in build_deps)
    has_cython = False
    for tool in path_tools:
        if "cython" in str(tool).lower():
            has_cython = True
            break

    if not has_cython:
        needs_cython = False
        for dep in build_deps:
            dep_str = str(dep).lower()
            if "cython" in dep_str and "cythonize" not in dep_str:
                needs_cython = True
                break

        if needs_cython:
            cython_wrapper_name = "cython"
            if repo:
                cython_wheel = repo + "//cython:wheel"
                cython_dep = repo + "//:cython"
            else:
                cython_wheel = "//cython:wheel"
                cython_dep = "//:cython"

            pycross_console_script_binary(
                name = cython_wrapper_name,
                wheel = cython_wheel,
                script = "cython",
                deps = [cython_dep],
                visibility = ["//visibility:private"],
            )
            actual_path_tools.append(":" + cython_wrapper_name)

    # Stage 1: Extract CC toolchains and static libs into a Mixin
    if native_deps or copts or linkopts:
        pycross_cc_mixin(
            name = cc_mixin_name,
            deps = native_deps,
            copts = copts,
            linkopts = linkopts,
            visibility = ["//visibility:private"],
        )
        mixins.append(":" + cc_mixin_name)

    merged_deps = []
    seen = {}
    for d in (build_deps or []) + (deps or []):
        if d not in seen:
            seen[d] = True
            merged_deps.append(d)

    # Stage 2: Build wheel via PEP 517
    pycross_pep517_build(
        name = build_name,
        sdist = sdist,
        builder = "@rules_pycross//pycross/private/build/tools:meson_builder",
        mixins = mixins,
        deps = merged_deps,
        config_settings = config_settings,
        pkg_config_files = pkg_config_files,
        sdist_python_paths = sdist_python_paths,
        path_tools = actual_path_tools,
        visibility = ["//visibility:private" if native_deps else "//visibility:public"],
        tags = tags,
    )

    needs_repair = bool(native_deps)
    if needs_repair:
        # Stage 3: Repair wheel (bundle native shared libraries)
        repaired_wheel_name = name + "_repaired"
        pycross_repaired_wheel(
            name = repaired_wheel_name,
            wheel = ":" + build_name,
            native_deps = native_deps,
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
