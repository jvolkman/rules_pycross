"""
A tool that uses pypa/installer to install wheel files to a specified directory.
The wheels may be pre-built or built from sdist tarballs using pypa/build (via wheel_builder.py).
"""

from __future__ import annotations

import fnmatch
import logging
import os
import re
import shutil
import tempfile
import zipfile
from contextlib import contextmanager
from pathlib import Path
from typing import Any
from typing import Iterator
from typing import List
from typing import Union

import patch_ng
from installer import install
from installer.destinations import SchemeDictionaryDestination
from installer.sources import WheelContentElement
from installer.sources import WheelFile
from installer.utils import parse_wheel_filename
from pycross.private.tools.args import FlagFileArgumentParser


class FilteredWheelFile(WheelFile):
    def __init__(self, f: zipfile.ZipFile, install_exclude_globs: List[str]) -> None:
        super().__init__(f)
        self._install_exclude_globs = install_exclude_globs

    @classmethod
    @contextmanager
    def open_filtered(
        cls, path: Union[os.PathLike, str], install_exclude_globs: List[str]
    ) -> Iterator[FilteredWheelFile]:
        with zipfile.ZipFile(path) as f:
            yield cls(f, install_exclude_globs)

    def get_contents(self) -> Iterator[WheelContentElement]:
        for record_elements, stream, is_executable in super().get_contents():
            if not self.should_install(stream.name):
                continue
            yield record_elements, stream, is_executable

    def should_install(self, filename: str) -> bool:
        for install_exclude_glob in self._install_exclude_globs:
            if fnmatch.fnmatch(filename, install_exclude_glob):
                return False
        return True


def apply_patches(lib_dir: Path, patches: List[str]) -> None:
    for patch in patches:
        patch_file = patch_ng.fromfile(patch)
        if not patch_file:
            raise SystemExit(f"error: failed to parse patch file: {patch}")
        if not patch_file.apply(root=lib_dir):
            raise SystemExit(f"error: failed to apply patch file: {patch}")


def _normalize_pep503(name: str) -> str:
    """Normalize a package name per PEP 503."""
    return re.sub(r"[-_.]+", "-", name).lower()


def _validate_wheel_identity(
    wheel_path: Path,
    expected_name: str | None,
    expected_version: str | None,
) -> None:
    """Validate that a wheel's filename matches the expected name and version.

    Per PEP 427 the wheel filename encodes {name}-{version}-{tags}.whl,
    so the filename is the canonical source of identity.
    """
    try:
        parsed = parse_wheel_filename(wheel_path.name)
    except Exception as e:
        raise SystemExit(f"error: failed to parse wheel filename {wheel_path.name}: {e}")

    actual_name = parsed.distribution
    actual_version = parsed.version

    if expected_name and _normalize_pep503(actual_name) != _normalize_pep503(expected_name):
        raise SystemExit(
            f"error: wheel identity mismatch for {wheel_path.name}: "
            f"expected package name '{expected_name}' "
            f"but wheel filename has '{actual_name}'"
        )

    if expected_version and actual_version != expected_version:
        raise SystemExit(
            f"error: wheel version mismatch for {wheel_path.name}: "
            f"expected version '{expected_version}' "
            f"but wheel filename has '{actual_version}'"
        )


def main(args: Any) -> None:
    dest_dir = args.directory
    lib_dir = dest_dir / "site-packages"
    destination = SchemeDictionaryDestination(
        scheme_dict={
            "platlib": str(lib_dir),
            "purelib": str(lib_dir),
            "headers": str(dest_dir / "include"),
            "scripts": str(dest_dir / "bin"),
            "data": str(dest_dir / "data"),
        },
        interpreter="python",  # Generic; it's not feasible to run these scripts directly.
        script_kind="posix",
        bytecode_optimization_levels=[],  # Setting to empty list to disable generation of .pyc files.
    )

    link_dir = Path(tempfile.mkdtemp())
    if args.wheel_dir:
        whl_files = list(Path(args.wheel_dir).glob("*.whl"))
        if len(whl_files) != 1:
            raise SystemExit(f"error: Expected 1 wheel in wheel directory, found {len(whl_files)}")
        wheel_path = whl_files[0]
        wheel_name = wheel_path.name
    else:
        wheel_path = Path(args.wheel)
        if args.wheel_name_file:
            with open(args.wheel_name_file, "r") as f:
                wheel_name = f.read().strip()
        else:
            wheel_name = wheel_path.name

    # Validate wheel identity before installation.
    if args.expected_name or args.expected_version:
        _validate_wheel_identity(wheel_path, args.expected_name, args.expected_version)

    link_path = link_dir / wheel_name
    os.symlink(wheel_path.absolute(), link_path)

    try:
        with FilteredWheelFile.open_filtered(link_path, args.install_exclude_globs) as source:
            install(
                source=source,
                destination=destination,
                # Additional metadata that is generated by the installation tool.
                additional_metadata={
                    "INSTALLER": b"https://github.com/jvolkman/rules_pycross",
                },
            )
    finally:
        shutil.rmtree(link_dir, ignore_errors=True)

    apply_patches(lib_dir, args.patches)

    # Extract entry_points.txt for rules_python compatibility.
    if args.entry_points_output:
        entry_points_output = Path(args.entry_points_output)
        entry_points_output.parent.mkdir(parents=True, exist_ok=True)
        found = False
        for dist_info_dir in lib_dir.glob("*.dist-info"):
            ep_file = dist_info_dir / "entry_points.txt"
            if ep_file.exists():
                shutil.copy2(ep_file, entry_points_output)
                found = True
                break
        if not found:
            entry_points_output.touch()


def parse_flags() -> Any:
    parser = FlagFileArgumentParser(description="Extract a Python wheel.")

    parser.add_argument(
        "--wheel",
        type=Path,
        required=False,
        help="The wheel file path.",
    )

    parser.add_argument(
        "--wheel-dir",
        type=Path,
        required=False,
        help="The wheel directory.",
    )

    parser.add_argument(
        "--wheel-name-file",
        type=Path,
        required=False,
        help="A file containing the canonical name of the wheel.",
    )

    parser.add_argument(
        "--install-exclude-glob",
        action="append",
        dest="install_exclude_globs",
        default=[],
        help="A glob for files to exclude during installation.",
    )

    parser.add_argument(
        "--patch",
        action="append",
        dest="patches",
        default=[],
        help="A list of patches to apply after installation.",
    )

    parser.add_argument(
        "--entry-points-output",
        type=Path,
        required=False,
        help="Path to write the entry_points.txt file for rules_python compatibility.",
    )

    parser.add_argument(
        "--directory",
        type=Path,
        help="The output path.",
    )

    parser.add_argument(
        "--expected-name",
        type=str,
        required=False,
        help="Expected package name; validated against wheel METADATA.",
    )

    parser.add_argument(
        "--expected-version",
        type=str,
        required=False,
        help="Expected package version; validated against wheel METADATA.",
    )

    return parser.parse_args()


# Alias for testing
_parse_args = parse_flags


if __name__ == "__main__":
    logging.getLogger("patch_ng").setLevel(logging.WARNING)
    main(parse_flags())
