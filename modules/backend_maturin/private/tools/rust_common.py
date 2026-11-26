"""Common Rust toolchain setup for backend builders."""

import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import textwrap
from pathlib import Path

from pycross.private.build.tools.utils.cc_toolchain import parse_ar_and_guess_ranlib
from pycross.private.build.tools.utils.context import load_layers
from pycross.private.build.tools.utils.context import resolve_sandbox_path
from pycross.private.build.tools.utils.sysconfig_utils import SYSCONFIG_DATA_NAME


def load_toml_file(path: Path) -> dict:
    """Parse a TOML file using tomllib (Python 3.11+) or pip vendored tomli (Python 3.10)."""
    try:
        import tomllib
    except ImportError:
        from pip._vendor import tomli as tomllib  # type: ignore[no-redef]

    with open(path, "rb") as f:
        return tomllib.load(f)


def _find_cargo_workspace_root(cargo_dir: Path) -> Path:
    """Find the Cargo workspace root for cargo_dir, walking up to Path('.')."""
    candidates = [cargo_dir] + list(cargo_dir.parents)
    for d in candidates:
        manifest = d / "Cargo.toml"
        if manifest.exists():
            try:
                if "workspace" in load_toml_file(manifest):
                    return d
            except Exception:
                pass
    return cargo_dir


def get_pyo3_version(cargo_dir: Path):
    """Parse Cargo.lock (walking from cargo_dir up to sdist root) to find pyo3 version."""
    lock_path = None
    for d in [cargo_dir] + list(cargo_dir.parents):
        candidate = d / "Cargo.lock"
        if candidate.exists():
            lock_path = candidate
            break
    if not lock_path:
        return None

    try:
        lock_data = load_toml_file(lock_path)
        for pkg in lock_data.get("package", []):
            if pkg.get("name") == "pyo3":
                return pkg.get("version")
    except Exception as e:
        print(f"WARNING: Failed to parse Cargo.lock: {e}", file=sys.stderr)
    return None


