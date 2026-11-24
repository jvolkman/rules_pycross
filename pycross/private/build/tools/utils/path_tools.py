import os
import shlex
from pathlib import Path

from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.venv_utils import venv_python_path


def _has_bazel_runfiles(path: Path) -> bool:
    """Return True if path is a Bazel executable with an adjacent runfiles tree or manifest."""
    return (path.parent / (path.name + ".runfiles")).is_dir() or (
        path.parent / (path.name + ".runfiles_manifest")
    ).is_file()


def _is_python_tool(path: Path) -> bool:
    if _has_bazel_runfiles(path):
        return False
    if path.suffix == ".py":
        return True
    if path.suffix == "":
        try:
            with open(path, "rb") as f:
                header = f.read(2)
                if header == b"#!":
                    shebang = f.readline().decode("utf-8", "replace")
                    return "python" in shebang
        except OSError:
            pass
    return False


def setup_path_tools(ctx: BuildContext) -> None:
    """Configure custom PATH directory with symlinked execution tools."""
    ctx.tools_dir.mkdir(parents=True, exist_ok=True)

    for tool in ctx.path_tools:
        name = tool["name"]
        dest_path = ctx.tools_dir / name

        if os.path.lexists(dest_path):
            continue

        abs_tool_path = tool["path"].absolute()
        if _has_bazel_runfiles(abs_tool_path):
            # Invoke Bazel executables directly through a thin exec wrapper so
            # argv[0] preserves the binary's original path (and adjacent
            # .runfiles tree/manifest) even when pycross_path_tool renames it,
            # and never hijack a Bazel py_binary into the build venv.
            sh_wrapper = (
                "#!/bin/sh\n"
                "unset RUNFILES_DIR RUNFILES_MANIFEST_FILE RUNFILES_MANIFEST_ONLY _PYTHON_SYSCONFIGDATA_NAME\n"
                f'exec {shlex.quote(str(abs_tool_path))} "$@"\n'
            )
            dest_path.write_text(sh_wrapper)
            dest_path.chmod(0o755)
            continue

        if not _is_python_tool(abs_tool_path):
            dest_path.symlink_to(abs_tool_path)
            continue

        venv_python = venv_python_path(ctx.env_dir)
        # Use a POSIX /bin/sh wrapper directly exec'ing the venv Python. This
        # bypasses Linux's 127-character shebang limit without spawning an
        # intermediate Python process.
        sh_wrapper = (
            f'#!/bin/sh\nexec {shlex.quote(str(venv_python.absolute()))} {shlex.quote(str(abs_tool_path))} "$@"\n'
        )
        dest_path.write_text(sh_wrapper)
        dest_path.chmod(0o755)
