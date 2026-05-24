import textwrap

from pycross.private.build.tools.utils.context import BuildContext


def setup_path_tools(ctx: BuildContext) -> None:
    """Configure custom PATH directory with symlinked execution tools."""
    ctx.tools_dir.mkdir(parents=True, exist_ok=True)

    for tool in ctx.path_tools:
        name = tool["name"]
        src_path = tool["path"]
        dest_path = ctx.tools_dir / name

        if not dest_path.exists():
            abs_tool_path = src_path.absolute()
            is_python_tool = abs_tool_path.suffix == ".py"
            if not is_python_tool and abs_tool_path.suffix == "":
                try:
                    with open(abs_tool_path, "rb") as f:
                        header = f.read(2)
                        if header == b"#!":
                            shebang = f.readline().decode("utf-8", "replace")
                            is_python_tool = "python" in shebang
                except OSError:
                    pass

            if is_python_tool:
                venv_python = ctx.env_dir / "bin" / "python"
                script_content = textwrap.dedent(f"""\
                #!{ctx.exec_python.absolute()} -S
                import os, sys
                os.execv({repr(str(venv_python.absolute()))}, [{repr(str(venv_python.absolute()))}, {repr(str(abs_tool_path))}] + sys.argv[1:])
                """)
                dest_path.write_text(script_content)
                dest_path.chmod(0o755)
            else:
                dest_path.symlink_to(abs_tool_path)
