import hashlib
import json
import ntpath
import os
from dataclasses import dataclass
from dataclasses import field
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Optional


@dataclass
class CcLayerState:
    """Resolved C/C++ toolchain state populated once by ``setup_cc_layer``."""

    cc_path: Path
    cxx_path: Path
    cflags: List[str]
    cxxflags: List[str]
    ldflags: List[str]
    ldsharedflags: List[str]
    ar_list: List[str]
    arflags: List[str]
    ranlib_path: Optional[Path]
    include_dirs: List[Path]
    layer_lib_dir: Path
    runtime_libs: List[Path]


@dataclass
class BuildContext:
    # Main configuration loaded from Bazel JSON
    bazel_config: Dict[str, Any]

    # Build paths. The original source path can be relative.
    prefix: Path
    temp_dir: Path
    sdist_root_dir: Path
    original_sdist_root: str
    sdist_dir: Path
    env_dir: Path
    tools_dir: Path

    # Key files & executables
    sdist_path: Path
    exec_python: Path
    target_python: Path
    wheel_dir: Path

    # Build dependencies and tools
    pkg_config_files: List[Path]
    path_tools: List[Dict[str, Any]]
    python_paths: List[Path]
    site_hooks: List[str]

    # Shared build environment state
    sysconfig_vars: Dict[str, Any] = field(default_factory=dict)
    build_env: Dict[str, str] = field(default_factory=dict)
    _layers: Optional[List[Dict[str, Any]]] = None
    config_settings: Dict[str, Any] = field(default_factory=dict)
    cc_layer: Optional[CcLayerState] = None
    is_crossenv: bool = False


def _short_windows_sdist_root(prefix: Path, original_sdist_root: str) -> Path:
    """Return a short, stable source path under bazel-out.

    Setuptools includes the full source path in MSVC object paths.
    Shortening it helps avoid Windows' 260-character path limit.
    """
    digest = hashlib.sha256(original_sdist_root.encode("utf-8")).hexdigest()[:16]
    return (prefix / "bazel-out" / "_pcr" / digest).absolute()


def remap_sdist_path(path: str, prefix: Path, original_sdist_root: str, sdist_root_dir: Path) -> str:
    """Return a source path updated to use the shorter directory.

    Windows builds extract sources into a shorter directory. Replace the old
    source directory in the returned path and keep the rest of the path.
    Return unrelated paths unchanged.
    """
    absolute_path = ntpath.normpath(ntpath.join(str(prefix), path))
    original_root = ntpath.normpath(ntpath.join(str(prefix), original_sdist_root))
    path_key = ntpath.normcase(absolute_path)
    root_key = ntpath.normcase(original_root)
    if path_key == root_key:
        return str(sdist_root_dir)
    if path_key.startswith(root_key + "\\"):
        suffix = absolute_path[len(original_root) + 1 :]
        return str(sdist_root_dir.joinpath(*suffix.split("\\")))
    return path


def remap_sdist_pythonpath(
    value: str, prefix: Path, original_sdist_root: str, sdist_root_dir: Path, pathsep: str
) -> str:
    """Update source entries in PYTHONPATH to use the shorter directory.

    Build processes use PYTHONPATH to find Python modules, including modules
    in the extracted sources. Keep other entries and their order unchanged.
    """
    return pathsep.join(
        remap_sdist_path(path, prefix, original_sdist_root, sdist_root_dir) for path in value.split(pathsep)
    )


