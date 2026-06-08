import json
import os
from dataclasses import dataclass
from dataclasses import field
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Optional


@dataclass
class BuildContext:
    # Main configuration loaded from Bazel JSON
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
    wheelhouse: Path

    # Build dependencies and tools
    pkg_config_files: List[Path]
    path_tools: List[Dict[str, Any]]
    python_paths: List[Path]
    target_sys_path: List[Path]
    site_hooks: List[str]

    # Shared build environment state
    sysconfig_vars: Dict[str, Any] = field(default_factory=dict)
    build_env: Dict[str, str] = field(default_factory=dict)
    _layers: Optional[List[Dict[str, Any]]] = None
    config_settings: Dict[str, Any] = field(default_factory=dict)


def load_build_context(config_path: str) -> BuildContext:
    """Loads Bazel configuration and initializes a typed BuildContext."""
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
                config_settings = replace_path_placeholders(json.load(f), prefix)
        else:
            config_settings = {}
    else:
        config_settings = bazel_config.get("config_settings", {})

    build_env = os.environ.copy()

    # Bazel py_binary launcher adds PYTHONSAFEPATH=1. This breaks numpy and other
    # builds that rely on sys.path[0] being the script directory. Strip it.
    build_env.pop("PYTHONSAFEPATH", None)

    return BuildContext(
        bazel_config=bazel_config,
        prefix=prefix,
        temp_dir=temp_dir,
        sdist_dir=sdist_dir,
        env_dir=temp_dir / "env",
        bin_dir=temp_dir / "bin",
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
        wheelhouse=(prefix / Path(bazel_config["wheelhouse"])).absolute(),
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
