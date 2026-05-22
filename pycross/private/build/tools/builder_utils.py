"""Shared utility functions and dataclasses for PEP 517 package builders in rules_pycross."""

import json
import os
import shlex
import shutil
import subprocess
import sys
import tarfile
import textwrap
import traceback
import zipfile
from dataclasses import dataclass
from dataclasses import field
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Optional


@dataclass
class BuildContext:
    # Master configuration loaded from Bazel JSON
    bazel_config: Dict[str, Any]

    # Absolute sandbox paths
    prefix: Path
    temp_dir: Path
    sdist_dir: Path
    env_dir: Path
    bin_dir: Path
    tools_dir: Path

    # Key files & executables
    sdist_path: Path
    exec_python: Path
    target_python: Path
    wheel_file: Path
    wheel_name_file: Path

    # Build dependencies and tools
    pkg_config_files: List[Path]
    path_tools: List[Dict[str, Any]]
    python_paths: List[Path]
    target_sys_path: List[Path]

    # Shared build environment state
    sysconfig_vars: Dict[str, Any] = field(default_factory=dict)
    build_env: Dict[str, str] = field(default_factory=dict)
    config_settings: Dict[str, Any] = field(default_factory=dict)


def load_build_context(config_path: str) -> BuildContext:
    """Loads Bazel master configuration and initializes a typed BuildContext."""
    with open(config_path, "r") as f:
        bazel_config = json.load(f)

    prefix = Path.cwd().absolute()
    temp_dir = (prefix / Path(os.environ["PYCROSS_BUILD_ROOT"])).absolute()
    sdist_dir = (prefix / Path(os.environ["PYCROSS_SDIST_DIR"])).absolute()

    # Resolve configuration settings from file or dictionary
    config_settings_raw_path = bazel_config.get("config_settings_raw")
    if config_settings_raw_path:
        raw_path = (prefix / Path(config_settings_raw_path)).absolute()
        if raw_path.exists():
            with open(raw_path, "r") as f:
                config_settings = replace_path_placeholders(json.load(f), "$$EXT_BUILD_ROOT$$", prefix)
        else:
            config_settings = {}
    else:
        config_settings = bazel_config.get("config_settings", {})

    build_env = os.environ.copy()
    build_env["MESON_FORCE_BACKTRACE"] = "1"

    return BuildContext(
        bazel_config=bazel_config,
        prefix=prefix,
        temp_dir=temp_dir,
        sdist_dir=sdist_dir,
        env_dir=temp_dir / "env",
        bin_dir=temp_dir / "bin",
        tools_dir=temp_dir / "tools",
        sdist_path=(prefix / Path(bazel_config["sdist"])).absolute(),
        exec_python=(prefix / Path(bazel_config["exec_python"])).absolute(),
        target_python=(prefix / Path(bazel_config["target_python"])).absolute(),
        wheel_file=(prefix / Path(bazel_config["wheel_file"])).absolute(),
        wheel_name_file=(prefix / Path(bazel_config["wheel_name_file"])).absolute(),
        pkg_config_files=[(prefix / Path(f)).absolute() for f in bazel_config.get("pkg_config_files", [])],
        path_tools=[
            {
                "name": tool["name"],
                "path": (prefix / Path(tool["path"])).absolute(),
            }
            for tool in bazel_config.get("path_tools", [])
        ],
        python_paths=[(prefix / Path(p)).absolute() for p in bazel_config.get("python_paths", [])],
        target_sys_path=[(prefix / Path(p)).absolute() for p in (bazel_config.get("target_sys_path") or [])],
        build_env=build_env,
        config_settings=config_settings,
    )


def replace_path_placeholders(data: Dict[str, Any], placeholder: str, replacement: Path) -> Dict[str, Any]:
    """Replace path placeholder strings in a dict of config values."""
    replacement_str = str(replacement)
    if replacement_str.endswith("/"):
        replacement_str = replacement_str[:-1]
    result = {}
    for k, v in data.items():
        if isinstance(v, list):
            result[k] = [vi.replace(placeholder, replacement_str) if isinstance(vi, str) else vi for vi in v]
        elif isinstance(v, str):
            result[k] = v.replace(placeholder, replacement_str)
        else:
            result[k] = v
    return result


