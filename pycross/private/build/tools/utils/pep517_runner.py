import os
import shlex
import subprocess
import sys
import traceback

from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.venv_utils import venv_python_path


def run_pep517_build(ctx: BuildContext) -> str:
    """Execute standard pypa/build frontend inside configured virtual environment.

    This runner is intentionally generic and backend-agnostic. Package-specific
    workarounds (e.g., injecting versioneer.py for Pandas) should be implemented
    as pre_build_hooks rather than added here.
    """
    python_executable = venv_python_path(ctx.env_dir).absolute()
    path_dirs = [ctx.tools_dir.absolute(), python_executable.parent]
    path_entries = [str(pd) for pd in path_dirs]
    existing_path = ctx.build_env.get("PATH")
    if existing_path:
        path_entries.append(existing_path)
    ctx.build_env["PATH"] = os.pathsep.join(path_entries)

    is_debug = os.environ.get("RULES_PYCROSS_DEBUG", "false").lower() in ("1", "true", "yes", "y")

    if is_debug:
        print("==================================================", file=sys.stderr)
        print("RULES_PYCROSS_DEBUG is set.", file=sys.stderr)
        print(f"Build environment is located at: {ctx.temp_dir.absolute()}", file=sys.stderr)
        print("To preserve this directory after the build, use Bazel's --sandbox_debug flag.", file=sys.stderr)
        print("==================================================", file=sys.stderr)

    wrote_failure_log = False

    def _subprocess_runner(cmd, cwd=None, extra_environ=None):
        nonlocal wrote_failure_log
        env = ctx.build_env.copy()
        if extra_environ:
            env.update(extra_environ)

        effective_cwd = cwd or os.getcwd()
        cmd_str = shlex.join(str(c) for c in cmd)
        if is_debug:
            print(f"\n[DEBUG] Running command: {cmd_str}", file=sys.stderr)
            print(f"[DEBUG] Working directory: {effective_cwd}", file=sys.stderr)
            sys.stderr.flush()

            chunks = []
            with subprocess.Popen(
                cmd,
                cwd=cwd,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            ) as proc:
                assert proc.stdout is not None
                for raw_line in proc.stdout:
                    decoded = raw_line.decode("utf-8", "replace")
                    chunks.append(decoded)
                    sys.stderr.write(decoded)
                    sys.stderr.flush()
                returncode = proc.wait()
            output_text = "".join(chunks)
        else:
            res = subprocess.run(
                cmd,
                cwd=cwd,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            returncode = res.returncode
            output_text = res.stdout.decode("utf-8", "replace") if res.stdout else ""

        if returncode != 0:
            header = (
                f"===== BUILD FAILED (exit code {returncode}) =====\n"
                f"Command: {cmd_str}\n"
                f"Working directory: {effective_cwd}\n"
            )
            print(header, end="", file=sys.stderr)
            if not is_debug and output_text:
                print(output_text, file=sys.stderr)
            ctx.temp_dir.mkdir(parents=True, exist_ok=True)
            with open(ctx.temp_dir / "build_failed.log", "w", encoding="utf-8") as f:
                f.write(header)
                if output_text:
                    f.write("\n")
                    f.write(output_text)
            wrote_failure_log = True
            raise RuntimeError(f"Build command exited with status {returncode}")

    from build._builder import ProjectBuilder

    ctx.wheel_dir.mkdir(parents=True, exist_ok=True)

    try:
        builder = ProjectBuilder(
            source_dir=ctx.sdist_dir,
            python_executable=str(python_executable),
            runner=_subprocess_runner,
        )
        wheel_file = builder.build(
            distribution="wheel",
            output_directory=ctx.wheel_dir,
            config_settings=ctx.config_settings,
        )

        return wheel_file
    except Exception:
        if not wrote_failure_log:
            ctx.temp_dir.mkdir(parents=True, exist_ok=True)
            with open(ctx.temp_dir / "build_failed.log", "w", encoding="utf-8") as f:
                f.write(traceback.format_exc())
        raise
