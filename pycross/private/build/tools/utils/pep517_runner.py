import os
import subprocess
import sys
import traceback
from pathlib import Path

from pycross.private.build.tools.utils.context import BuildContext


def run_pep517_build(ctx: BuildContext) -> str:
    """Execute standard pypa/build frontend inside configured virtual environment.

    This runner is intentionally generic and backend-agnostic. Package-specific
    workarounds (e.g., injecting versioneer.py for Pandas) should be implemented
    as pre_build_hooks rather than added here.
    """
    path_dirs = [ctx.tools_dir.absolute(), (ctx.env_dir / "bin").absolute(), ctx.bin_dir.absolute()]
    path_entries = [str(pd) for pd in path_dirs]
    existing_path = ctx.build_env.get("PATH")
    if existing_path:
        path_entries.append(existing_path)
    ctx.build_env["PATH"] = os.pathsep.join(path_entries)

    def _subprocess_runner(cmd, cwd=None, extra_environ=None):
        env = ctx.build_env.copy()
        if extra_environ:
            env.update(extra_environ)
        try:
            subprocess.check_output(cmd, cwd=cwd, env=env, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError as cpe:
            print("===== BUILD FAILED =====", file=sys.stderr)
            if cpe.output:
                print(cpe.output.decode("utf-8", "replace"), file=sys.stderr)
            with open(ctx.temp_dir / "build_failed.log", "w") as f:
                if cpe.output:
                    f.write(cpe.output.decode("utf-8", "replace"))
            raise RuntimeError("Build failed")

    from build._builder import ProjectBuilder

    builder = ProjectBuilder(
        source_dir=ctx.sdist_dir,
        python_executable=str(ctx.env_dir / "bin" / "python"),
        runner=_subprocess_runner,
    )

    ctx.wheel_directory.mkdir(parents=True, exist_ok=True)

    try:
        wheel_file = builder.build(
            distribution="wheel",
            output_directory=ctx.wheel_directory,
            config_settings=ctx.config_settings,
        )

        if ctx.wheel_file.exists() or ctx.wheel_file.is_symlink():
            ctx.wheel_file.unlink()

        os.symlink("wheel/" + Path(wheel_file).name, ctx.wheel_file)

        with open(ctx.wheel_name_file, "w") as f:
            f.write(Path(wheel_file).name)

        return str(ctx.wheel_file)
    except Exception:
        ctx.temp_dir.mkdir(parents=True, exist_ok=True)
        with open(ctx.temp_dir / "build_failed.log", "w") as f:
            f.write(traceback.format_exc())
        raise
