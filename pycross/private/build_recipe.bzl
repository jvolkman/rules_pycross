"""Build recipe rule for pycross_wheel_build.

A build recipe encapsulates build-system-specific configuration for building
Python wheels from source distributions. Recipes form a single-inheritance
chain via the `parent` attribute, allowing layered composition:

    crossenv (root) -> meson -> user's custom recipe

The `pycross_wheel_build` rule consumes a recipe target and flattens the chain
at analysis time, producing ordered hook lists and merged configuration.
"""

load("@rules_python//python:py_info.bzl", "PyInfo")
load(":providers.bzl", "PycrossBuildRecipeInfo")

# Attributes shared between pycross_build_recipe and pycross_wheel_build.
# This ensures both rules accept the same configuration surface.
RECIPE_ATTRS = {
    "pre_build_hooks": attr.label_list(
        doc = "Executables run before the PEP 517 build.",
        cfg = "exec",
    ),
    "post_build_hooks": attr.label_list(
        doc = "Executables run after the PEP 517 build.",
        cfg = "exec",
    ),
    "path_tools": attr.label_keyed_string_dict(
        doc = "A mapping of executable targets to names placed on PATH during the build.",
        cfg = "exec",
    ),
    "build_env": attr.string_dict(
        doc = (
            "Environment variables set during the build. " +
            "Values are subject to 'Make variable', location, and build_cwd_token expansion."
        ),
    ),
    "config_settings": attr.string_list_dict(
        doc = (
            "PEP 517 config settings passed to the build backend. " +
            "Values are subject to 'Make variable', location, and build_cwd_token expansion."
        ),
    ),
    "recipe_data": attr.label_keyed_string_dict(
        doc = (
            "A mapping of file targets to logical names. Files are staged into " +
            "PYCROSS_RECIPE_DATA_DIR and accessible to hooks by their logical name. " +
            "Use namespaced names (e.g., 'meson/cross_properties.json') to avoid collisions."
        ),
        allow_files = True,
    ),
}

def _executable(target):
    exe = target[DefaultInfo].files_to_run.executable
    if not exe:
        fail("%s is not executable" % target.label)
    return exe


def _pycross_build_recipe_impl(ctx):
    parent = None
    if ctx.attr.parent:
        parent = ctx.attr.parent[PycrossBuildRecipeInfo]

    # Store both executable (for args) and files_to_run (for sandbox runfiles)
    pre_build_hooks = [
        struct(executable = _executable(h), files_to_run = h[DefaultInfo].files_to_run)
        for h in ctx.attr.pre_build_hooks
    ]
    post_build_hooks = [
        struct(executable = _executable(h), files_to_run = h[DefaultInfo].files_to_run)
        for h in ctx.attr.post_build_hooks
    ]

    # Collect path_tools as structs with name, executable, and files_to_run
    path_tools = []
    for tool, name in ctx.attr.path_tools.items():
        path_tools.append(struct(
            name = name,
            executable = _executable(tool),
            files_to_run = tool[DefaultInfo].files_to_run,
        ))

    # Collect recipe_data as structs with name and file
    recipe_data = []
    for target, name in ctx.attr.recipe_data.items():
        files = target[DefaultInfo].files.to_list()
        if len(files) != 1:
            fail("recipe_data target %s must provide exactly one file" % target.label)
        recipe_data.append(struct(name = name, file = files[0]))

    recipe_info = PycrossBuildRecipeInfo(
        name = ctx.attr.recipe_name or ctx.label.name,
        pre_build_hooks = pre_build_hooks,
        post_build_hooks = post_build_hooks,
        path_tools = path_tools,
        build_deps = ctx.attr.build_deps,
        data = ctx.attr.data,
        required_dep_names = ctx.attr.required_dep_names,
        build_env = ctx.attr.build_env,
        config_settings = ctx.attr.config_settings,
        recipe_data = recipe_data,
        use_crossenv = ctx.attr.use_crossenv,
        parent = parent,
    )

    # Collect all transitive files AND runfiles needed by the recipe chain.
    all_files = []
    runfiles = ctx.runfiles()
    for h in ctx.attr.pre_build_hooks + ctx.attr.post_build_hooks:
        all_files.append(h[DefaultInfo].files)
        if h[DefaultInfo].default_runfiles:
            runfiles = runfiles.merge(h[DefaultInfo].default_runfiles)
    for tool in ctx.attr.path_tools.keys():
        all_files.append(tool[DefaultInfo].files)
        if tool[DefaultInfo].default_runfiles:
            runfiles = runfiles.merge(tool[DefaultInfo].default_runfiles)
    for dep in ctx.attr.build_deps:
        all_files.append(dep[DefaultInfo].files)
    for data in ctx.attr.data:
        all_files.append(data[DefaultInfo].files)
    for rd_target in ctx.attr.recipe_data.keys():
        all_files.append(rd_target[DefaultInfo].files)

    # Include parent's files and runfiles
    if ctx.attr.parent:
        all_files.append(ctx.attr.parent[DefaultInfo].files)
        if ctx.attr.parent[DefaultInfo].default_runfiles:
            runfiles = runfiles.merge(ctx.attr.parent[DefaultInfo].default_runfiles)

    return [
        recipe_info,
        DefaultInfo(
            files = depset(transitive = all_files),
            runfiles = runfiles,
        ),
    ]

