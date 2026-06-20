import json
import os
import subprocess
import sys
import textwrap
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Optional

from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.venv_utils import find_site_dir


def determine_target_path_from_exec(exec_python_exe: Path, target_python_exe: Path) -> List[Path]:
    """Query target sys.path using host Python relative references."""
    query_args = (
        exec_python_exe,
        "-c",
        "import json, sys; print(json.dumps(dict(exec=sys.executable, path=sys.path)))",
    )
    try:
        out_json = subprocess.check_output(args=query_args, env={})
        query_result = json.loads(out_json)
    except subprocess.CalledProcessError as cpe:
        print("Failed to query exec_python for target path", file=sys.stderr)
        print(cpe.output.decode(), file=sys.stderr)
        raise

    exec_path = Path(query_result["exec"]).resolve()
    sys_path = [Path(p).resolve() for p in query_result["path"]]
    target_exec_resolved = target_python_exe.resolve()

    result = []
    for p in sys_path:
        try:
            common = Path(os.path.commonpath([exec_path, p])).absolute()
            exec_depth = len(exec_path.relative_to(common).parents)
            rel = p.relative_to(common)
            up_path = Path(*[".."] * exec_depth)
            path = (target_exec_resolved / up_path / rel).resolve()
            result.append(path)
        except ValueError:
            continue
    return result


def find_sysconfig_data(search_paths: List[Path]) -> Dict[str, Any]:
    """Search for _sysconfigdata_*.py modules in the given paths and return build_time_vars."""
    import glob
    import importlib.util

    for search_path in search_paths:
        pattern = str(search_path / "_sysconfigdata_*.py")
        for match in glob.glob(pattern):
            spec = importlib.util.spec_from_file_location("_sysconfigdata", match)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                if hasattr(mod, "build_time_vars"):
                    return mod.build_time_vars
    return {}


def _query_interpreter(python_exe: Path) -> Optional[Dict[str, Any]]:
    query_args = (
        python_exe,
        "-c",
        textwrap.dedent(
            """\
        import importlib, json, sysconfig, sys
        sysconfigdata_name = sysconfig._get_sysconfigdata_name()
        if sysconfigdata_name:
            try:
                result = dict(importlib.import_module(sysconfigdata_name).build_time_vars)
            except ImportError:
                result = {}
        else:
            result = {}
        result["installed_base"] = sysconfig.get_config_var("installed_base") or sys.base_prefix
        result["installed_platbase"] = sysconfig.get_config_var("installed_platbase") or sys.base_exec_prefix
        print(json.dumps(result))
        """
        ),
    )
    try:
        out_json = subprocess.check_output(args=query_args, timeout=5, stderr=subprocess.DEVNULL)
        return json.loads(out_json)
    except Exception as e:
        print(
            f"WARNING: Could not query interpreter {python_exe} (expected for cross-compilation): {e}", file=sys.stderr
        )
        return None


def load_target_sysconfig(ctx: BuildContext) -> Dict[str, Any]:
    """Load target environment sysconfig build variables."""
    # Try to query the target python directly first (works for host and same-arch target toolchains).
    # Falls back to static _sysconfigdata for cross-compilation where the target
    # interpreter cannot be executed on the host.
    result = _query_interpreter(ctx.target_python)
    if result is not None:
        return result

    # Fallback for cross-compilation: load static _sysconfigdata
    if not ctx.target_sys_path:
        ctx.target_sys_path = determine_target_path_from_exec(ctx.exec_python, ctx.target_python)

    return find_sysconfig_data(ctx.target_sys_path)


def derive_platform_overrides(sysconfig_vars: Dict[str, Any]) -> tuple[Optional[str], Optional[str]]:
    """Derive _PYTHON_HOST_PLATFORM and MACOSX_DEPLOYMENT_TARGET dynamically from target sysconfig."""
    machdep = sysconfig_vars.get("MACHDEP")
    host_gnu_type = sysconfig_vars.get("HOST_GNU_TYPE", "")

    if not machdep:
        return None, None

    # Resolve target architecture from HOST_GNU_TYPE (e.g. aarch64-apple-darwin -> arm64)
    arch = "x86_64"
    if "aarch64" in host_gnu_type or "arm64" in host_gnu_type:
        arch = "aarch64"
    elif "x86_64" in host_gnu_type:
        arch = "x86_64"

    if machdep == "darwin":
        if arch == "aarch64":
            arch = "arm64"
        dep_target = sysconfig_vars.get("MACOSX_DEPLOYMENT_TARGET")
        if not dep_target:
            dep_target = "11.0"  # fallback deployment target
        return f"macosx-{dep_target}-{arch}", dep_target

    elif machdep == "linux":
        return f"linux-{arch}", None

    return None, None


def apply_sysconfig_overrides(ctx: BuildContext) -> None:
    """Inject sysconfig configuration and environment overrides.

    This function serves two purposes:

    1. **Sysconfigdata override**: Writes a custom ``_pycross_sysconfigdata.py``
       module and a ``.pth`` file so that Python's ``sysconfig`` reads
       target-platform build variables instead of the host's. This is needed
       by all builders.

    2. **Environment variable overrides**: Sets ``_PYTHON_HOST_PLATFORM`` and
       ``MACOSX_DEPLOYMENT_TARGET`` directly in the build environment
       (``ctx.build_env``) so they are naturally inherited by the underlying
       build backend subprocesses (like setuptools) without needing
       late-binding monkeypatches.
    """
    site_dir = find_site_dir(ctx.env_dir)
    with open(site_dir / "_sysconfigdata_pycross.py", "w") as f:
        f.write(f"build_time_vars = {repr(ctx.sysconfig_vars)}\n")
    with open(site_dir / "_sysconfigdata_pycross.pth", "w") as f:
        f.write('import os; os.environ["_PYTHON_SYSCONFIGDATA_NAME"] = "_sysconfigdata_pycross"\n')
    ctx.build_env["_PYTHON_SYSCONFIGDATA_NAME"] = "_sysconfigdata_pycross"

    target_platform, macosx_deployment_target = derive_platform_overrides(ctx.sysconfig_vars)

    if macosx_deployment_target:
        ctx.build_env["MACOSX_DEPLOYMENT_TARGET"] = macosx_deployment_target
    if target_platform:
        ctx.build_env["_PYTHON_HOST_PLATFORM"] = target_platform
