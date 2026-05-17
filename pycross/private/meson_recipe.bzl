"""Specialized Meson build recipe macro for pycross_wheel_build.

Exposes a clean, first-class Starlark API with a generic cross_properties dictionary.
Provides a high-leverage macro that automatically instantiates user-space ninja wrappers,
enabling seamless cross-compilation of Meson packages without rules_pycross having
a bootstrap dependency on ninja.
"""

load(":build_recipe.bzl", "pycross_build_recipe")
load(":ninja_wrapper.bzl", "ninja_wrapper")

def _pycross_meson_properties_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + "_properties.json")
    ctx.actions.write(out, json.encode(ctx.attr.cross_properties))
    return [DefaultInfo(files = depset([out]))]

_pycross_meson_properties = rule(
    implementation = _pycross_meson_properties_impl,
    attrs = {
        "cross_properties": attr.string_dict(
            doc = "Dictionary of properties to inject into the Meson cross-file properties section.",
            mandatory = True,
        ),
    },
)

def pycross_meson_recipe(
        name,
        lock_repo = None,
        ninja = None,
        build_deps = [],
        cross_properties = {},
        pre_build_hooks = [],
        post_build_hooks = [],
        path_tools = {},
        recipe_data = {},
        parent = Label("//pycross/recipes:meson"),
        use_crossenv = True,
        **kwargs):
    """Defines a Meson-backed build recipe for pycross_wheel_build.

    When `lock_repo` is specified, the macro auto-fills `ninja` and `build_deps`
    from the user's lock repository using conventional package names:

        pycross_meson_recipe(
            name = "my_meson",
            lock_repo = "@uv",
        )
        # Equivalent to:
        #   ninja = "@uv//:ninja"
        #   build_deps = ["@uv//:meson-python", "@uv//:meson"]

    Without `lock_repo`, the user must provide deps explicitly via `build_deps`
    on the recipe or `deps` on `pycross_wheel_build`.

    Explicit values for `ninja` and `build_deps` always take precedence over
    `lock_repo` defaults.

    Args:
      name: The name of the recipe target.
      lock_repo: Lock repository name (e.g., "@uv"). When set, auto-fills
          ninja, meson-python, and meson as build_deps.
      ninja: The ninja target to wrap and put on PATH. Also added to build_deps.
          Defaults to `lock_repo + "//:ninja"` when lock_repo is set.
      build_deps: Python dependencies this recipe provides to the build
          environment. Defaults to meson-python and meson from lock_repo.
      cross_properties: A dictionary of properties to inject into the Meson cross-file.
      pre_build_hooks: Executables to run before the PEP 517 build.
      post_build_hooks: Executables to run after the PEP 517 build.
      path_tools: A dictionary of executable targets to names on PATH.
      recipe_data: A mapping of file targets to logical names staged at build-time.
      parent: The parent build recipe target.
      use_crossenv: Whether to use crossenv sysconfig patching.
      **kwargs: Extra attributes passed to the underlying pycross_build_recipe.
    """
    actual_path_tools = dict(path_tools)
    actual_recipe_data = dict(recipe_data)
    actual_build_deps = list(build_deps)

    # Auto-fill from lock_repo when explicit values aren't provided.
    if lock_repo:
        if not ninja:
            ninja = lock_repo + "//:ninja"
        if not build_deps:
            actual_build_deps = [
                lock_repo + "//:meson-python",
                lock_repo + "//:meson",
            ]

    if ninja:
        ninja_wrapper(
            name = name + "_ninja_wrapper",
            ninja = ninja,
            visibility = ["//visibility:private"],
        )
        actual_path_tools[":" + name + "_ninja_wrapper"] = "ninja"

        # Also add ninja as a build_dep so its Python package is importable
        # in the build venv (the wrapper needs `import ninja` to find the binary).
        if ninja not in actual_build_deps:
            actual_build_deps.append(ninja)

    if cross_properties:
        _pycross_meson_properties(
            name = name + "_properties_json",
            cross_properties = cross_properties,
            visibility = ["//visibility:private"],
        )
        actual_recipe_data[":" + name + "_properties_json"] = "meson/cross_properties.json"

    pycross_build_recipe(
        name = name,
        parent = parent,
        build_deps = actual_build_deps,
        pre_build_hooks = pre_build_hooks,
        post_build_hooks = post_build_hooks,
        path_tools = actual_path_tools,
        recipe_data = actual_recipe_data,
        use_crossenv = use_crossenv,
        **kwargs
    )