pycross_build_recipe = rule(
    implementation = _pycross_build_recipe_impl,
    doc = """Defines a build recipe for pycross_wheel_build.

Recipes encapsulate build-system-specific hooks, dependencies, environment
variables, and config settings. They form a single-inheritance chain via
the `parent` attribute.

Example:
    pycross_build_recipe(
        name = "meson",
        parent = "@rules_pycross//pycross/recipes:crossenv",
        pre_build_hooks = [":generate_cross_file"],
        required_dep_names = ["meson-python"],
    )
""",
    attrs = dict(
        RECIPE_ATTRS,
        recipe_name = attr.string(
            doc = "Human-readable recipe name. Defaults to the target name.",
        ),
        parent = attr.label(
            doc = "Parent recipe. This recipe's pre-build hooks run after the parent's.",
            providers = [PycrossBuildRecipeInfo],
        ),
        build_deps = attr.label_list(
            doc = "Python dependencies this recipe provides to the build environment.",
            providers = [PyInfo],
        ),
        data = attr.label_list(
            doc = "Additional data files available at build time.",
            allow_files = True,
        ),
        required_dep_names = attr.string_list(
            doc = "Package names that must be present in the user's build deps (validated at build time).",
        ),
        use_crossenv = attr.bool(
            doc = "Whether this recipe needs crossenv sysconfig patching.",
            default = False,
        ),
    ),
)

def flatten_recipe_chain(recipe_info):
    """Flattens a recipe parent chain into merged, ordered configuration.

    Walks the parent chain from leaf to root, reverses it, and produces:
      - pre_build_hooks: root's hooks first, leaf's hooks last
      - post_build_hooks: leaf's hooks first, root's hooks last
      - path_tools: merged (child overrides parent for same name)
      - build_deps: union of all
      - required_dep_names: union of all
      - build_env: merged (child overrides parent)
      - config_settings: merged (child extends parent lists)
      - use_crossenv: True if ANY recipe in chain sets it

    Args:
        recipe_info: A PycrossBuildRecipeInfo provider.

    Returns:
        struct with the flattened fields.
    """
    # Build chain from leaf to root, then reverse to get root-first order
    chain = []
    node = recipe_info
    for _ in range(100):  # Guard against infinite loops
        if not node:
            break
        chain.append(node)
        node = node.parent

    # Reverse: chain[0] = root, chain[-1] = leaf
    reversed_chain = []
    for i in range(len(chain) - 1, -1, -1):
        reversed_chain.append(chain[i])

    all_pre_hooks = []
    all_post_hooks = []
    all_build_deps = []
    all_required = []
    merged_env = {}
    merged_config = {}
    needs_crossenv = False

    # path_tools: keyed by name, child overrides parent
    path_tools_by_name = {}

    # recipe_data: keyed by logical name, child overrides parent
    recipe_data_by_name = {}

    for recipe in reversed_chain:
        all_pre_hooks.extend(recipe.pre_build_hooks)
        # Post hooks: prepend so leaf ends up first
        all_post_hooks = list(recipe.post_build_hooks) + all_post_hooks
        all_build_deps.extend(recipe.build_deps)
        all_required.extend(recipe.required_dep_names)
        merged_env.update(recipe.build_env)
        for k, v in recipe.config_settings.items():
            if k in merged_config:
                merged_config[k] = merged_config[k] + v
            else:
                merged_config[k] = list(v)
        for pt in recipe.path_tools:
            path_tools_by_name[pt.name] = pt
        for rd in recipe.recipe_data:
            recipe_data_by_name[rd.name] = rd
        if recipe.use_crossenv:
            needs_crossenv = True

    return struct(
        pre_build_hooks = all_pre_hooks,
        post_build_hooks = all_post_hooks,
        path_tools = path_tools_by_name,
        build_deps = all_build_deps,
        required_dep_names = all_required,
        build_env = merged_env,
        config_settings = merged_config,
        recipe_data = recipe_data_by_name,
        use_crossenv = needs_crossenv,
    )
