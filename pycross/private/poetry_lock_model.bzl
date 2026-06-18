"""Translator execution logic for poetry lock files."""

load(":internal_repo.bzl", "exec_internal_tool")

TRANSLATOR_TOOL = Label("//pycross/private/tools:poetry_translator.py")

def handle_args(attrs, project_file, lock_file, output):
    """Parses poetry specific arguments and returns a list.

    Args:
        attrs: The attributes struct.
        project_file: The project file.
        lock_file: The lock file.
        output: The output file path.

    Returns:
        A list of parsed arguments.
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

    return args

def repo_create_poetry_model(rctx, project_file, lock_file, lock_model, output):
    """Run the poetry lock translator.

    Args:
        rctx: The repository_ctx or module_ctx object.
        project_file: The pyproject.toml file.
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_poetry_lock_model rule.
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
