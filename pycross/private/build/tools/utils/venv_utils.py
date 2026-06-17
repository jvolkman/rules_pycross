import json
import os
import subprocess
import sys
import textwrap
from pathlib import Path
from typing import Optional

from pycross.private.build.tools.utils.context import BuildContext


def find_site_dir(env_dir: Path) -> Path:
    """Find virtualenv site-packages directory."""
    lib_dir = env_dir / "lib"
    try:
        return next(lib_dir.glob("python*/site-packages"))
    except StopIteration:
        raise ValueError(f"Cannot find site-packages under {env_dir}")


def resolve_base_prefix(
    installed_value: Optional[str],
    target_python: Path,
    prefix: Path,
) -> Optional[Path]:
    """Resolve a base prefix (base_prefix or base_exec_prefix) for the build venv.

    Prefers ``installed_base`` / ``installed_platbase`` from sysconfig when the
    path actually exists on disk.  Falls back to the ``target_python``
    grandparent heuristic when:

    * The sysconfig value is missing, OR
    * The sysconfig value points to a directory that doesn't exist — this
      happens when Python outputs are copied through additional Bazel rules
      (e.g., rpath correction on macOS) but sysconfig still references the
      original location.

    Args:
        installed_value: The raw ``installed_base`` or ``installed_platbase``
            string from sysconfig, or ``None``.
        target_python: Absolute path to the target Python executable.
        prefix: The sandbox execroot path (``ctx.prefix``).

    Returns:
        Resolved :class:`Path` or ``None`` (when the target python is not
        under ``prefix`` and no sysconfig value is usable).
    """
    if installed_value:
        candidate = Path(installed_value)
        if candidate.exists():
            return candidate
        # installed_base is stale — fall back to grandparent if possible.
        if prefix in target_python.parents:
            return target_python.parent.parent
        return None

    # No sysconfig value at all — use the grandparent heuristic.
    if prefix in target_python.parents:
        return target_python.parent.parent
    return None


def build_standard_venv(ctx: BuildContext) -> None:
    """Initialize a standard Python virtualenv in the build sandbox."""
    venv_args = [
        str(ctx.exec_python),
        "-m",
        "venv",
        "--symlinks",
        "--without-pip",
        str(ctx.env_dir),
    ]
    subprocess.check_output(args=venv_args, env=ctx.build_env, stderr=subprocess.STDOUT)

    site_dir = find_site_dir(ctx.env_dir)
    with open(site_dir / "_pycross_sys_prefix.pth", "w") as f:
        f.write(f'import sys; sys.prefix = sys.exec_prefix = "{ctx.env_dir}"\n')

    base_prefix = resolve_base_prefix(
        ctx.sysconfig_vars.get("installed_base"),
        ctx.target_python,
        ctx.prefix,
    )
    platbase_prefix = resolve_base_prefix(
        ctx.sysconfig_vars.get("installed_platbase"),
        ctx.target_python,
        ctx.prefix,
    )

    if base_prefix or platbase_prefix:
        parts = []
        need_os = False

        if base_prefix:
            # If the base_prefix is inside the sandbox execroot, write it as a
            # relative path from site-packages (using the .pth 'sitedir' variable)
            # so it resolves correctly regardless of the absolute execroot path.
            if ctx.prefix in base_prefix.parents or base_prefix == ctx.prefix:
                rel_base = os.path.relpath(base_prefix, site_dir)
                parts.append(f'sys.base_prefix = os.path.abspath(os.path.join(sitedir, "{rel_base}"))')
                need_os = True
            else:
                parts.append(f'sys.base_prefix = "{base_prefix}"')

        if platbase_prefix:
            if ctx.prefix in platbase_prefix.parents or platbase_prefix == ctx.prefix:
                rel_platbase = os.path.relpath(platbase_prefix, site_dir)
                parts.append(f'sys.base_exec_prefix = os.path.abspath(os.path.join(sitedir, "{rel_platbase}"))')
                need_os = True
            else:
                parts.append(f'sys.base_exec_prefix = "{platbase_prefix}"')

        imports = "import os, sys; " if need_os else "import sys; "
        pth_line = imports + "; ".join(parts) + "\n"

        with open(site_dir / "_pycross_sys_base_prefix.pth", "w") as f:
            f.write(pth_line)

    with open(site_dir / "deps.pth", "w") as f:
        for dep_path in ctx.python_paths:
            rel_dep_path = os.path.relpath(dep_path, site_dir)
            f.write(f"import os, site; site.addsitedir(os.path.join(sitedir, {rel_dep_path!r}))\n")

    # Write site_hooks to a file and .pth entry.
    # The hooks file is loaded by the python wrapper's -c handler and by
    # non-intercepted Python invocations via the .pth file.
    if ctx.site_hooks:
        hooks_file = ctx.env_dir / "_pycross_hooks.py"
        with open(hooks_file, "w") as f:
            for hook in ctx.site_hooks:
                f.write(hook + "\n")
        with open(site_dir / "_pycross_hooks.pth", "w") as f:
            f.write(
                f"import importlib.util; "
                f"_s = importlib.util.spec_from_file_location('_pycross_hooks', '{hooks_file.absolute()}'); "
                f"_m = importlib.util.module_from_spec(_s); _s.loader.exec_module(_m)\n"
            )

    inject_python_wrapper(ctx)


