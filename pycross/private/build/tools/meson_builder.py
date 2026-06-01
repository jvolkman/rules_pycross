"""Meson PEP 517 builder."""

import sys

from pycross.private.build.tools.meson_utils import generate_cross_ini
from pycross.private.build.tools.utils.context import load_layers
from pycross.private.build.tools.utils.lifecycle import BackendStrategy
from pycross.private.build.tools.utils.lifecycle import run_standard_build_lifecycle


def pre_build(ctx):
    cc_layer_config = next((m for m in load_layers(ctx) if "CC" in m), None)
    generate_cross_ini(ctx, cc_layer_config)


def prepare_env(ctx):
    ctx.build_env["MESON_FORCE_BACKTRACE"] = "1"
    for key in ["CC", "CXX", "CFLAGS", "CXXFLAGS", "LDFLAGS", "LDSHAREDFLAGS", "AR", "ARFLAGS"]:
        ctx.build_env.pop(key, None)


def main():
    strategy = BackendStrategy(
        pre_build=pre_build,
        prepare_env=prepare_env,
    )
    import os

    print("PYTHONPATH:", os.environ.get("PYTHONPATH"))
    run_standard_build_lifecycle(sys.argv[1], strategy)


if __name__ == "__main__":
    main()
