import os
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from pycross.private.build.tools.utils.cc_toolchain import setup_cc_layer
from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import load_build_context
from pycross.private.build.tools.utils.context import load_layers
from pycross.private.build.tools.utils.context import replace_placeholder
from pycross.private.build.tools.utils.hooks import run_post_build_hooks
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
    setup_venv: Callable[[BuildContext], None] = build_standard_venv
    pre_build: Callable[[BuildContext], None] = lambda ctx: None
    prepare_env: Callable[[BuildContext], None] = lambda ctx: None


def setup_pkg_config(ctx: BuildContext) -> Path:
    """Materialize declared pkg-config .pc files and expose them via PKG_CONFIG_PATH."""
    pkgconfig_dir = ctx.temp_dir / "pkgconfig"
    pkgconfig_dir.mkdir(parents=True, exist_ok=True)
    if getattr(ctx, "_pkg_config_initialized", False):
        return pkgconfig_dir

    for pc_file in ctx.pkg_config_files:
        dest_pc = pkgconfig_dir / pc_file.name
        shutil.copy2(pc_file.absolute(), dest_pc)
        dest_pc.chmod(0o644)
        content = dest_pc.read_text()
        dest_pc.write_text(replace_placeholder(ctx.prefix, content))

    if ctx.pkg_config_files and hasattr(ctx, "build_env"):
        abs_pkgconfig_dir = pkgconfig_dir.resolve().as_posix()
        existing = ctx.build_env.get("PKG_CONFIG_PATH", "")
        parts = [p for p in existing.split(os.pathsep) if p] if existing else []
        if abs_pkgconfig_dir not in parts:
            parts.insert(0, abs_pkgconfig_dir)
        ctx.build_env["PKG_CONFIG_PATH"] = os.pathsep.join(parts)

    ctx._pkg_config_initialized = True
    return pkgconfig_dir


def _apply_pre_build_patches(ctx: BuildContext) -> None:
    """Apply pre-build patches to the extracted sdist directory."""
    patches = ctx.bazel_config.get("pre_build_patches", [])
    if not patches:
        return
    from pycross_patch import apply_patch_or_exit

    for patch_path in patches:
        abs_path = ctx.prefix / patch_path
        print(f"Applying pre-build patch: {abs_path}", file=sys.stderr)
        apply_patch_or_exit(ctx.sdist_dir, abs_path)


def run_standard_build_lifecycle(config_path: str, strategy: BackendStrategy) -> None:
    ctx = load_build_context(config_path)
    extract_sdist(ctx)
    os.chdir(ctx.sdist_dir)
    _inject_extra_files(ctx)
    _apply_pre_build_patches(ctx)

    ctx.sysconfig_vars = load_target_sysconfig(ctx)
    setup_path_tools(ctx)

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

    if ctx.pkg_config_files:
        setup_pkg_config(ctx)

    strategy.setup_venv(ctx)

    # Run pre-build hooks from the pre_build_hooks attribute.
    run_pre_build_hooks_from_config(ctx)

    strategy.pre_build(ctx)

    apply_sysconfig_overrides(ctx)

    strategy.prepare_env(ctx)

    wheel_file = run_pep517_build(ctx)
    wheel_file = run_post_build_hooks(ctx, wheel_file)
    print(f"Successfully built wheel: {wheel_file}")
