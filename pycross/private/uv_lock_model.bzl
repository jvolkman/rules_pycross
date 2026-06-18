"""Translator execution logic for uv lock files."""

load(":internal_repo.bzl", "exec_internal_tool")

TRANSLATOR_TOOL = Label("//pycross/private/tools:uv_translator.py")

def handle_args(attrs, project_file, lock_file, output):
    """Parses uv specific arguments and returns a list of arguments.

    Args:
        attrs: The rule attributes.
        project_file: The project file.
        lock_file: The lock file.
        output: The output file.

    Returns:
        A list of arguments.
    """
    args = []
    args.extend(["--project-file", project_file])
    args.extend(["--lock-file", lock_file])
    args.extend(["--output", output])

    if attrs.default_group:
        args.append("--default-group")

    for group in attrs.optional_groups:
        args.extend(["--optional-group", group])

    if attrs.all_optional_groups:
        args.append("--all-optional-groups")

    for group in attrs.development_groups:
        args.extend(["--development-group", group])

    if attrs.all_development_groups:
        args.append("--all-development-groups")

    if attrs.require_static_urls:
        args.append("--require-static-urls")

    return args

def repo_create_uv_model(rctx, project_file, lock_file, lock_model, output):
    """Run the uv lock translator.

    Args:
        rctx: The repository_ctx or module_ctx object.
        project_file: The pyproject.toml file.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_uv_lock_model rule.
        output: the output file.
    """

    args = handle_args(
        lock_model,
        str(rctx.path(project_file)),
        str(rctx.path(lock_file)),
        output,
    )

    exec_internal_tool(
        rctx,
        TRANSLATOR_TOOL,
        args,
    )
