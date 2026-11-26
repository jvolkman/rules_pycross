"""Maturin / PEP 517 Rust builder."""

import sys
from pathlib import Path

from private.tools import rust_common
from private.tools.cargo_manifest import find_cargo_dir

from pycross.private.build.tools.utils.lifecycle import BackendStrategy
from pycross.private.build.tools.utils.lifecycle import run_standard_build_lifecycle
from pycross.private.build.tools.utils.venv_utils import build_crossenv_or_standard_venv


def _disable_sbom() -> None:
    """Disable maturin SBOM generation for reproducibility.

    The generated CycloneDX SBOM contains non-reproducible data (random UUIDs,
    timestamps, and absolute sandbox paths). Maturin only supports disabling
    SBOM via pyproject.toml, so we patch it in the extracted sdist.
    """
    pyproject = Path("pyproject.toml")
    if pyproject.exists():
        content = pyproject.read_text()
        if "[tool.maturin.sbom]" not in content:
            content += "\n[tool.maturin.sbom]\nrust = false\nauditwheel = false\n"
            pyproject.write_text(content)


def pre_build(ctx):
    _disable_sbom()
    cargo_dir = find_cargo_dir(backend="maturin")
    rust_common.configure_rust_env(ctx, cargo_dir, is_maturin=True)


def main():
    strategy = BackendStrategy(
        setup_venv=build_crossenv_or_standard_venv,
        pre_build=pre_build,
    )
    run_standard_build_lifecycle(sys.argv[1], strategy)


if __name__ == "__main__":
    main()
