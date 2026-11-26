"""Stdlib-only file operations for wheel directories and extracted wheel artifacts.

Subcommands:
    wrap-wheel <src> <dest_dir>
    unwrap-wheel <src_dir> <dst_file>
    extract-lib <site_packages_tree> <path_in_site_packages> <attr_name> <out_file>
    extract-bin <wheel_dir> <binary_name> <out_file>
"""

import argparse
import glob
import os
import shutil
import sys


def _remove_if_exists(path: str) -> None:
    """Remove an existing output path, clearing read-only bits for Windows safety."""
    if not os.path.lexists(path):
        return
    if not os.path.islink(path):
        try:
            os.chmod(path, 0o644)
        except OSError:
            pass
    os.unlink(path)


def _find_single_wheel(src_dir: str) -> str:
    """Return the path to the single .whl file inside src_dir, or exit with an error."""
    wheels = sorted(glob.glob(os.path.join(src_dir, "*.whl")))
    if not wheels:
        sys.exit(f"error: No .whl files found in {src_dir}")
    if len(wheels) > 1:
        sys.exit(f"error: Multiple .whl files found in {src_dir}: {wheels}")
    return wheels[0]


def wrap_wheel(src: str, dest_dir: str) -> None:
    """Copy a .whl file into a Bazel TreeArtifact directory by basename."""
    os.makedirs(dest_dir, exist_ok=True)
    dst = os.path.join(dest_dir, os.path.basename(src))
    _remove_if_exists(dst)
    shutil.copy2(src, dst)


def unwrap_wheel(src_dir: str, dst_file: str) -> None:
    """Copy the single .whl file out of a wheel directory to a stable destination.

    Always copies rather than symlinking so Bazel path mapping does not bake
    configuration-stripped paths into a relative symlink target.
    """
    src_file = _find_single_wheel(src_dir)
    dst_dir = os.path.dirname(dst_file)
    if dst_dir:
        os.makedirs(dst_dir, exist_ok=True)
    _remove_if_exists(dst_file)
    shutil.copy2(src_file, dst_file)


def extract_lib(tree: str, rel_path: str, attr_name: str, out_file: str) -> None:
    """Copy a library out of an installed wheel's site-packages so it can be linked."""
    src = os.path.join(tree, "site-packages", rel_path)
    if not os.path.isfile(src):
        sys.exit(f"error: {attr_name} '{rel_path}' is not a file in the wheel's site-packages")
    dst_dir = os.path.dirname(out_file)
    if dst_dir:
        os.makedirs(dst_dir, exist_ok=True)
    _remove_if_exists(out_file)
    shutil.copyfile(src, out_file)


def extract_bin(wheel_dir: str, binary_name: str, out_file: str) -> None:
    """Extract an executable (native binary or console script) from a wheel's bin/ directory."""
    src = os.path.join(wheel_dir, "bin", binary_name)
    if not os.path.isfile(src) and os.path.isfile(src + ".exe"):
        src = src + ".exe"
    if not os.path.isfile(src):
        sys.exit(f"error: executable '{binary_name}' not found in {os.path.join(wheel_dir, 'bin')}")

    dst_dir = os.path.dirname(out_file)
    if dst_dir:
        os.makedirs(dst_dir, exist_ok=True)
    _remove_if_exists(out_file)

    # wheel_installer.py installs POSIX console scripts with the placeholder
    # shebang `#!python`. Rewrite it to `#!/usr/bin/env python3` so tools that
    # re-invoke themselves by sys.argv[0] (e.g. meson via ninja) remain directly
    # executable instead of failing with `python: bad interpreter`.
    with open(src, "rb") as src_f:
        header = src_f.read(11)
        for shebang in (b"#!python\n", b"#!python\r\n"):
            if header.startswith(shebang):
                remainder = header[len(shebang) :]
                with open(out_file, "wb") as dst_f:
                    dst_f.write(b"#!/usr/bin/env python3\n")
                    dst_f.write(remainder)
                    shutil.copyfileobj(src_f, dst_f)
                os.chmod(out_file, 0o755)
                return

    shutil.copyfile(src, out_file)
    os.chmod(out_file, 0o755)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Wheel file copy and extraction utilities.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_wrap = subparsers.add_parser("wrap-wheel", help="Copy a .whl file into a TreeArtifact directory.")
    p_wrap.add_argument("src")
    p_wrap.add_argument("dest_dir")

    p_unwrap = subparsers.add_parser("unwrap-wheel", help="Copy the single .whl out of a directory.")
    p_unwrap.add_argument("src_dir")
    p_unwrap.add_argument("dst_file")

    p_lib = subparsers.add_parser("extract-lib", help="Copy a library from site-packages.")
    p_lib.add_argument("site_packages_tree")
    p_lib.add_argument("path_in_site_packages")
    p_lib.add_argument("attr_name")
    p_lib.add_argument("out_file")

    p_bin = subparsers.add_parser("extract-bin", help="Extract an executable from a wheel's bin/ directory.")
    p_bin.add_argument("wheel_dir")
    p_bin.add_argument("binary_name")
    p_bin.add_argument("out_file")

    args = parser.parse_args(argv)
    if args.command == "wrap-wheel":
        wrap_wheel(args.src, args.dest_dir)
    elif args.command == "unwrap-wheel":
        unwrap_wheel(args.src_dir, args.dst_file)
    elif args.command == "extract-lib":
        extract_lib(args.site_packages_tree, args.path_in_site_packages, args.attr_name, args.out_file)
    elif args.command == "extract-bin":
        extract_bin(args.wheel_dir, args.binary_name, args.out_file)


if __name__ == "__main__":
    main()