def load_build_context(config_path: str) -> BuildContext:
    """Loads Bazel configuration and initializes a typed BuildContext."""
    with open(config_path, "r") as f:
        bazel_config = json.load(f)

    prefix = Path.cwd().absolute()
    temp_dir = (prefix / Path(os.environ["PYCROSS_BUILD_ROOT"])).absolute()
    original_sdist_root = os.environ["PYCROSS_SDIST_DIR"]
    if os.name == "nt":
        sdist_root_dir = _short_windows_sdist_root(prefix, original_sdist_root)
    else:
        sdist_root_dir = (prefix / Path(original_sdist_root)).absolute()
    source_dir = bazel_config.get("source_dir")
    if source_dir:
        sdist_dir = sdist_root_dir / source_dir
    else:
        sdist_dir = sdist_root_dir

    # Resolve configuration settings directly from bazel_config.
    config_settings = replace_path_placeholders(bazel_config.get("config_settings", {}), prefix)

    build_env = os.environ.copy()

    # Remove Bazel py_binary launcher variables that shouldn't leak into builds.
    from pycross.private.build.tools.utils.env import scrub_bazel_env

    scrub_bazel_env(build_env)

    # Default reproducibility settings for wheel timestamps and Python hash ordering
    # (user build_env below can still override either).
    build_env.setdefault("SOURCE_DATE_EPOCH", "315532800")
    build_env.setdefault("PYTHONHASHSEED", "0")

    # Merge user-supplied environment variables from the build_env attribute.
    # User vars take precedence over inherited environment.
    user_build_env = bazel_config.get("build_env", {})
    if os.name == "nt":
        # Windows treats Path and PATH as the same variable, but this dictionary
        # treats them as different keys. Uppercase user keys so they replace
        # inherited values instead of creating duplicates.
        user_build_env = {key.upper(): value for key, value in user_build_env.items()}
    if user_build_env:
        build_env.update(user_build_env)

    if os.name == "nt":
        build_env["PYCROSS_SDIST_DIR"] = str(sdist_root_dir)
        build_env["PYCROSS_BUILD_ROOT"] = str(temp_dir)
        if "PYTHONPATH" in build_env:
            build_env["PYTHONPATH"] = remap_sdist_pythonpath(
                build_env["PYTHONPATH"],
                prefix,
                original_sdist_root,
                sdist_root_dir,
                os.pathsep,
            )

    return BuildContext(
        bazel_config=bazel_config,
        prefix=prefix,
        temp_dir=temp_dir,
        sdist_root_dir=sdist_root_dir,
        original_sdist_root=original_sdist_root,
        sdist_dir=sdist_dir,
        env_dir=temp_dir / "env",
        tools_dir=temp_dir / "tools",
        sdist_path=(prefix / Path(bazel_config["sdist"])).absolute(),
        exec_python=(
            Path(bazel_config["exec_python"])
            if os.path.isabs(bazel_config["exec_python"])
            else (prefix / Path(bazel_config["exec_python"])).absolute()
        ),
        target_python=(
            Path(bazel_config["target_python"])
            if os.path.isabs(bazel_config["target_python"])
            else (prefix / Path(bazel_config["target_python"])).absolute()
        ),
        wheel_dir=(prefix / Path(bazel_config["wheel_dir"])).absolute(),
        pkg_config_files=[(prefix / Path(f)).absolute() for f in bazel_config.get("pkg_config_files", [])],
        path_tools=[
            {
                "name": tool["name"],
                "path": (prefix / Path(tool["path"])).absolute(),
            }
            for tool in bazel_config.get("path_tools", [])
        ],
        python_paths=[(prefix / Path(p)).absolute() for p in bazel_config.get("python_paths", [])],
        site_hooks=[replace_placeholder(prefix, h) for h in bazel_config.get("site_hooks", [])],
        build_env=build_env,
        config_settings=config_settings,
    )


EXT_BUILD_ROOT_PLACEHOLDER = "$$EXT_BUILD_ROOT$$"


def replace_placeholder(prefix: Path, value: str) -> str:
    """Replace $$EXT_BUILD_ROOT$$ placeholder in a single string value."""
    return value.replace(EXT_BUILD_ROOT_PLACEHOLDER, str(prefix))


def resolve_sandbox_path(prefix: Path, raw_path: str) -> str:
    """Replace $$EXT_BUILD_ROOT$$ placeholder and resolve relative paths against prefix.

    Returns the resolved absolute path as a string, or empty string if raw_path is empty.
    """
    if not raw_path:
        return ""
    path = raw_path.replace(EXT_BUILD_ROOT_PLACEHOLDER, str(prefix))
    if os.path.isabs(path):
        return path
    return str(prefix / path)


def replace_path_placeholders(data: Dict[str, Any], prefix: Path) -> Dict[str, Any]:
    """Replace $$EXT_BUILD_ROOT$$ placeholders in a dict of config values."""
    prefix_str = str(prefix)
    if prefix_str.endswith("/"):
        prefix_str = prefix_str[:-1]
    result = {}
    for k, v in data.items():
        if isinstance(v, list):
            result[k] = [vi.replace(EXT_BUILD_ROOT_PLACEHOLDER, prefix_str) if isinstance(vi, str) else vi for vi in v]
        elif isinstance(v, str):
            result[k] = v.replace(EXT_BUILD_ROOT_PLACEHOLDER, prefix_str)
        else:
            result[k] = v
    return result


def load_layers(ctx: BuildContext) -> List[Dict[str, Any]]:
    """Yield deserialized JSON build env target configurations."""
    if ctx._layers is not None:
        return ctx._layers

    envs = ctx.bazel_config.get("layers", [])
    result = []
    for layer_json_path_str in envs:
        layer_json_path = (ctx.prefix / Path(layer_json_path_str)).absolute()
        with open(layer_json_path, "r") as f:
            result.append(json.load(f))

    ctx._layers = result
    return result
