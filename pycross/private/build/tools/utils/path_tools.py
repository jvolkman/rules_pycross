import shlex
from pathlib import Path

from pycross.private.build.tools.utils.context import BuildContext


def _is_python_tool(path: Path) -> bool:
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

        if dest_path.exists():
            continue

        abs_tool_path = tool["path"].absolute()
        if not _is_python_tool(abs_tool_path):
            dest_path.symlink_to(abs_tool_path)
            continue

        venv_python = ctx.env_dir / "bin" / "python"
        # Use a POSIX /bin/sh wrapper directly exec'ing the venv Python. This
        # bypasses Linux's 127-character shebang limit without spawning an
        # intermediate Python process.
        sh_wrapper = (
            f'#!/bin/sh\nexec {shlex.quote(str(venv_python.absolute()))} {shlex.quote(str(abs_tool_path))} "$@"\n'
        )
        dest_path.write_text(sh_wrapper)
        dest_path.chmod(0o755)
