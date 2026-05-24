"""Maturin / PEP 517 Rust builder using procedural composition with BuildContext."""

import os
import re
import shlex
import shutil
import stat
import sys
import textwrap
from pathlib import Path

from pycross.private.build.tools.utils.context import load_mixins
from pycross.private.build.tools.utils.context import resolve_sandbox_path
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


def pre_build(ctx):
    rust_config = None
    for mixin_config in load_mixins(ctx):
        if "target_triple" in mixin_config or "rustc" in mixin_config:
            rust_config = mixin_config
            break

    if not rust_config:
        return

    target_triple = rust_config.get("target_triple")
    if not target_triple:
        raise ValueError("target_triple must be defined in rust_config")
    triple_env_name = target_triple.replace("-", "_").upper()

    version = ctx.sysconfig_vars.get("VERSION")
    if not version:
        version = ctx.sysconfig_vars.get("py_version_short")
    if not version:
        version = f"{sys.version_info.major}.{sys.version_info.minor}"

    sizeof_void_p = int(ctx.sysconfig_vars.get("SIZEOF_VOID_P", 8))
    pointer_width = str(sizeof_void_p * 8)

    hook_lib_dir = ctx.temp_dir / "cc_hook" / "lib"
    lib_name = f"python{version}"
    if hook_lib_dir.exists():
        for f in hook_lib_dir.glob("libpython*"):
            m = re.match(r"libpython(.*)\.(a|so|dylib)", f.name)
            if m:
                lib_name = f"python{m.group(1)}"
                break

    is_darwin = "apple-darwin" in target_triple
    pyo3_config_lines = [
        "implementation=CPython",
        f"version={version}",
        "shared=true",
        "abi3=false",
        f"pointer_width={pointer_width}",
        f"executable={ctx.target_python.absolute()}",
        "suppress_build_script_link_lines=true",
    ]
    if not is_darwin:
        pyo3_config_lines.extend(
            [
                f"extra_build_script_line=cargo:rustc-link-search=native={hook_lib_dir.absolute()}",
                f"extra_build_script_line=cargo:rustc-link-lib={lib_name}",
            ]
        )
    pyo3_config_path = ctx.temp_dir / "pyo3_config.txt"
    pyo3_config_path.write_text("\n".join(pyo3_config_lines) + "\n")

    ctx.build_env["PYO3_CONFIG_FILE"] = str(pyo3_config_path.absolute())
    ctx.build_env["PYO3_NO_PYTHON"] = "1"

    ctx.build_env["RUSTC"] = resolve_sandbox_path(ctx.prefix, rust_config["rustc"])
    if rust_config.get("cargo"):
        ctx.build_env["CARGO"] = resolve_sandbox_path(ctx.prefix, rust_config["cargo"])

    wrapped_cxx = ctx.sysconfig_vars.get("CXX")
    if not wrapped_cxx:
        raise ValueError("Wrapped CXX compiler not found in sysconfig_vars")
    ctx.build_env[f"CARGO_TARGET_{triple_env_name}_LINKER"] = wrapped_cxx

    for triple in (target_triple, target_triple.replace("-", "_")):
        ctx.build_env[f"CC_{triple}"] = ctx.sysconfig_vars["CC"]
        ctx.build_env[f"CXX_{triple}"] = ctx.sysconfig_vars["CXX"]
        ctx.build_env[f"AR_{triple}"] = ctx.sysconfig_vars["AR"]

    host_stdlib_src = ""
    cross_repo_name = ""
    host_triple = ""
    repo_idx = rust_config["sysroot"].find("rules_rust++rust+")
    if repo_idx != -1:
        repo_end = rust_config["sysroot"].find("/", repo_idx)
        cross_repo_name = rust_config["sysroot"][repo_idx:repo_end]
        host_triple = rust_config.get("host_triple")
        if not host_triple:
            raise RuntimeError("host_triple must be defined in rust_config")
        host_repo_name = cross_repo_name.replace(target_triple, host_triple)
        host_stdlib_src = resolve_sandbox_path(ctx.prefix, f"external/{host_repo_name}/lib/rustlib/{host_triple}/lib")
    else:
        print(
            "WARNING: Could not parse rules_rust bzlmod repository name from sysroot. Host stdlib will not be injected.",
            file=sys.stderr,
        )

    host_stdlib_src_path = Path(host_stdlib_src) if host_stdlib_src else None
    sysroot_dir = ctx.temp_dir / "sysroot"
    host_stdlib_dst_path = sysroot_dir / Path(f"lib/rustlib/{host_triple}/lib") if host_stdlib_src else None
    target_stdlib_dst_path = sysroot_dir / Path(f"lib/rustlib/{target_triple}/lib")

    try:
        if host_stdlib_src_path:
            if not host_stdlib_src_path.exists():
                raise RuntimeError(f"host_stdlib missing at {host_stdlib_src_path}")
            if host_stdlib_dst_path.exists() or host_stdlib_dst_path.is_symlink():
                if host_stdlib_dst_path.is_symlink():
                    host_stdlib_dst_path.unlink(missing_ok=True)
                else:
                    shutil.rmtree(host_stdlib_dst_path, ignore_errors=True)

            host_stdlib_dst_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(host_stdlib_src_path, host_stdlib_dst_path, symlinks=False, dirs_exist_ok=True)

            target_stdlib_src_path = ctx.prefix / Path(f"external/{cross_repo_name}/lib/rustlib/{target_triple}/lib")
            if target_stdlib_src_path and target_stdlib_dst_path:
                if not target_stdlib_src_path.exists():
                    raise RuntimeError(f"target_stdlib missing at {target_stdlib_src_path}")
                if target_stdlib_src_path != host_stdlib_src_path:
                    if target_stdlib_dst_path.exists() or target_stdlib_dst_path.is_symlink():
                        if target_stdlib_dst_path.is_symlink():
                            target_stdlib_dst_path.unlink(missing_ok=True)
                        else:
                            shutil.rmtree(target_stdlib_dst_path, ignore_errors=True)
                    target_stdlib_dst_path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copytree(target_stdlib_src_path, target_stdlib_dst_path, symlinks=False, dirs_exist_ok=True)
    except Exception as e:
        raise RuntimeError(f"Failed to populate hermetic Rust sysroot: {e}") from e

    wrapper_path = ctx.temp_dir / "rustc_wrapper"

    ldflags = ctx.sysconfig_vars.get("LDFLAGS", "")
    ldflags_args = shlex.split(ldflags)

    wrapper_content = textwrap.dedent(f"""    #!{ctx.exec_python.absolute()} -S
    import os, sys

    real_rustc = sys.argv[1]
    args = sys.argv[2:]

    has_sysroot = any(arg.startswith("--sysroot") for arg in args)
    if not has_sysroot and os.path.isdir({repr(str(sysroot_dir.absolute()))}):
        args = ["--sysroot", {repr(str(sysroot_dir.absolute()))}] + args

    is_target = any({repr(target_triple)} in arg for arg in args)
    if is_target:
        for arg in {repr(ldflags_args)}:
            args.extend(["-C", f"link-arg={{arg}}"])

    os.execv(real_rustc, [real_rustc] + args)
    """)

    wrapper_path.write_text(wrapper_content)
    st = wrapper_path.stat()
    wrapper_path.chmod(st.st_mode | stat.S_IEXEC)

    parent_cargo_dir = ctx.prefix / ".cargo"
    parent_cargo_dir.mkdir(parents=True, exist_ok=True)

    parent_flat_config = parent_cargo_dir / "config"
    if parent_flat_config.exists() or parent_flat_config.is_symlink():
        parent_flat_config.unlink(missing_ok=True)

    cargo_config_lines = ["[build]", f'rustc-wrapper = "{wrapper_path.absolute()}"']
    (parent_cargo_dir / "config.toml").write_text("\n".join(cargo_config_lines) + "\n")

    cargo_home = ctx.temp_dir / "cargo_home"
    cargo_home.mkdir(parents=True, exist_ok=True)

    ctx.build_env["CARGO_HOME"] = str(cargo_home.absolute())
    os.environ["CARGO_HOME"] = str(cargo_home.absolute())

    for var_name in ("RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"):
        if var_name in ctx.build_env:
            del ctx.build_env[var_name]
        if var_name in os.environ:
            del os.environ[var_name]

    ctx.build_env["CARGO_TERM_VERBOSE"] = "true"
    ctx.build_env["PYO3_USE_ABI3_FORWARD_COMPATIBILITY"] = "1"
    os.environ["PYO3_USE_ABI3_FORWARD_COMPATIBILITY"] = "1"


def main():
    strategy = BackendStrategy(
        setup_venv=setup_venv,
        pre_build=pre_build,
    )
    run_standard_build_lifecycle(sys.argv[1], strategy)


if __name__ == "__main__":
    main()
