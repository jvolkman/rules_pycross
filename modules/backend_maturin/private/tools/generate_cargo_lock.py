"""A tool to generate Cargo.lock for an sdist."""

import argparse
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path
from typing import Optional


def derive_default_output(sdist_path: Path) -> str:
    name = sdist_path.name
    for ext in (".tar.gz", ".tgz", ".zip"):
        if name.endswith(ext):
            name = name[: -len(ext)]
            break
    parts = name.rsplit("-", 1)
    if len(parts) == 2:
        pkg_name, version = parts
        pkg_name = pkg_name.replace("_", "-")
        return f"{pkg_name}@{version}.lock"
    return "Cargo.lock"


def _extract_sdist(sdist_path: Path, dest: Path) -> None:
    if sdist_path.name.endswith(".zip"):
        with zipfile.ZipFile(sdist_path, "r") as zf:
            zf.extractall(dest)
    else:
        with tarfile.open(sdist_path, "r:*") as tar:
            if hasattr(tarfile, "data_filter"):
                tar.extraction_filter = tarfile.data_filter
            tar.extractall(path=dest)


def _find_cargo_toml_dir_from_pyproject(sdist_root: Path) -> Optional[Path]:
    pyproject_path = sdist_root / "pyproject.toml"
    if not pyproject_path.exists():
        return sdist_root

    try:
        import tomllib
    except ImportError:
        try:
            from pip._vendor import tomli as tomllib  # type: ignore[no-redef]
        except ImportError:
            print("Warning: tomllib/tomli not found. Searching for Cargo.toml instead.", file=sys.stderr)
            return None

    try:
        with open(pyproject_path, "rb") as f:
            pyproject_data = tomllib.load(f)
        tool_cfg = pyproject_data.get("tool", {})
        maturin_cfg = tool_cfg.get("maturin", {})
        if maturin_cfg and "manifest-path" in maturin_cfg:
            manifest_path = maturin_cfg["manifest-path"]
        else:
            ext_modules = tool_cfg.get("setuptools-rust", {}).get("ext-modules", [])
            if ext_modules and isinstance(ext_modules, list) and isinstance(ext_modules[0], dict):
                manifest_path = ext_modules[0].get("path", "Cargo.toml")
            else:
                manifest_path = "Cargo.toml"
        return (sdist_root / manifest_path).parent
    except Exception as e:
        print(
            f"Warning: Failed to parse pyproject.toml: {e}. Searching for Cargo.toml instead.",
            file=sys.stderr,
        )
        return None


def main():
    parser = argparse.ArgumentParser(description="Generate Cargo.lock for an sdist.")
    parser.add_argument("--sdist", required=True, help="Path to the sdist tarball.")
    parser.add_argument("--output", help="Path to write the Cargo.lock to. Defaults to package@version.lock.")
    parser.add_argument("--cargo", default="cargo", help="Path to the cargo binary.")
    args = parser.parse_args()

    sdist_path = Path(args.sdist)
    if not sdist_path.exists():
        print(f"Error: sdist file not found: {sdist_path}", file=sys.stderr)
        sys.exit(1)

    output_str = args.output
    if not output_str:
        output_str = derive_default_output(sdist_path)
        print(f"Defaulting output to {output_str}")

    output_path = Path(output_str)
    # If running under bazel run, resolve relative output path to workspace root
    workspace_dir = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if workspace_dir and not output_path.is_absolute():
        output_path = Path(workspace_dir) / output_path

    cargo_cmd = args.cargo
    if os.sep in cargo_cmd or "/" in cargo_cmd:
        # Use abspath (not resolve) so symlinks such as rustup/cargo proxies
        # preserve their argv[0] dispatch name.
        cargo_cmd = os.path.abspath(cargo_cmd)

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        print(f"Extracting {sdist_path} to {tmp_path}...")
        _extract_sdist(sdist_path, tmp_path)

        # Find sdist root (should be a single directory in tmpdir)
        sdist_root = None
        for child in tmp_path.iterdir():
            if child.is_dir():
                sdist_root = child
                break
        if not sdist_root:
            sdist_root = tmp_path

        # Find Cargo.toml.
        # We also want to support manifest-path if defined in pyproject.toml
        cargo_toml_dir = _find_cargo_toml_dir_from_pyproject(sdist_root)

        if not cargo_toml_dir or not (cargo_toml_dir / "Cargo.toml").exists():
            # Fallback to searching
            print("Searching for Cargo.toml...")
            cargo_toml_paths = list(sdist_root.glob("**/Cargo.toml"))
            if not cargo_toml_paths:
                print("Error: Cargo.toml not found in sdist.", file=sys.stderr)
                sys.exit(1)
            if len(cargo_toml_paths) > 1:
                print(f"Warning: Found multiple Cargo.toml files, using {cargo_toml_paths[0]}", file=sys.stderr)
            cargo_toml_dir = cargo_toml_paths[0].parent

        print(f"Running '{cargo_cmd} generate-lockfile' in {cargo_toml_dir}...")
        try:
            subprocess.run([cargo_cmd, "generate-lockfile"], cwd=cargo_toml_dir, check=True)
        except subprocess.CalledProcessError as e:
            print(f"Error: cargo failed: {e}", file=sys.stderr)
            sys.exit(1)
        except FileNotFoundError:
            print(f"Error: cargo binary '{cargo_cmd}' not found.", file=sys.stderr)
            sys.exit(1)

        try:
            locate_output = subprocess.check_output(
                [cargo_cmd, "locate-project", "--workspace", "--message-format", "plain"],
                cwd=cargo_toml_dir,
                text=True,
            ).strip()
            workspace_toml = Path(locate_output)
            generated_lock = workspace_toml.parent / "Cargo.lock"
        except subprocess.CalledProcessError as e:
            print(f"Warning: 'cargo locate-project' failed: {e}. Falling back to cargo_toml_dir.", file=sys.stderr)
            generated_lock = cargo_toml_dir / "Cargo.lock"

        if not generated_lock.exists():
            print(f"Warning: Cargo.lock not found at {generated_lock}. Searching...", file=sys.stderr)
            locks = list(sdist_root.glob("**/Cargo.lock"))
            if not locks:
                print("Error: Cargo.lock was not generated.", file=sys.stderr)
                sys.exit(1)
            generated_lock = locks[0]
            if len(locks) > 1:
                print(f"Warning: Found multiple Cargo.lock files, using {generated_lock}", file=sys.stderr)

        print(f"Writing Cargo.lock to {output_path}...")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(generated_lock, output_path)
        print("Done.")


if __name__ == "__main__":
    main()