def _symlink_stdlib(src_path: Path, dst_path: Path, label: str) -> None:
    if not src_path.exists():
        raise RuntimeError(f"{label} missing at {src_path}")
    if dst_path.exists() or dst_path.is_symlink():
        dst_path.unlink(missing_ok=True)
    dst_path.parent.mkdir(parents=True, exist_ok=True)
    os.symlink(src_path.resolve(), dst_path)


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

    cc_layer = getattr(ctx, "cc_layer", None)
    layer_lib_dir = cc_layer.layer_lib_dir if cc_layer is not None else ctx.temp_dir / "cc_layer" / "lib"
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

    # Relocate user-injected Cargo.lock to the Cargo workspace root (or manifest
    # directory if not part of a workspace), overwriting any existing lockfile.
    # Leave sdist-shipped root Cargo.lock files untouched.
    root_lock = Path("Cargo.lock")
    user_injected_lock = "Cargo.lock" in ctx.bazel_config.get("extra_files", {})
    if user_injected_lock and cargo_dir != Path(".") and root_lock.exists():
        lock_dir = _find_cargo_workspace_root(cargo_dir)
        target_lock = lock_dir / "Cargo.lock"
        if lock_dir != Path("."):
            target_lock.parent.mkdir(parents=True, exist_ok=True)
            if target_lock.exists():
                target_lock.unlink()
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
            sysconfigdata_path = layer_lib_dir / f"{SYSCONFIG_DATA_NAME}.py"
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

    if cc_layer is not None:
        wrapped_cc = str(cc_layer.cc_path)
        wrapped_cxx = str(cc_layer.cxx_path)
        ar = cc_layer.ar_list[0] if len(cc_layer.ar_list) == 1 else shlex.join(cc_layer.ar_list)
        ranlib_path = cc_layer.ranlib_path
        cflags_tokens = cc_layer.cflags
        cxxflags_tokens = cc_layer.cxxflags
        ldflags_args = list(cc_layer.ldflags)
    else:
        wrapped_cc = ctx.sysconfig_vars.get("CC", "")
        wrapped_cxx = ctx.sysconfig_vars.get("CXX", "")
        ar = ctx.sysconfig_vars.get("AR", "")
        _, ranlib_path = parse_ar_and_guess_ranlib(ar)
        cflags_tokens = shlex.split(ctx.sysconfig_vars.get("CFLAGS", ""))
        cxxflags_tokens = shlex.split(ctx.sysconfig_vars.get("CXXFLAGS", ""))
        ldflags_args = shlex.split(ctx.sysconfig_vars.get("LDFLAGS", ""))

    if not wrapped_cxx:
        raise ValueError("Wrapped CXX compiler not found in cc_layer or sysconfig_vars")
    ctx.build_env[f"CARGO_TARGET_{triple_env_name}_LINKER"] = wrapped_cxx

    for triple in (target_triple, target_triple.replace("-", "_")):
        ctx.build_env[f"CC_{triple}"] = wrapped_cc
        ctx.build_env[f"CXX_{triple}"] = wrapped_cxx
        if ar:
            ctx.build_env[f"AR_{triple}"] = ar
        if ranlib_path:
            ctx.build_env[f"RANLIB_{triple}"] = ranlib_path.as_posix()
        # cc-rs splits CFLAGS_<triple>/CXXFLAGS_<triple> on whitespace unless
        # CC_SHELL_ESCAPED_FLAGS is set (newer cc only). It prefers the
        # per-target vars, so pass unquoted tokens joined with spaces.
        if cflags_tokens:
            ctx.build_env[f"CFLAGS_{triple}"] = " ".join(cflags_tokens)
        if cxxflags_tokens:
            ctx.build_env[f"CXXFLAGS_{triple}"] = " ".join(cxxflags_tokens)

    host_triple = rust_config.get("host_triple", "")
    host_rustlib_rel = rust_config.get("host_rustlib_dir")
    target_rustlib_rel = rust_config.get("target_rustlib_dir")

    host_stdlib_src_path = Path(resolve_sandbox_path(ctx.prefix, host_rustlib_rel)) if host_rustlib_rel else None
    target_stdlib_src_path = Path(resolve_sandbox_path(ctx.prefix, target_rustlib_rel)) if target_rustlib_rel else None

    sysroot_dir = ctx.temp_dir / "sysroot"
    try:
        host_dst_path = None
        if host_stdlib_src_path and host_triple and (host_triple != target_triple or not target_stdlib_src_path):
            host_dst_path = sysroot_dir / "lib" / "rustlib" / host_triple / "lib"
            _symlink_stdlib(host_stdlib_src_path, host_dst_path, "host_stdlib")

        if target_stdlib_src_path:
            target_dst_path = sysroot_dir / "lib" / "rustlib" / target_triple / "lib"
            if target_dst_path != host_dst_path:
                _symlink_stdlib(target_stdlib_src_path, target_dst_path, "target_stdlib")
    except Exception as e:
        raise RuntimeError(f"Failed to populate hermetic Rust sysroot: {e}") from e

    wrapper_path = ctx.temp_dir / "rustc_wrapper"

    sysroot_dir_str = str(sysroot_dir.absolute())

    # Compute a host-independent toolchain identifier for the metadata hash.
    # `rustc --version` (without --verbose) reports only the Rust version and
    # commit hash, which is identical across build hosts.
    try:
        _toolchain_id = subprocess.check_output([rustc_bin, "--version"], text=True).strip()
    except (subprocess.CalledProcessError, OSError):
        _toolchain_id = target_triple

    wrapper_content = textwrap.dedent(f"""\
    #!/bin/sh
    "exec" "{ctx.exec_python.absolute()}" "-S" "$0" "$@"
    import hashlib
    import os
    import sys

    real_rustc = sys.argv[1]
    args = sys.argv[2:]

    sysroot_dir = {repr(sysroot_dir_str)}
    target_triple = {repr(target_triple)}
    is_native = {repr(is_native)}
    ldflags_args = {repr(ldflags_args)}
    toolchain_id = {repr(_toolchain_id)}

    def _parse_target(argv):
        for idx, token in enumerate(argv):
            if token == "--target" and idx + 1 < len(argv):
                return argv[idx + 1]
            if token.startswith("--target="):
                return token.split("=", 1)[1]
        return None

    def _parse_crate_name(argv):
        for idx, token in enumerate(argv):
            if token == "--crate-name" and idx + 1 < len(argv):
                return argv[idx + 1]
            if token.startswith("--crate-name="):
                return token.split("=", 1)[1]
        return None

    has_sysroot = any(arg == "--sysroot" or arg.startswith("--sysroot=") for arg in args)
    explicit_target = _parse_target(args)
    explicit_crate_name = _parse_crate_name(args)
    is_target = (explicit_target == target_triple) or (explicit_target is None and is_native)
    has_print = any(arg == "--print" or arg.startswith("--print=") for arg in args)
    is_probe = (
        not args
        or any(
            arg in ("-V", "-vV", "-Vv", "--version", "-h", "--help", "--explain")
            or arg.startswith("--explain=")
            for arg in args
        )
        or (has_print and explicit_crate_name in (None, "___"))
    )

    final_args = []
    if not has_sysroot and os.path.isdir(sysroot_dir):
        final_args.extend(["--sysroot", sysroot_dir])

    final_args.extend(args)

    if not is_probe:
        if is_target:
            for link_arg in ldflags_args:
                final_args.extend(["-C", f"link-arg={{link_arg}}"])

        # Remap sandbox paths for reproducible builds
        prefix = {repr(str(ctx.prefix))}
        final_args.extend(["--remap-path-prefix", f"{{prefix}}/="])
        final_args.extend(["--remap-path-prefix", f"{{prefix}}="])

        # Force single codegen unit for deterministic LLVM module IDs.
        # With multiple CGUs, LLVM generates non-deterministic module ID suffixes
        # (.llvm.NNNNN) in symbol names that can vary across build hosts.
        if is_target:
            final_args.extend(["-C", "codegen-units=1"])

        # Normalize -C metadata for cross-host reproducibility.
        # Cargo's metadata hash includes host-specific info (host triple from
        # rustc --version -v, paths to host-compiled build scripts, etc.).
        # We replace it with a deterministic hash derived from host-independent
        # inputs (including crate name, package name/version, edition, and target)
        # so multi-version crate graphs do not collide while staying identical
        # across build hosts. We leave -C extra-filename alone so Cargo can still
        # find its files.
        crate_name = None
        crate_types = []
        cfg_flags = []
        edition = ""
        i = 0
        while i < len(final_args):
            arg = final_args[i]
            if arg == "--crate-name" and i + 1 < len(final_args):
                crate_name = final_args[i + 1]
                i += 2
                continue
            if arg.startswith("--crate-name="):
                crate_name = arg.split("=", 1)[1]
            elif arg == "--crate-type" and i + 1 < len(final_args):
                crate_types.append(final_args[i + 1])
                i += 2
                continue
            elif arg.startswith("--crate-type="):
                crate_types.append(arg.split("=", 1)[1])
            elif arg == "--cfg" and i + 1 < len(final_args):
                cfg_flags.append(final_args[i + 1])
                i += 2
                continue
            elif arg.startswith("--cfg="):
                cfg_flags.append(arg.split("=", 1)[1])
            elif arg == "--edition" and i + 1 < len(final_args):
                edition = final_args[i + 1]
                i += 2
                continue
            elif arg.startswith("--edition="):
                edition = arg.split("=", 1)[1]
            i += 1

        if crate_name:
            cfg_flags.sort()
            crate_types.sort()
            pkg_name = os.environ.get("CARGO_PKG_NAME", "")
            pkg_version = os.environ.get("CARGO_PKG_VERSION", "")
            effective_target = explicit_target or (target_triple if is_native else "host")
            metadata_input = (
                f"{{toolchain_id}}\\0{{crate_name}}\\0{{pkg_name}}\\0{{pkg_version}}\\0{{edition}}"
                f"\\0{{effective_target}}\\0{{'|'.join(crate_types)}}\\0{{'|'.join(cfg_flags)}}"
            )
            stable_metadata = hashlib.sha256(metadata_input.encode()).hexdigest()[:16]
            i = 0
            while i < len(final_args):
                if final_args[i] == "-C" and i + 1 < len(final_args) and final_args[i + 1].startswith("metadata="):
                    final_args[i + 1] = f"metadata={{stable_metadata}}"
                    i += 2
                    continue
                if final_args[i].startswith("-Cmetadata="):
                    final_args[i] = f"-Cmetadata={{stable_metadata}}"
                i += 1

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
        abs_vendor_path = os.path.normpath(str((ctx.prefix / cargo_vendored_sources).absolute()))
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

    # Strip inherited RUSTFLAGS / CARGO_ENCODED_RUSTFLAGS (e.g. from --action_env)
    # so ambient flags don't override an sdist's .cargo/config.toml rustflags,
    # while preserving values explicitly set via rule build_env or pre-build hooks.
    # Also strip ARFLAGS: cc-rs prepends ARFLAGS before its own `cq` archiver
    # flags, causing `ar` to treat `cq` as the output archive.
    # sysconfig_vars["ARFLAGS"] stays intact for hybrid setuptools_rust C builds.
    user_build_env = ctx.bazel_config.get("build_env", {})
    for var_name in ("RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"):
        if var_name not in user_build_env and ctx.build_env.get(var_name) == os.environ.get(var_name):
            ctx.build_env.pop(var_name, None)
    ctx.build_env.pop("ARFLAGS", None)

    ctx.build_env.setdefault("CARGO_TERM_VERBOSE", "true")
    ctx.build_env.setdefault("PYO3_USE_ABI3_FORWARD_COMPATIBILITY", "1")
