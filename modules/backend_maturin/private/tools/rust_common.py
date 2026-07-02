"""Common Rust toolchain setup for backend builders."""

import os
import re
import shlex
import shutil
import stat
import sys
import textwrap
from pathlib import Path

from pycross.private.build.tools.utils.context import load_layers
from pycross.private.build.tools.utils.context import resolve_sandbox_path


# NOTE: The canonical version of this logic is parse_ar_and_guess_ranlib in
# pycross/private/build/tools/utils/cc_toolchain.py. This copy avoids a
# cross-module import. Keep both copies in sync.
def guess_ranlib_path(ar: str | None) -> Path | None:
    """Guess ranlib path from AR path."""
    if not ar:
        return None
    ar_list = shlex.split(ar)
    if not ar_list:
        return None

    ar_path = Path(ar_list[0])
    if not ar_path.is_absolute():
        resolved_ar = shutil.which(str(ar_path))
        if resolved_ar:
            ar_path = Path(resolved_ar)

    stem = ar_path.stem
    if stem == "ar" or stem.endswith(("-ar", "_ar")):
        ranlib_stem = stem[:-2] + "ranlib"
        ranlib_name = ranlib_stem + ar_path.suffix

        if ar_path.is_absolute():
            guessed_ranlib_path = ar_path.parent / ranlib_name
            if guessed_ranlib_path.exists():
                return guessed_ranlib_path
        else:
            resolved_ranlib = shutil.which(ranlib_name)
            if resolved_ranlib:
                return Path(resolved_ranlib)
    return None


def get_pyo3_version(cargo_dir: Path):
    """Parse Cargo.lock to find the pyo3 version, if present."""
    lock_path = cargo_dir / "Cargo.lock"
    if not lock_path.exists():
        return None

    try:
        try:
            import tomllib
        except ImportError:
            from pip._vendor import tomli as tomllib

        with open(lock_path, "rb") as f:
            lock_data = tomllib.load(f)
        for pkg in lock_data.get("package", []):
            if pkg.get("name") == "pyo3":
                return pkg.get("version")
    except Exception as e:
        print(f"WARNING: Failed to parse Cargo.lock: {e}", file=sys.stderr)
    return None