def extract_sdist(ctx: BuildContext) -> None:
    """Extracts the source distribution into the build sandbox."""
    extract_parent = ctx.temp_dir / "extracted"
    extract_parent.mkdir(parents=True, exist_ok=True)

    if ctx.sdist_path.name.endswith(".tar.gz"):
        with tarfile.open(ctx.sdist_path, "r") as f:
            if hasattr(tarfile, "data_filter"):
                f.extraction_filter = tarfile.data_filter
            f.extractall(extract_parent)
    elif ctx.sdist_path.name.endswith(".zip"):
        with zipfile.ZipFile(ctx.sdist_path, "r") as f:
            f.extractall(extract_parent)
    else:
        raise ValueError(f"Unsupported sdist format: {ctx.sdist_path}")

    extracted_dirs = list(extract_parent.glob("*"))
    if len(extracted_dirs) != 1:
        raise ValueError(f"Expected exactly one directory in sdist archive, got: {extracted_dirs}")

    ctx.sdist_dir.parent.mkdir(parents=True, exist_ok=True)
    extracted_dirs[0].rename(ctx.sdist_dir)
    shutil.rmtree(extract_parent)


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
        print("Failed to query exec_python for target path")
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
            print("Failed to query exec_python for sysconfig vars")
            print(cpe.output.decode(), file=sys.stderr)
            raise

    target_sys_path = ctx.target_sys_path
    if not target_sys_path:
        target_sys_path = determine_target_path_from_exec(ctx.exec_python, ctx.target_python)

    return find_sysconfig_data(target_sys_path)


