"""Stdlib-only Cargo manifest discovery and TOML loading helpers."""

import sys
from pathlib import Path
from typing import Optional


def load_toml_file(path: Path) -> dict:
    """Parse a TOML file using tomllib (Python 3.11+) or pip vendored tomli (Python 3.10)."""
    try:
        import tomllib
    except ImportError:
        from pip._vendor import tomli as tomllib  # type: ignore[no-redef]

    with open(path, "rb") as f:
        return tomllib.load(f)


def find_cargo_dir(sdist_root: Path = Path("."), backend: Optional[str] = None) -> Path:
    """Find the directory containing Cargo.toml from pyproject.toml.

    Checks ``[tool.maturin].manifest-path`` and/or
    ``[tool.setuptools-rust].ext-modules[0].path`` depending on ``backend``
    (``"maturin"``, ``"setuptools-rust"``, or ``None`` to check both).
    Falls back to ``sdist_root`` if ``pyproject.toml`` is missing or unparsable.
    """
    pyproject_path = sdist_root / "pyproject.toml"
    if not pyproject_path.exists():
        return sdist_root

    try:
        data = load_toml_file(pyproject_path)
    except Exception as e:
        print(f"WARNING: Failed to parse pyproject.toml for manifest-path: {e}", file=sys.stderr)
        return sdist_root

    tool_cfg = data.get("tool", {})
    if not isinstance(tool_cfg, dict):
        return sdist_root

    manifest_path = None
    if backend in (None, "maturin"):
        maturin_cfg = tool_cfg.get("maturin", {})
        if isinstance(maturin_cfg, dict) and "manifest-path" in maturin_cfg:
            manifest_path = maturin_cfg["manifest-path"]

    if manifest_path is None and backend in (None, "setuptools-rust"):
        sr_cfg = tool_cfg.get("setuptools-rust", {})
        ext_modules = sr_cfg.get("ext-modules", []) if isinstance(sr_cfg, dict) else []
        if isinstance(ext_modules, list) and ext_modules and isinstance(ext_modules[0], dict):
            manifest_path = ext_modules[0].get("path")

    if manifest_path:
        return (sdist_root / manifest_path).parent
    return sdist_root
