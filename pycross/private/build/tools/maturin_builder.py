"""Maturin / PEP 517 Rust builder."""

import os
import re
import shlex
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
    is_native = target_triple == rust_config.get("host_triple")
    triple_env_name = target_triple.replace("-", "_").upper()

    version = ctx.sysconfig_vars.get("VERSION")
    if not version:
        version = ctx.sysconfig_vars.get("py_version_short")
    if not version:
        version = f"{sys.version_info.major}.{sys.version_info.minor}"

    sizeof_void_p = int(ctx.sysconfig_vars.get("SIZEOF_VOID_P", 8))
    pointer_width = str(sizeof_void_p * 8)

    mixin_lib_dir = ctx.temp_dir / "cc_mixin" / "lib"
    lib_name = f"python{version}"
    if mixin_lib_dir.exists():
        for f in mixin_lib_dir.glob("libpython*"):
            m = re.match(r"libpython(.*)\.(a|so|dylib)", f.name)
            if m:
                lib_name = f"python{m.group(1)}"
                break

    is_darwin = "apple-darwin" in target_triple
    is_linux = "linux" in target_triple
    ext_suffix = ctx.sysconfig_vars.get("EXT_SUFFIX")
    pyo3_config_lines = [
        "implementation=CPython",
        f"version={version}",
        "shared=true",
        "abi3=false",
        f"pointer_width={pointer_width}",
        f"executable={ctx.target_python.absolute()}",
        "suppress_build_script_link_lines=true",
    ]
    if ext_suffix:
        pyo3_config_lines.append(f"ext_suffix={ext_suffix}")
    if not is_darwin and not is_linux:
        pyo3_config_lines.append(f"extra_build_script_line=cargo:rustc-link-lib={lib_name}")
    if not is_darwin:
        pyo3_config_lines.append(f"extra_build_script_line=cargo:rustc-link-search=native={mixin_lib_dir.absolute()}")
    pyo3_config_path = ctx.temp_dir / "pyo3_config.txt"
    pyo3_config_path.write_text("\n".join(pyo3_config_lines) + "\n")

    ctx.build_env["PYO3_CONFIG_FILE"] = str(pyo3_config_path.absolute())
    ctx.build_env["PYO3_NO_PYTHON"] = "1"

    rustc_bin = resolve_sandbox_path(ctx.prefix, rust_config["rustc"])
    ctx.build_env["RUSTC"] = rustc_bin

    cargo_bin = None
    if rust_config.get("cargo"):
        cargo_bin = resolve_sandbox_path(ctx.prefix, rust_config["cargo"])
        ctx.build_env["CARGO"] = cargo_bin

    # Prevent maturin from attempting to auto-bootstrap Rust via puccinialin
    ctx.build_env["MATURIN_NO_INSTALL_RUST"] = "1"
    ctx.build_env["CARGO_BUILD_TARGET"] = target_triple

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
                host_stdlib_dst_path.unlink(missing_ok=True)

            host_stdlib_dst_path.parent.mkdir(parents=True, exist_ok=True)
            os.symlink(host_stdlib_src_path.resolve(), host_stdlib_dst_path)

            target_stdlib_src_path = ctx.prefix / Path(f"external/{cross_repo_name}/lib/rustlib/{target_triple}/lib")
            if target_stdlib_src_path and target_stdlib_dst_path:
                if not target_stdlib_src_path.exists():
                    raise RuntimeError(f"target_stdlib missing at {target_stdlib_src_path}")
                if target_stdlib_src_path != host_stdlib_src_path:
                    if target_stdlib_dst_path.exists() or target_stdlib_dst_path.is_symlink():
                        target_stdlib_dst_path.unlink(missing_ok=True)
                    target_stdlib_dst_path.parent.mkdir(parents=True, exist_ok=True)
                    os.symlink(target_stdlib_src_path.resolve(), target_stdlib_dst_path)
    except Exception as e:
        raise RuntimeError(f"Failed to populate hermetic Rust sysroot: {e}") from e

    wrapper_path = ctx.temp_dir / "rustc_wrapper"

    from pycross.private.build.tools.utils.cc_toolchain import _python_wrapper_shebang

    shebang = _python_wrapper_shebang(ctx.exec_python)

    ldflags = ctx.sysconfig_vars.get("LDFLAGS", "")
    ldflags_args = shlex.split(ldflags)

    wrapper_content = textwrap.dedent(f"""\
    {shebang}
    import os, sys

    real_rustc = sys.argv[1]
    args = sys.argv[2:]

    has_sysroot = any(arg.startswith("--sysroot") for arg in args)
    if not has_sysroot and os.path.isdir({repr(str(sysroot_dir.absolute()))}):
        args = ["--sysroot", {repr(str(sysroot_dir.absolute()))}] + args

    is_target = any({repr(target_triple)} in arg for arg in args) or {repr(is_native)}
    if is_target:
        for arg in {repr(ldflags_args)}:
            args.extend(["-C", f"link-arg={{arg}}"])

    os.execv(real_rustc, [real_rustc] + args)
    """)

    wrapper_path.write_text(wrapper_content)
    st = wrapper_path.stat()
    wrapper_path.chmod(st.st_mode | stat.S_IEXEC)

    # Write Cargo config to CARGO_HOME rather than ctx.prefix/.cargo/ to avoid
    # polluting the shared sandbox execroot. Cargo checks $CARGO_HOME/config.toml
    # with highest priority, so this is reliable as long as CARGO_HOME is set.
    cargo_home = ctx.temp_dir / "cargo_home"
    cargo_home.mkdir(parents=True, exist_ok=True)

    cargo_config_lines = ["[build]", f'rustc-wrapper = "{wrapper_path.absolute()}"']
    (cargo_home / "config.toml").write_text("\n".join(cargo_config_lines) + "\n")

    ctx.build_env["CARGO_HOME"] = str(cargo_home.absolute())

    # Ensure inherited RUSTFLAGS/CARGO_ENCODED_RUSTFLAGS don't leak into the
    # build — these conflict with per-target settings in the rustc wrapper.
    for var_name in ("RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"):
        ctx.build_env.pop(var_name, None)

    ctx.build_env["CARGO_TERM_VERBOSE"] = "true"
    ctx.build_env["PYO3_USE_ABI3_FORWARD_COMPATIBILITY"] = "1"


def main():
    strategy = BackendStrategy(
        setup_venv=setup_venv,
        pre_build=pre_build,
    )
    run_standard_build_lifecycle(sys.argv[1], strategy)


if __name__ == "__main__":
    main()
