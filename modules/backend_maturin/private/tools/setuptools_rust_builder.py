"""Setuptools Rust / PEP 517 Rust builder."""
# ruff: noqa: E402

import sys
from pathlib import Path

current_dir = Path(__file__).parent.absolute()
if str(current_dir) not in sys.path:
    sys.path.insert(0, str(current_dir))

import rust_common

from pycross.private.build.tools.utils.lifecycle import BackendStrategy
from pycross.private.build.tools.utils.lifecycle import run_standard_build_lifecycle
from pycross.private.build.tools.utils.venv_utils import build_crossenv_venv
from pycross.private.build.tools.utils.venv_utils import build_standard_venv


def setup_venv(ctx):
    is_cross = ctx.exec_python != ctx.target_python
    if is_cross or ctx.bazel_config.get("always_use_crossenv"):
        build_crossenv_venv(ctx)
    else:
        build_standard_venv(ctx)


def _get_cargo_dir() -> Path:
    """Find the directory containing Cargo.toml based on setuptools-rust config."""
    pyproject = Path("pyproject.toml")
    if pyproject.exists():
        try:
            try:
                import tomllib
            except ImportError:
                from pip._vendor import tomli as tomllib

            with open(pyproject, "rb") as f:
                data = tomllib.load(f)
            # Check setuptools-rust
            ext_modules = data.get("tool", {}).get("setuptools-rust", {}).get("ext-modules", [])
            if ext_modules and isinstance(ext_modules, list):
                manifest_path = ext_modules[0].get("path", "Cargo.toml")
                return Path(manifest_path).parent
        except Exception as e:
            print(f"WARNING: Failed to parse pyproject.toml for manifest-path: {e}", file=sys.stderr)
    return Path(".")


def pre_build(ctx):
    cargo_dir = _get_cargo_dir()
    rust_common.configure_rust_env(ctx, cargo_dir, is_maturin=False)


def main():
    strategy = BackendStrategy(
        setup_venv=setup_venv,
        pre_build=pre_build,
    )
    run_standard_build_lifecycle(sys.argv[1], strategy)


if __name__ == "__main__":
    main()
