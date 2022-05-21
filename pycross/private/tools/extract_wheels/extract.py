"""Utility functions to manipulate Bazel files"""
import argparse
import os.path
import shutil
import tempfile
from pathlib import Path
from typing import Optional
from typing import Union

from pycross.private.tools.extract_wheels import (
    namespace_pkgs,
    purelib,
    wheel,
)


def setup_namespace_pkg_compatibility(wheel_dir: Union[str, Path]) -> None:
    """Converts native namespace packages to pkgutil-style packages

    Namespace packages can be created in one of three ways. They are detailed here:
    https://packaging.python.org/guides/packaging-namespace-packages/#creating-a-namespace-package

    'pkgutil-style namespace packages' (2) and 'pkg_resources-style namespace packages' (3) works in Bazel, but
    'native namespace packages' (1) do not.

    We ensure compatibility with Bazel of method 1 by converting them into method 2.

    Args:
        wheel_dir: the directory of the wheel to convert
    """

    namespace_pkg_dirs = namespace_pkgs.implicit_namespace_packages(
        wheel_dir,
        ignored_dirnames=["%s/bin" % wheel_dir],
    )

    for ns_pkg_dir in namespace_pkg_dirs:
        namespace_pkgs.add_pkgutil_style_namespace_pkg_init(ns_pkg_dir)


def extract_wheel(
    wheel_file: str,
    wheel_name_file: Optional[str],
    enable_implicit_namespace_pkgs: bool,
    directory: Optional[Path] = None,
) -> None:
    """Extracts wheel into given directory.

    Args:
        wheel_file: the filepath of the .whl
        wheel_name_file: the optional file containing the wheel's canonical filename.
        enable_implicit_namespace_pkgs: if true, disables conversion of implicit namespace packages and will unzip as-is
        directory: The directory to extract into.

    Returns:
        The Bazel label for the extracted wheel, in the form '//path/to/wheel'.
    """
    link_dir = tempfile.mkdtemp()
    if wheel_name_file:
        with open(wheel_name_file, "r") as f:
            wheel_name = f.read().strip()
    else:
        wheel_name = os.path.basename(wheel_file)

    link_path = os.path.join(link_dir, wheel_name)
    os.symlink(os.path.join(os.getcwd(), wheel_file), link_path)

    try:
        whl = wheel.Wheel(link_path)
        if directory is None:
            directory = Path(".")

        whl.unzip(directory)

        # Note: Order of operations matters here
        purelib.spread_purelib_into_root(directory)

        if not enable_implicit_namespace_pkgs:
            setup_namespace_pkg_compatibility(directory)

    finally:
        shutil.rmtree(link_dir, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description="Extract a Python wheel.")

    parser.add_argument(
        "--wheel",
        type=str,
        required=True,
        help="The wheel file path.",
    )

    parser.add_argument(
        "--wheel-name-file",
        type=str,
        required=False,
        help="A file containing the canonical name of the wheel.",
    )

    parser.add_argument(
        "--enable-implicit-namespace-pkgs",
        action="store_true",
        help="If true, disables conversion of implicit namespace packages and will unzip as-is.",
    )

    parser.add_argument(
        "--directory",
        type=str,
        required=False,
        help="The output path.",
    )

    args = parser.parse_args()
    extract_wheel(args.wheel, args.wheel_name_file, args.enable_implicit_namespace_pkgs, args.directory)


if __name__ == "__main__":
    main()
