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


def _link_merge_multiple(src_dirs: list[Path], dst_dir: Path):
    """Merge contents of multiple src_dirs into dst_dir using symlinks.

    Link only as deeply as necessary. If a top-level directory/file is unique
    across all sources, it is symlinked directly. If there are conflicts,
    directories are merged recursively.
    """
    from collections import defaultdict

    entries = defaultdict(list)
    for src in src_dirs:
        if not src.exists():
            continue
        for item in src.iterdir():
            entries[item.name].append(item)

    for name, items in entries.items():
        target = dst_dir / name

        # Handle pre-existing files in dst_dir (e.g. .pth files written before this)
        if target.exists() or target.is_symlink():
            if target.is_dir() and not target.is_symlink() and all(item.is_dir() for item in items):
                _link_merge_multiple(items, target)
            continue

        if len(items) == 1:
            target.symlink_to(items[0])
        else:
            if all(item.is_dir() for item in items):
                target.mkdir()
                _link_merge_multiple(items, target)
            else:
                # Conflict: mixed file/dir or multiple files. First one wins.
                print(
                    f"WARNING: link merge conflict for '{name}': using {items[0]}, ignoring {items[1:]}",
                    file=sys.stderr,
                )
                target.symlink_to(items[0])


def write_base_prefix_pth(
    site_dir: Path, prefix: Path, base_prefix: Optional[Path], platbase_prefix: Optional[Path]
) -> None:
    if not base_prefix and not platbase_prefix:
        return

    parts = []
    need_os = False

    if base_prefix:
        if prefix in base_prefix.parents or base_prefix == prefix:
            rel_base = os.path.relpath(base_prefix, site_dir)
            parts.append(f'sys.base_prefix = os.path.abspath(os.path.join(sitedir, "{rel_base}"))')
            need_os = True
        else:
            parts.append(f'sys.base_prefix = "{base_prefix}"')

    if platbase_prefix:
        if prefix in platbase_prefix.parents or platbase_prefix == prefix:
            rel_platbase = os.path.relpath(platbase_prefix, site_dir)
            parts.append(f'sys.base_exec_prefix = os.path.abspath(os.path.join(sitedir, "{rel_platbase}"))')
            need_os = True
        else:
            parts.append(f'sys.base_exec_prefix = "{platbase_prefix}"')

    imports = "import os, sys; " if need_os else "import sys; "
    pth_line = imports + "; ".join(parts) + "\n"

    with open(site_dir / "_pycross_sys_base_prefix.pth", "w") as f:
        f.write(pth_line)


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
            return candidate.resolve()
        # installed_base is stale — fall back to grandparent if possible.
        if prefix in target_python.parents:
            return target_python.parent.parent.resolve()
        return None

    # No sysconfig value at all — use the grandparent heuristic.
    if prefix in target_python.parents:
        return target_python.parent.parent.resolve()
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

    write_base_prefix_pth(site_dir, ctx.prefix, base_prefix, platbase_prefix)

    _link_merge_multiple(ctx.python_paths, site_dir)

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

    ctx.crossenv_active = True

    site_dir = find_site_dir(ctx.env_dir)
    _link_merge_multiple(ctx.python_paths, site_dir)

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
    sdist_paths = [str(ctx.sdist_dir.absolute())]

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

            venv_site = {repr(str(site_dir.absolute()))}
            sdist_paths = {repr(sdist_paths)}
            paths_to_add = [venv_site] + sdist_paths
            existing_pp = os.environ.get("PYTHONPATH")
            os.environ["PYTHONPATH"] = os.pathsep.join(paths_to_add) + (os.pathsep + existing_pp if existing_pp else "")

            os.execv({repr(str(real_python))}, [{repr(str(python_exe.absolute()))}] + sys.argv[1:])
            """)
        )
    python_exe.chmod(0o755)