def configure_rust_env(ctx, cargo_dir: Path, is_maturin: bool = False):
    rust_config = None
    for layer_config in load_layers(ctx):
        if "target_triple" in layer_config or "rustc" in layer_config:
            rust_config = layer_config
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

    layer_lib_dir = ctx.temp_dir / "cc_layer" / "lib"
    lib_name = f"python{version}"
    if layer_lib_dir.exists():
        for f in layer_lib_dir.glob("libpython*"):
            m = re.match(r"libpython(.*)\.(a|so|dylib)", f.name)
            if m:
                lib_name = f"python{m.group(1)}"
                break

    is_darwin = "apple-darwin" in target_triple
    is_linux = "linux" in target_triple
    ext_suffix = ctx.sysconfig_vars.get("EXT_SUFFIX")

    # Relocate injected Cargo.lock to manifest directory if needed
    root_lock = Path("Cargo.lock")
    target_lock = cargo_dir / "Cargo.lock"
    if cargo_dir != Path(".") and root_lock.exists() and not target_lock.exists():
        target_lock.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(root_lock), str(target_lock))
        print(f"Relocated Cargo.lock to {target_lock}", file=sys.stderr)

    pyo3_version = get_pyo3_version(cargo_dir)
    supports_ext_suffix = True
    if pyo3_version:
        try:
            # Strip pre-release suffixes (e.g. "0.18.0-rc1" -> "0.18.0")
            version_core = pyo3_version.split("-")[0].split("+")[0]
            parts = [int(x) for x in version_core.split(".")[:3]]
            if len(parts) >= 2 and (parts[0] == 0 and parts[1] < 18):
                supports_ext_suffix = False
        except ValueError:
            pass

    if supports_ext_suffix:
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
            pyo3_config_lines.append(
                f"extra_build_script_line=cargo:rustc-link-search=native={layer_lib_dir.absolute()}"
            )
        pyo3_config_path = ctx.temp_dir / "pyo3_config.txt"
        pyo3_config_path.write_text("\n".join(pyo3_config_lines) + "\n")

        ctx.build_env["PYO3_CONFIG_FILE"] = str(pyo3_config_path.absolute())
        ctx.build_env["PYO3_NO_PYTHON"] = "1"
    else:
        # Old PyO3 (< 0.18): let it query the crossenv Python directly,
        # but provide cross-compilation hints via environment variables.
        ctx.build_env["PYO3_CROSS_PYTHON_VERSION"] = version
        if layer_lib_dir.exists():
            ctx.build_env["PYO3_CROSS_LIB_DIR"] = str(layer_lib_dir.absolute())

            # Older PyO3 also looks for _sysconfigdata*.py in PYO3_CROSS_LIB_DIR.
            # Since rules_pycross sets _PYTHON_SYSCONFIGDATA_NAME to _sysconfigdata_pycross,
            # we write the target sysconfig variables to that name in the lib dir.
            sysconfigdata_path = layer_lib_dir / "_sysconfigdata_pycross.py"
            with open(sysconfigdata_path, "w") as f:
                f.write(f"build_time_vars = {repr(ctx.sysconfig_vars)}\n")
            print(f"Wrote target sysconfigdata to {sysconfigdata_path}", file=sys.stderr)

    rustc_bin = resolve_sandbox_path(ctx.prefix, rust_config["rustc"])
    ctx.build_env["RUSTC"] = rustc_bin

    cargo_bin = None
    if rust_config.get("cargo"):
        cargo_bin = resolve_sandbox_path(ctx.prefix, rust_config["cargo"])
        ctx.build_env["CARGO"] = cargo_bin

    if is_maturin:
        # Prevent maturin from attempting to auto-bootstrap Rust via puccinialin
        ctx.build_env["MATURIN_NO_INSTALL_RUST"] = "1"

    ctx.build_env["CARGO_BUILD_TARGET"] = target_triple

    wrapped_cxx = ctx.sysconfig_vars.get("CXX")
    if not wrapped_cxx:
        raise ValueError("Wrapped CXX compiler not found in sysconfig_vars")
    ctx.build_env[f"CARGO_TARGET_{triple_env_name}_LINKER"] = wrapped_cxx

    ar = ctx.sysconfig_vars.get("AR")
    ranlib_path = guess_ranlib_path(ar)

    for triple in (target_triple, target_triple.replace("-", "_")):
        ctx.build_env[f"CC_{triple}"] = ctx.sysconfig_vars["CC"]
        ctx.build_env[f"CXX_{triple}"] = ctx.sysconfig_vars["CXX"]
        if ar:
            ctx.build_env[f"AR_{triple}"] = ar
        if ranlib_path:
            ctx.build_env[f"RANLIB_{triple}"] = ranlib_path.as_posix()

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

    ldflags = ctx.sysconfig_vars.get("LDFLAGS", "")
    ldflags_args = shlex.split(ldflags)

    sysroot_dir_str = str(sysroot_dir.absolute())

    wrapper_content = textwrap.dedent(f"""\
    #!/bin/sh
    "exec" "{ctx.exec_python.absolute()}" "-S" "$0" "$@"
    import os
    import sys

    real_rustc = sys.argv[1]
    args = sys.argv[2:]

    sysroot_dir = {repr(sysroot_dir_str)}
    target_triple = {repr(target_triple)}
    is_native = {repr(is_native)}
    ldflags_args = {repr(ldflags_args)}

    has_sysroot = any(arg.startswith("--sysroot") for arg in args)
    is_target = any(target_triple in arg for arg in args)

    if is_native:
        is_target = True

    final_args = []
    if not has_sysroot and os.path.isdir(sysroot_dir):
        final_args.extend(["--sysroot", sysroot_dir])

    final_args.extend(args)

    if is_target:
        for link_arg in ldflags_args:
            final_args.extend(["-C", f"link-arg={{link_arg}}"])

    os.execv(real_rustc, [real_rustc] + final_args)
    """)

    wrapper_path.write_text(wrapper_content)
    st = wrapper_path.stat()
    wrapper_path.chmod(st.st_mode | stat.S_IEXEC)

    cargo_home = ctx.temp_dir / "cargo_home"
    cargo_home.mkdir(parents=True, exist_ok=True)

    cargo_config_lines = ["[build]", f'rustc-wrapper = "{wrapper_path.absolute()}"']

    cargo_vendored_sources = ctx.build_env.get("CARGO_VENDORED_SOURCES")
    if cargo_vendored_sources:
        abs_vendor_path = (ctx.prefix / cargo_vendored_sources).absolute()
        cargo_config_lines.extend(
            [
                "",
                "[source.crates-io]",
                'replace-with = "vendored-sources"',
                "",
                "[source.vendored-sources]",
                f'directory = "{abs_vendor_path}"',
            ]
        )
        ctx.build_env["CARGO_NET_OFFLINE"] = "true"

    (cargo_home / "config.toml").write_text("\n".join(cargo_config_lines) + "\n")

    ctx.build_env["CARGO_HOME"] = str(cargo_home.absolute())

    for var_name in ("RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"):
        ctx.build_env.pop(var_name, None)

    ctx.build_env["CARGO_TERM_VERBOSE"] = "true"
    ctx.build_env["PYO3_USE_ABI3_FORWARD_COMPATIBILITY"] = "1"