def build_crossenv_venv(ctx: BuildContext) -> None:
    """Initialize crossenv virtual environment for cross-compiling standard Python extensions."""
    ctx.env_dir.mkdir(parents=True, exist_ok=True)
    sysconfig_json = ctx.env_dir / "sysconfig.json"
    with open(sysconfig_json, "w") as f:
        json.dump(ctx.sysconfig_vars, f, indent=2)

    import sysconfig as host_sysconfig

    crossenv_args = [
        str(ctx.exec_python),
        "-m",
        "pycross.private.build.tools.crossenv",
        "--env-dir",
        str(ctx.env_dir),
        "--sysconfig-json",
        str(sysconfig_json),
        "--target-python",
        str(ctx.target_python),
    ]

    target_env_tags = ctx.bazel_config.get("target_environment_tags", [])
    for tag in target_env_tags:
        if "manylinux" in tag:
            crossenv_args.extend(["--manylinux", tag])

    try:
        stdlib = host_sysconfig.get_path("stdlib")
        non_stdlib = [p for p in sys.path if p and not p.startswith(stdlib)]
        crossenv_env = ctx.build_env.copy()
        existing_pythonpath = crossenv_env.get("PYTHONPATH", "")
        non_stdlib_str = os.pathsep.join(non_stdlib)
        crossenv_env["PYTHONPATH"] = non_stdlib_str + (os.pathsep + existing_pythonpath if existing_pythonpath else "")

        subprocess.check_output(args=crossenv_args, env=crossenv_env, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as cpe:
        print("===== CROSSENV FAILED =====", file=sys.stderr)
        print(cpe.output.decode(), file=sys.stderr)
        raise

    inject_python_wrapper(ctx)


def inject_python_wrapper(ctx: BuildContext) -> None:
    """Inject custom PYTHONPATH python wrapper script inside virtualenv."""
    python_exe = ctx.env_dir / "bin" / "python"
    if python_exe.is_symlink():
        real_python = python_exe.readlink()
        if not real_python.is_absolute():
            real_python = (python_exe.parent / real_python).resolve()
        python_exe.unlink()
    else:
        real_python = ctx.exec_python
        python_exe.unlink()

    site_dir = find_site_dir(ctx.env_dir)
    python_paths_list = [str(p.absolute()) for p in ctx.python_paths]
    sdist_paths = [str(ctx.sdist_dir.absolute())]
    hooks_file_path = str((ctx.env_dir / "_pycross_hooks.py").absolute())

    with open(python_exe, "w") as f:
        f.write(
            textwrap.dedent(f"""\
            #!/bin/sh
            # POLYGLOT BASH/PYTHON WRAPPER
            # We use /bin/sh because Bazel's absolute paths can exceed the Linux 127-character shebang limit.
            # Shell evaluates "exec" as a command and replaces the process with the real Python interpreter,
            # passing -S to disable site-packages, $0 (this file) as the script, and $@ as the arguments.
            # Python evaluates "exec" as a string literal and discards it, then runs the rest of the script.
            "exec" "{ctx.exec_python.absolute()}" "-S" "$0" "$@"

            import os, sys

            # Intercept and execute all -c commands internally inside the wrapper process with target sysconfig overrides
            c_index = -1
            for idx, arg in enumerate(sys.argv):
                if arg == "-c":
                    c_index = idx
                    break

            if c_index != -1 and len(sys.argv) > c_index + 1:
                import sysconfig
                import site

                for p in [{repr(str(site_dir.absolute()))}] + {repr(python_paths_list)} + {repr(sdist_paths)}:
                    site.addsitedir(p)

                _real_get_config_var = sysconfig.get_config_var
                def _get_config_var(name):
                    if name == "EXT_SUFFIX":
                        return {repr(ctx.sysconfig_vars.get("EXT_SUFFIX"))}
                    elif name == "SOABI":
                        return {repr(ctx.sysconfig_vars.get("SOABI"))}
                    return _real_get_config_var(name)
                sysconfig.get_config_var = _get_config_var

                _real_get_config_vars = sysconfig.get_config_vars
                def _get_config_vars(*args, **kwargs):
                    res = _real_get_config_vars(*args, **kwargs)
                    if isinstance(res, dict):
                        if "EXT_SUFFIX" in res:
                            res["EXT_SUFFIX"] = {repr(ctx.sysconfig_vars.get("EXT_SUFFIX"))}
                        if "SOABI" in res:
                            res["SOABI"] = {repr(ctx.sysconfig_vars.get("SOABI"))}
                    return res
                sysconfig.get_config_vars = _get_config_vars

                # Execute site_hooks if present.
                _hooks_file = {repr(hooks_file_path)}
                if os.path.exists(_hooks_file):
                    with open(_hooks_file) as _hf:
                        exec(compile(_hf.read(), _hooks_file, 'exec'))

                # Execute the Meson/packaging command string cleanly inside our monkey-patched wrapper process
                exec(sys.argv[c_index + 1])
                sys.exit(0)

            venv_site = {repr(str(site_dir.absolute()))}
            dependency_paths = {repr(python_paths_list)}
            sdist_paths = {repr(sdist_paths)}
            paths_to_add = [venv_site] + dependency_paths + sdist_paths
            existing_pp = os.environ.get("PYTHONPATH")
            os.environ["PYTHONPATH"] = os.pathsep.join(paths_to_add) + (os.pathsep + existing_pp if existing_pp else "")

            os.execv({repr(str(real_python))}, [{repr(str(python_exe.absolute()))}] + sys.argv[1:])
            """)
        )
    python_exe.chmod(0o755)
