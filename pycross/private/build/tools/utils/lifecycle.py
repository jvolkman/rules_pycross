import os
import shutil
import sys
from dataclasses import dataclass
from typing import Callable

from pycross.private.build.tools.utils.cc_toolchain import setup_cc_layer
from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import load_build_context
from pycross.private.build.tools.utils.context import load_layers
from pycross.private.build.tools.utils.hooks import run_post_build_hooks
from pycross.private.build.tools.utils.hooks import run_pre_build_hook
from pycross.private.build.tools.utils.hooks import run_pre_build_hooks_from_config
from pycross.private.build.tools.utils.path_tools import setup_path_tools
from pycross.private.build.tools.utils.pep517_runner import run_pep517_build
from pycross.private.build.tools.utils.sdist import extract_sdist
from pycross.private.build.tools.utils.sysconfig_utils import apply_sysconfig_overrides
from pycross.private.build.tools.utils.sysconfig_utils import load_target_sysconfig
from pycross.private.build.tools.utils.venv_utils import build_standard_venv


def _inject_extra_files(ctx: BuildContext) -> None:
    """Copy extra files from the Bazel config into the sdist directory.

    This handles files like user-provided lockfiles that need to be present
    in the source tree before the build backend runs.
    """
    extra_files = ctx.bazel_config.get("extra_files", {})
    for target_name, source_path in extra_files.items():
        src = ctx.prefix / source_path
        dst = ctx.sdist_dir / target_name
        print(f"Injecting {target_name} from {src}", file=sys.stderr)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(str(src), str(dst))


@dataclass
class BackendStrategy:
    setup_toolchains: Callable[[BuildContext], None] = lambda ctx: None
    setup_venv: Callable[[BuildContext], None] = build_standard_venv
    pre_build: Callable[[BuildContext], None] = lambda ctx: None
    prepare_env: Callable[[BuildContext], None] = lambda ctx: None


def _apply_pre_build_patches(ctx: BuildContext) -> None:
    """Apply pre-build patches to the extracted sdist directory."""
    patches = ctx.bazel_config.get("pre_build_patches", [])
    if not patches:
        return
    import patch_ng

    for patch_path in patches:
        abs_path = ctx.prefix / patch_path
        print(f"Applying pre-build patch: {abs_path}", file=sys.stderr)
        patch_file = patch_ng.fromfile(str(abs_path))
        if not patch_file:
            raise SystemExit(f"error: failed to parse patch file: {abs_path}")
        if not patch_file.apply(root=ctx.sdist_dir):
            raise SystemExit(f"error: failed to apply patch file: {abs_path}")


def run_standard_build_lifecycle(config_path: str, strategy: BackendStrategy) -> None:
    ctx = load_build_context(config_path)
    extract_sdist(ctx)
    os.chdir(ctx.sdist_dir)
    _inject_extra_files(ctx)
    _apply_pre_build_patches(ctx)

    ctx.sysconfig_vars = load_target_sysconfig(ctx)
    setup_path_tools(ctx)

    strategy.setup_toolchains(ctx)

    cc_config = None
    cc_layer_count = 0
    for layer_config in load_layers(ctx):
        if "CC" in layer_config:
            cc_layer_count += 1
            if cc_config is None:
                cc_config = layer_config

    if cc_layer_count > 1:
        print(
            f"WARNING: {cc_layer_count} CC envs found, but only the first one will be applied.",
            file=sys.stderr,
        )

    if cc_config:
        setup_cc_layer(ctx, cc_config)

    strategy.setup_venv(ctx)

    for layer_config in load_layers(ctx):
        if layer_config.get("type") == "pre_build_hook":
            run_pre_build_hook(ctx, layer_config)

    # Run pre-build hooks from the pre_build_hooks attribute.
    run_pre_build_hooks_from_config(ctx)

    strategy.pre_build(ctx)

    apply_sysconfig_overrides(ctx)

    strategy.prepare_env(ctx)

    wheel_file = run_pep517_build(ctx)
    wheel_file = run_post_build_hooks(ctx, wheel_file)
    print(f"Successfully built wheel: {wheel_file}")