def find_site_dir(env_dir: Path) -> Path:
    """Find virtualenv site-packages directory."""
    lib_dir = env_dir / "lib"
    try:
        return next(lib_dir.glob("python*/site-packages"))
    except StopIteration:
        raise ValueError(f"Cannot find site-packages under {env_dir}")


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
    subprocess.check_output(args=venv_args, env=os.environ, stderr=subprocess.STDOUT)

    site_dir = find_site_dir(ctx.env_dir)
    with open(site_dir / "_pycross_sys_prefix.pth", "w") as f:
        f.write(f'import sys; sys.prefix = sys.exec_prefix = "{ctx.env_dir}"\n')

    if ctx.prefix in ctx.target_python.parents:
        with open(site_dir / "_pycross_sys_base_prefix.pth", "w") as f:
            f.write(f'import sys; sys.base_prefix = sys.base_exec_prefix = "{ctx.target_python.parent.parent}"\n')

    with open(site_dir / "deps.pth", "w") as f:
        for dep_path in ctx.python_paths:
            rel_dep_path = os.path.relpath(dep_path, site_dir)
            f.write(f"import os, site; site.addsitedir(os.path.join(sitedir, {rel_dep_path!r}))\n")

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

    # Add user-configured sdist-relative paths (e.g., vendored build utilities)
    for rel_path in ctx.bazel_config.get("sdist_python_paths", []):
        p = ctx.sdist_dir / rel_path
        if p.is_dir():
            sdist_paths.append(str(p.absolute()))

    with open(python_exe, "w") as f:
        f.write(
            textwrap.dedent(f"""\
            #!/usr/bin/env python3
            import os, sys

            venv_site = {repr(str(site_dir.absolute()))}
            dependency_paths = {repr(python_paths_list)}
            sdist_paths = {repr(sdist_paths)}
            paths_to_add = [venv_site] + dependency_paths + sdist_paths
            existing_pp = os.environ.get("PYTHONPATH")
            os.environ["PYTHONPATH"] = os.pathsep.join(paths_to_add) + (os.pathsep + existing_pp if existing_pp else "")

            os.execv({repr(str(real_python))}, [{repr(str(real_python))}] + sys.argv[1:])
            """)
        )
    python_exe.chmod(0o755)


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
                #!/bin/sh
                exec "{venv_python.absolute()}" "{abs_tool_path}" "$@"
                """)
                dest_path.write_text(script_content)
                dest_path.chmod(0o755)
            else:
                dest_path.symlink_to(abs_tool_path)


def get_wrapper_flags(cflags: str) -> List[str]:
    """Extract target and sysroot flags to forward to compiler wrappers."""
    possible_flags = ["-target", "--target", "--sysroot", "-isysroot"]
    result = []
    split_cflags = shlex.split(cflags)
    for i, flag in enumerate(split_cflags):
        for possible_flag in possible_flags:
            if not (flag.startswith(possible_flag)):
                continue
            if "=" in flag:
                flag, value = flag.split("=", 1)
                additions = [f"{flag}={value}"]
            else:
                flag, value = flag, split_cflags[i + 1]
                additions = [flag, value]

            if not flag == possible_flag:
                continue
            result.extend(additions)
    return result


def wrap_compiler(lang: str, cc_exe: str, cflags: str, python_exe: Path, bin_dir: Path) -> Path:
    """Generate custom compiler wrapper scripts to filter Apple linker compatibility flags."""
    assert lang in ("cc", "cxx")

    cc_path = Path(cc_exe)
    if "clang" in cc_path.name or "zig" in cc_path.name:
        wrapper_name = "clang" if lang == "cc" else "clang++"
    elif "gcc" in cc_path.name:
        wrapper_name = "gcc" if lang == "cc" else "g++"
    else:
        wrapper_name = cc_path.name

    wrapper_flags = get_wrapper_flags(cflags)
    wrapper_path = bin_dir / wrapper_name

    with open(wrapper_path, "w") as f:
        f.write(
            textwrap.dedent(
                f"""\
                #!{python_exe.absolute()}
                import os
                import sys

                here = os.path.dirname(sys.argv[0])
                cc_exe = os.path.join(here, "{cc_exe}")

                filtered_args = []
                for arg in sys.argv[1:]:
                    if arg in (
                        "-Wl,--start-group",
                        "-Wl,--end-group",
                        "-Wl,-start_group",
                        "-Wl,-end_group",
                        "-Wl,--as-needed",
                        "-Wl,--allow-shlib-undefined",
                        "-Wl,-O1"
                    ):
                        continue
                    filtered_args.append(arg)

                os.execv(cc_exe, [cc_exe] + {repr(wrapper_flags)} + filtered_args)
                """
            )
        )

    wrapper_path.chmod(0o755)
    return wrapper_path


def setup_cc_mixin(ctx: BuildContext, cc_config: Dict[str, Any]) -> None:
    """Populate environment parameters and wrappers for Bazel CC Toolchains."""
    hook_bin_dir = ctx.temp_dir / "cc_hook" / "bin"
    hook_include_dir = ctx.temp_dir / "cc_hook" / "include"
    hook_lib_dir = ctx.temp_dir / "cc_hook" / "lib"
    hook_bin_dir.mkdir(parents=True, exist_ok=True)
    hook_include_dir.mkdir(parents=True, exist_ok=True)
    hook_lib_dir.mkdir(parents=True, exist_ok=True)

    for lib_path_str in cc_config.get("static_libs", []) + cc_config.get("shared_libs", []):
        lib_path = Path(lib_path_str.replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix)))
        dest = hook_lib_dir / lib_path.name
        if not dest.exists():
            dest.symlink_to(lib_path.absolute())

    orig_cc = cc_config["CC"].replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix))
    orig_cxx = cc_config["CXX"].replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix))
    cflags = cc_config["CFLAGS"].replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix))

    wrapped_cc = wrap_compiler("cc", orig_cc, cflags, ctx.exec_python, hook_bin_dir)
    wrapped_cxx = wrap_compiler("cxx", orig_cxx, cflags, ctx.exec_python, hook_bin_dir)

    extra_includes = []
    for inc_dir_str in cc_config.get("include_dirs", []):
        inc_dir = Path(inc_dir_str.replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix)))
        extra_includes.append(f"-I{inc_dir.absolute()}")
    extra_includes_str = " ".join(extra_includes)

    ctx.sysconfig_vars.update(
        {
            "CC": str(wrapped_cc.absolute()),
            "CXX": str(wrapped_cxx.absolute()),
            "CFLAGS": cflags
            + f" -I{hook_include_dir.absolute()} -L{hook_lib_dir.absolute()}"
            + (f" {extra_includes_str}" if extra_includes_str else ""),
            "CXXFLAGS": cc_config["CXXFLAGS"].replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix))
            + f" -I{hook_include_dir.absolute()} -L{hook_lib_dir.absolute()}"
            + (f" {extra_includes_str}" if extra_includes_str else ""),
            "LDFLAGS": cc_config["LDFLAGS"].replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix))
            + f" -L{hook_lib_dir.absolute()}",
            "LDSHAREDFLAGS": cc_config["LDSHAREDFLAGS"].replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix))
            + f" -L{hook_lib_dir.absolute()}",
            "AR": cc_config["AR"].replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix)),
            "ARFLAGS": cc_config["ARFLAGS"].replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix)),
        }
    )

    ctx.sysconfig_vars["LDSHARED"] = " ".join([ctx.sysconfig_vars["CC"], ctx.sysconfig_vars["LDSHAREDFLAGS"]])
    if ctx.sysconfig_vars.get("MACHDEP") == "darwin":
        ctx.sysconfig_vars["LDSHARED"] += " -Wl,-undefined,dynamic_lookup"
    ctx.sysconfig_vars["LDCXXSHARED"] = ctx.sysconfig_vars["LDSHARED"]

    include_paths = [str(hook_include_dir.absolute())] + [
        str(Path(p.replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix))).absolute())
        for p in cc_config.get("include_dirs", [])
    ]
    ctx.build_env.update(
        {
            "PATH": f"{hook_bin_dir.absolute()}:{ctx.build_env.get('PATH', '')}",
            "PYCROSS_LIBRARY_PATH": str(hook_lib_dir.absolute()),
            "PYCROSS_INCLUDE_PATH": ":".join(include_paths),
            "CC": ctx.sysconfig_vars["CC"],
            "CXX": ctx.sysconfig_vars["CXX"],
            "CFLAGS": ctx.sysconfig_vars["CFLAGS"],
            "CXXFLAGS": ctx.sysconfig_vars["CXXFLAGS"],
            "LDFLAGS": ctx.sysconfig_vars["LDFLAGS"],
            "LDSHAREDFLAGS": ctx.sysconfig_vars["LDSHAREDFLAGS"],
        }
    )


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
    """Inject sysconfig configuration and write sitecustomize.py monkeypatches."""
    site_dir = find_site_dir(ctx.env_dir)
    with open(site_dir / "_pycross_sysconfigdata.py", "w") as f:
        f.write(f"build_time_vars = {repr(ctx.sysconfig_vars)}\n")
    with open(site_dir / "_pycross_sysconfigdata.pth", "w") as f:
        f.write('import os; os.environ["_PYTHON_SYSCONFIGDATA_NAME"] = "_pycross_sysconfigdata"\n')

    target_platform, macosx_deployment_target = derive_platform_overrides(ctx.sysconfig_vars)
    target_sys_platform = ctx.sysconfig_vars.get("MACHDEP")

    if macosx_deployment_target:
        ctx.build_env["MACOSX_DEPLOYMENT_TARGET"] = macosx_deployment_target
    if target_platform:
        ctx.build_env["_PYTHON_HOST_PLATFORM"] = target_platform

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


def run_pre_build_hook(ctx: BuildContext, hook_config: Dict[str, Any]) -> None:
    """Execute a pre-build hook mixin inside the build sandbox.

    The hook receives the current build environment and config settings
    via JSON files. It may mutate both by writing back to those files.
    """
    hook_exe = (ctx.prefix / Path(hook_config["executable"])).absolute()

    # Write current state files for the hook to read/modify
    config_settings_file = ctx.temp_dir / "config_settings.json"
    env_file = ctx.temp_dir / "build_env.json"

    with open(config_settings_file, "w") as f:
        json.dump(ctx.config_settings, f)
    with open(env_file, "w") as f:
        json.dump({k: v for k, v in ctx.build_env.items() if isinstance(v, str)}, f)

    hook_env = dict(ctx.build_env)
    hook_env["PYCROSS_BAZEL_ROOT"] = str(ctx.prefix)
    hook_env["PYCROSS_CONFIG_SETTINGS_FILE"] = str(config_settings_file)
    hook_env["PYCROSS_ENV_VARS_FILE"] = str(env_file)

    # Merge hook-specific env vars
    for key, value in hook_config.get("env", {}).items():
        hook_env[key] = value.replace("$$EXT_BUILD_ROOT$$", str(ctx.prefix))

    try:
        subprocess.check_output(
            args=[str(hook_exe)],
            env=hook_env,
            cwd=str(ctx.sdist_dir),
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as cpe:
        print("===== PRE-BUILD HOOK FAILED =====", file=sys.stderr)
        if cpe.output:
            print(cpe.output.decode("utf-8", "replace"), file=sys.stderr)
        raise

    # Read back any mutations the hook made
    if env_file.exists():
        with open(env_file, "r") as f:
            updated_env = json.load(f)
            ctx.build_env.update(updated_env)

    if config_settings_file.exists():
        with open(config_settings_file, "r") as f:
            ctx.config_settings = json.load(f)


def run_pep517_build(ctx: BuildContext) -> str:
    """Execute standard pypa/build frontend inside configured virtual environment."""
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
            sys.exit(1)

    from build._builder import ProjectBuilder

    builder = ProjectBuilder(
        source_dir=ctx.sdist_dir,
        python_executable=str(ctx.env_dir / "bin" / "python"),
        runner=_subprocess_runner,
    )

    wheel_dir = ctx.temp_dir / "wheel"
    wheel_dir.mkdir(exist_ok=True)

    try:
        wheel_file = builder.build(
            distribution="wheel",
            output_directory=wheel_dir,
            config_settings=ctx.config_settings,
        )

        shutil.copy2(wheel_file, ctx.wheel_file)
        with open(ctx.wheel_name_file, "w") as f:
            f.write(Path(wheel_file).name)

        return str(ctx.wheel_file)
    except Exception:
        ctx.temp_dir.mkdir(parents=True, exist_ok=True)
        with open(ctx.temp_dir / "build_failed.log", "w") as f:
            f.write(traceback.format_exc())
        raise


def load_mixins(ctx: BuildContext) -> List[Dict[str, Any]]:
    """Yield deserialized JSON build mixin target configurations."""
    mixins = ctx.bazel_config.get("mixins", [])
    result = []
    for mixin_json_path_str in mixins:
        mixin_json_path = (ctx.prefix / Path(mixin_json_path_str)).absolute()
        with open(mixin_json_path, "r") as f:
            result.append(json.load(f))
    return result
