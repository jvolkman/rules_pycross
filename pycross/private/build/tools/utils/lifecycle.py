import os
import sys
from dataclasses import dataclass
from typing import Callable

from pycross.private.build.tools.utils.cc_toolchain import setup_cc_mixin
from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import load_build_context
from pycross.private.build.tools.utils.context import load_mixins
from pycross.private.build.tools.utils.hooks import run_pre_build_hook
from pycross.private.build.tools.utils.path_tools import setup_path_tools
from pycross.private.build.tools.utils.pep517_runner import run_pep517_build
from pycross.private.build.tools.utils.sdist import extract_sdist
from pycross.private.build.tools.utils.sysconfig_utils import apply_sysconfig_overrides
from pycross.private.build.tools.utils.sysconfig_utils import load_target_sysconfig
from pycross.private.build.tools.utils.venv_utils import build_standard_venv


@dataclass
class BackendStrategy:
    setup_toolchains: Callable[[BuildContext], None] = lambda ctx: None
    setup_venv: Callable[[BuildContext], None] = build_standard_venv
    pre_build: Callable[[BuildContext], None] = lambda ctx: None
    prepare_env: Callable[[BuildContext], None] = lambda ctx: None


def run_standard_build_lifecycle(config_path: str, strategy: BackendStrategy) -> None:
    ctx = load_build_context(config_path)
    extract_sdist(ctx)
    os.chdir(ctx.sdist_dir)

    ctx.sysconfig_vars = load_target_sysconfig(ctx)
    setup_path_tools(ctx)

    strategy.setup_toolchains(ctx)

    cc_config = None
    cc_mixin_count = 0
    for mixin_config in load_mixins(ctx):
        if "CC" in mixin_config:
            cc_mixin_count += 1
            if cc_config is None:
                cc_config = mixin_config

    if cc_mixin_count > 1:
        print(
            f"WARNING: {cc_mixin_count} CC mixins found, but only the first one will be applied.",
            file=sys.stderr,
        )

    if cc_config:
        setup_cc_mixin(ctx, cc_config)

    strategy.setup_venv(ctx)

    for mixin_config in load_mixins(ctx):
        if mixin_config.get("type") == "pre_build_hook":
            run_pre_build_hook(ctx, mixin_config)

    strategy.pre_build(ctx)

    apply_sysconfig_overrides(ctx)

    strategy.prepare_env(ctx)

    wheel_file = run_pep517_build(ctx)
    print(f"Successfully built wheel: {wheel_file}")
