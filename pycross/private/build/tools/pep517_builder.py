"""Generic PEP 517 builder (used by setuptools, hatchling, flit-core, etc.)."""

import sys

from pycross.private.build.tools.utils.lifecycle import BackendStrategy
from pycross.private.build.tools.utils.lifecycle import run_standard_build_lifecycle
from pycross.private.build.tools.utils.venv_utils import build_crossenv_or_standard_venv


def main():
    strategy = BackendStrategy(
        setup_venv=build_crossenv_or_standard_venv,
    )
    run_standard_build_lifecycle(sys.argv[1], strategy)


if __name__ == "__main__":
    main()
