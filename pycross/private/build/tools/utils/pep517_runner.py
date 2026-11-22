import os
import shlex
import subprocess
import sys
import traceback

from pycross.private.build.tools.crossenv import utils as crossenv_utils
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

    is_cross = ctx.exec_python != ctx.target_python
    if is_cross or ctx.bazel_config.get("always_use_crossenv"):
        import sysconfig

        target_suffix = ctx.sysconfig_vars.get("EXT_SUFFIX")
        target_soabi = ctx.sysconfig_vars.get("SOABI")

        _real_get_config_var = sysconfig.get_config_var

        def _get_config_var(name):
            if name == "EXT_SUFFIX" and target_suffix:
                return target_suffix
            elif name == "SOABI" and target_soabi:
                return target_soabi
            return _real_get_config_var(name)

        sysconfig.get_config_var = _get_config_var

        _real_get_config_vars = sysconfig.get_config_vars

        def _get_config_vars(*args, **kwargs):
            res = _real_get_config_vars(*args, **kwargs)
            if isinstance(res, dict):
                if "EXT_SUFFIX" in res and target_suffix:
                    res["EXT_SUFFIX"] = target_suffix
                if "SOABI" in res and target_soabi:
                    res["SOABI"] = target_soabi
            return res

        sysconfig.get_config_vars = _get_config_vars

        # Limited-API suffixes come from this list (e.g. Python 3.15's ".abi3-<platform>.so").
        target_extension_suffixes = crossenv_utils.target_extension_suffixes(ctx.sysconfig_vars)
        if target_extension_suffixes is not None:
            import importlib.machinery

            importlib.machinery.EXTENSION_SUFFIXES = target_extension_suffixes

    try:
        builder = ProjectBuilder(
            source_dir=ctx.sdist_dir,
            python_executable=str(ctx.env_dir / "bin" / "python"),
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
