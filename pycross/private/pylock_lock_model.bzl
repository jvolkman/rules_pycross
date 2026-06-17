"""Translator execution logic for pylock files."""

load(":internal_repo.bzl", "exec_internal_tool")

TRANSLATOR_TOOL = Label("//pycross/private/tools:pylock_translator.py")

def handle_args(lock_model, project_file, lock_file, output):
    """Parses pylock specific arguments and returns a list of arguments.

    Args:
        lock_model: A struct containing the lock model attributes.
        project_file: The pyproject.toml file path (optional).
        lock_file: The lock file path.
        output: The output file path.

    Returns:
        A list of arguments for the translator tool.
    """
    args = []
    if project_file:
        args.extend(["--project-file", project_file])
    args.extend(["--lock-file", lock_file])
    args.extend(["--output", output])

    if lock_model.default:
        args.append("--default")
    else:
        args.append("--no-default")

    if lock_model.all_optional_groups:
        args.append("--all-optional-groups")
    else:
        for group in lock_model.optional_groups:
            args.extend(["--optional-group", group])

    if getattr(lock_model, "all_development_groups", False):
        args.append("--all-development-groups")
    else:
        for group in getattr(lock_model, "development_groups", []):
            args.extend(["--development-group", group])

    return args

def repo_create_pylock_model(rctx, project_file, lock_file, lock_model, output):
    """Run the pylock translator.

    Args:
        rctx: The repository_ctx or module_ctx object.
        project_file: The pyproject.toml file (optional).
        lock_file: The lock file.
        lock_model: a struct containing the same attrs as the pycross_pylock_lock_model rule.
        output: the output file.
    """

    project_file_path = str(rctx.path(project_file)) if project_file else None

    args = handle_args(
        lock_model,
        project_file_path,
        str(rctx.path(lock_file)),
        output,
    )

    exec_internal_tool(
        rctx,
        TRANSLATOR_TOOL,
        args,
    )
