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


def load_target_sysconfig(ctx: BuildContext) -> Dict[str, Any]:
    """Load target environment sysconfig build variables."""
    if ctx.exec_python == ctx.target_python:
        query_args = (
            ctx.exec_python,
            "-c",
            textwrap.dedent(
                """\
            import importlib, json, sysconfig
            sysconfigdata_name = sysconfig._get_sysconfigdata_name()
            if sysconfigdata_name:
                vars = importlib.import_module(sysconfigdata_name).build_time_vars
                print(json.dumps(vars))
            else:
                print("{}")
            """
            ),
        )
        try:
            vars_json = subprocess.check_output(args=query_args)
            return json.loads(vars_json)
        except subprocess.CalledProcessError as cpe:
            print("Failed to query exec_python for sysconfig vars", file=sys.stderr)
            print(cpe.output.decode(), file=sys.stderr)
            raise

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


def _is_crossenv_active(env_dir: Path) -> bool:
    """Check whether crossenv has already been set up in the virtualenv.

    Crossenv writes its own platform-spoofing patches (e.g. sys-patch.py,
    platform-patch.py, sysconfig-patch.py) into the venv's lib directory.
    If these files are present, crossenv is handling cross-compilation and
    additional sitecustomize.py spoofing is unnecessary.
    """
    lib_dir = env_dir / "lib"
    if not lib_dir.exists():
        return False
    # crossenv creates these characteristic patch scripts in the lib dir
    crossenv_markers = ["sys-patch.py", "platform-patch.py", "sysconfig-patch.py"]
    return all((lib_dir / marker).exists() for marker in crossenv_markers)


def apply_sysconfig_overrides(ctx: BuildContext) -> None:
    """Inject sysconfig configuration and write sitecustomize.py monkeypatches.

    This function serves two purposes:

    1. **Sysconfigdata override** (always applied): Writes a custom
       ``_pycross_sysconfigdata.py`` module and a ``.pth`` file so that
       Python's ``sysconfig`` reads target-platform build variables instead
       of the host's.  This is needed by all builders.

    2. **sitecustomize.py platform spoofing** (conditionally applied): Writes a
       ``sitecustomize.py`` that monkey-patches ``sys.platform`` and
       ``sysconfig.get_platform()`` so that callers like ``packaging.tags``
       and ``mesonpy`` see the *target* platform rather than the host.

       **Why this is necessary:** Meson-based builds (``mesonpy``) bypass
       ``crossenv`` entirely and manage cross-compilation through their own
       ``cross.ini``.  Without this spoofing, ``mesonpy`` and
       ``packaging/tags`` would read the host platform and incorrectly tag
       the output wheel.

       **When it is redundant:** When ``crossenv`` is already active (e.g.
       Setuptools or Maturin builds in cross-compilation mode), crossenv
       installs its own comprehensive platform patches
       (``sys-patch.py``, ``platform-patch.py``, ``sysconfig-patch.py``, etc.)
       that handle all platform spoofing.  Injecting ``sitecustomize.py``
       on top of crossenv's patches is unnecessary and risks conflicts.
       In that case, this step is skipped.
    """
    site_dir = find_site_dir(ctx.env_dir)
    with open(site_dir / "_sysconfigdata_pycross.py", "w") as f:
        f.write(f"build_time_vars = {repr(ctx.sysconfig_vars)}\n")
    with open(site_dir / "_sysconfigdata_pycross.pth", "w") as f:
        f.write('import os; os.environ["_PYTHON_SYSCONFIGDATA_NAME"] = "_sysconfigdata_pycross"\n')

    target_platform, macosx_deployment_target = derive_platform_overrides(ctx.sysconfig_vars)
    target_sys_platform = ctx.sysconfig_vars.get("MACHDEP")

    if macosx_deployment_target:
        ctx.build_env["MACOSX_DEPLOYMENT_TARGET"] = macosx_deployment_target
    if target_platform:
        ctx.build_env["_PYTHON_HOST_PLATFORM"] = target_platform

    # Skip sitecustomize.py injection when crossenv is active, since crossenv
    # already provides its own comprehensive platform-spoofing patches.
    if _is_crossenv_active(ctx.env_dir):
        return

    with open(site_dir / "sitecustomize.py", "w") as f:
        f.write(
            textwrap.dedent(f"""\
            import os
            import sys
            import sysconfig
            import types

            class SysWrapper(object):
                def __init__(self, real_sys):
                    self.__dict__["_real_sys"] = real_sys
                def __getattr__(self, name):
                    return getattr(self._real_sys, name)
                def __setattr__(self, name, value):
                    setattr(self._real_sys, name, value)
                @property
                def platform(self):
                    import sys as _sys
                    try:
                        f = _sys._getframe(1)
                        while f:
                            filename = f.f_code.co_filename
                            if "packaging/tags" in filename or "mesonpy" in filename:
                                val = {repr(target_sys_platform)}
                                if val is not None:
                                    return val
                                break
                            f = f.f_back
                    except Exception:
                        pass
                    return self._real_sys.platform

            sys.modules["sys"] = SysWrapper(sys)

            _real_get_platform = sysconfig.get_platform
            def _get_platform():
                import sys as _sys
                try:
                    f = _sys._getframe(1)
                    while f:
                        filename = f.f_code.co_filename
                        if "packaging/tags" in filename or "mesonpy" in filename:
                            val = {repr(target_platform)}
                            if val is not None:
                                return val
                            break
                        f = f.f_back
                except Exception:
                    pass
                return _real_get_platform()

            sysconfig.get_platform = _get_platform

            scproxy = types.ModuleType("_scproxy")
            scproxy._get_proxies = lambda: {{}}
            scproxy._get_proxy_settings = lambda: {{}}
            sys.modules["_scproxy"] = scproxy

            if {repr(macosx_deployment_target)}:
                os.environ["MACOSX_DEPLOYMENT_TARGET"] = {repr(macosx_deployment_target)}

            if {repr(target_platform)}:
                os.environ["_PYTHON_HOST_PLATFORM"] = {repr(target_platform)}

            from importlib.abc import MetaPathFinder
            class SetuptoolsPatchFinder(MetaPathFinder):
                def find_spec(self, fullname, path, target=None):
                    if fullname in ("setuptools._distutils.util", "distutils.util"):
                        sys.meta_path.remove(self)
                        try:
                            import importlib
                            spec = importlib.util.find_spec(fullname)
                            if spec:
                                class PatchedLoader(spec.loader.__class__):
                                    def __init__(self, original_loader):
                                        self.original_loader = original_loader
                                    def create_module(self, spec):
                                        return self.original_loader.create_module(spec)
                                    def exec_module(self, module):
                                        self.original_loader.exec_module(module)
                                        module._syscfg_macosx_ver = None
                                spec.loader = PatchedLoader(spec.loader)
                                return spec
                        finally:
                            sys.meta_path.insert(0, self)
                    return None

            sys.meta_path.insert(0, SetuptoolsPatchFinder())

            if sys.version_info >= (3, 12):
                try:
                    import _distutils_hack
                    _distutils_hack.add_shim()
                except ImportError:
                    pass
            """)
        )
