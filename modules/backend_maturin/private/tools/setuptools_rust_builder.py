"""Setuptools Rust / PEP 517 Rust builder."""

import sys

from private.tools import rust_common
from private.tools.cargo_manifest import find_cargo_dir

from pycross.private.build.tools.utils.lifecycle import BackendStrategy
from pycross.private.build.tools.utils.lifecycle import run_standard_build_lifecycle
from pycross.private.build.tools.utils.venv_utils import build_crossenv_or_standard_venv


def pre_build(ctx):
    cargo_dir = find_cargo_dir(backend="setuptools-rust")
    rust_common.configure_rust_env(ctx, cargo_dir, is_maturin=False)


def main():
    strategy = BackendStrategy(
        setup_venv=build_crossenv_or_standard_venv,
        pre_build=pre_build,
    )
    run_standard_build_lifecycle(sys.argv[1], strategy)


if __name__ == "__main__":
    main()
