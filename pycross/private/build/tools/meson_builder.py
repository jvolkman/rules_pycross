"""Meson-specific PEP 517 builder using procedural composition with BuildContext."""

import os
import sys

from pycross.private.build.tools.builder_utils import apply_sysconfig_overrides
from pycross.private.build.tools.builder_utils import build_standard_venv
from pycross.private.build.tools.builder_utils import extract_sdist
from pycross.private.build.tools.builder_utils import load_build_context
from pycross.private.build.tools.builder_utils import load_mixins
from pycross.private.build.tools.builder_utils import load_target_sysconfig
from pycross.private.build.tools.builder_utils import run_pep517_build
from pycross.private.build.tools.builder_utils import run_pre_build_hook
from pycross.private.build.tools.builder_utils import setup_cc_mixin
from pycross.private.build.tools.builder_utils import setup_path_tools
from pycross.private.build.tools.meson_utils import generate_cross_ini


def main():
    # Initialize build context from Bazel JSON config
    ctx = load_build_context(sys.argv[1])

    # Extract the source distribution and enter it
    extract_sdist(ctx)
    os.chdir(ctx.sdist_dir)

    # Load target environment sysconfig variables
    ctx.sysconfig_vars = load_target_sysconfig(ctx)

    # Setup PATH tools (cython, ninja, etc.) before compiling or setting up venvs
    setup_path_tools(ctx)

    # 1. Setup C/C++ toolchain mixin first if present
    cc_mixin_config = None
    for mixin_config in load_mixins(ctx):
        if "CC" in mixin_config:
            cc_mixin_config = mixin_config
            setup_cc_mixin(ctx, mixin_config)

    # 2. Meson always uses standard native virtual environments as it manages
    # cross-compilation flags natively via its own cross.ini file.
    build_standard_venv(ctx)

    # 3. Process other build mixins (pre-build hooks, etc.)
    for mixin_config in load_mixins(ctx):
        if mixin_config.get("type") == "pre_build_hook":
            run_pre_build_hook(ctx, mixin_config)

    # 4. Meson-specific: always generate cross.ini and append it to the build options
    generate_cross_ini(ctx, cc_mixin_config)

    # Inject sysconfig overrides and write sitecustomize.py monkeypatches
    apply_sysconfig_overrides(ctx)

    # Run PEP 517 builder
    wheel_file = run_pep517_build(ctx)
    print(f"Successfully built Meson wheel: {wheel_file}")


if __name__ == "__main__":
    main()
