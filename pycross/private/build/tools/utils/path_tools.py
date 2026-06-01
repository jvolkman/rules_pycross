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
                py_script_path = ctx.tools_dir / (name + ".py")
                # We use a 4-hop chain (bash -> python wrapper -> execv -> venv python -> tool script)
                # to execute tools. This bypasses Linux's 127 character shebang limit while
                # ensuring the tool is executed hermetically using the venv's python environment.
                script_content = textwrap.dedent(f"""
                    import os, sys
                    os.execv({repr(str(venv_python.absolute()))}, [{repr(str(venv_python.absolute()))}, {repr(str(abs_tool_path))}] + sys.argv[1:])
                """).lstrip()
                py_script_path.write_text(script_content)

                bash_wrapper = textwrap.dedent(f"""
                    #!/bin/sh
                    exec "{ctx.exec_python.absolute()}" "{py_script_path.absolute()}" "$@"
                """).lstrip()
                dest_path.write_text(bash_wrapper)
                dest_path.chmod(0o755)
            else:
                dest_path.symlink_to(abs_tool_path)
