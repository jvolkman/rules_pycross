"""Pycross providers."""

PycrossWheelInfo = provider(
    doc = "Information about a Python wheel.",
    fields = {
        "name_file": "File: A file containing the canonical name of the wheel.",
        "wheel_file": "File: The wheel file itself.",
    },
)

PycrossBuildRecipeInfo = provider(
    doc = "Describes a build recipe for pycross_wheel_build.",
    fields = {
        "name": "str: Human-readable recipe name.",
        "pre_build_hooks": "list[File]: Executables run before the PEP 517 build.",
        "post_build_hooks": "list[File]: Executables run after the PEP 517 build.",
        "path_tools": "list[struct]: Each has .name (str) and .executable (File).",
        "build_deps": "list[Target]: Python deps this recipe provides.",
        "data": "list[Target]: Additional data files for the build.",
        "required_dep_names": "list[str]: Package names required in user's build deps.",
        "build_env": "dict[str, str]: Extra environment variables.",
        "config_settings": "dict[str, list[str]]: Extra PEP 517 config settings.",
        "recipe_data": "list[struct]: Each has .name (str) and .file (File). Keyed files accessible to hooks.",
        "use_crossenv": "bool: Whether crossenv sysconfig patching is needed.",
        "parent": "PycrossBuildRecipeInfo or None: Parent recipe.",
    },
)
