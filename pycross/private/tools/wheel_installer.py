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
import subprocess
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
from installer.records import RecordEntry
from installer.sources import WheelContentElement
from installer.sources import WheelFile
from installer.utils import Scheme
from installer.utils import parse_wheel_filename
from pycross.private.tools.args import FlagFileArgumentParser

_COMPILE_SCRIPT = """\
import importlib.util
import os
import py_compile
import sys
from pathlib import Path

lib_dir = Path(sys.argv[1])
mode_name = sys.argv[2]
opt_level = int(sys.argv[3])
opt_arg = "" if opt_level == 0 else opt_level
mode = (
    py_compile.PycInvalidationMode.UNCHECKED_HASH
    if mode_name == "unchecked_hash"
    else py_compile.PycInvalidationMode.CHECKED_HASH
)

if lib_dir.is_dir():
    for root, dirs, files in os.walk(lib_dir):
        dirs[:] = sorted(d for d in dirs if d != "__pycache__")
        for fn in sorted(files):
            if not fn.endswith(".py"):
                continue
            src = Path(root) / fn
            rel = src.relative_to(lib_dir).as_posix()
            cfile = importlib.util.cache_from_source(str(src), optimization=opt_arg)
            try:
                py_compile.compile(
                    str(src),
                    cfile=cfile,
                    dfile=rel,
                    doraise=True,
                    optimize=opt_level,
                    invalidation_mode=mode,
                )
            except (SyntaxError, py_compile.PyCompileError) as exc:
                sys.stderr.write(f"Skipping bytecode compilation for {rel}: {exc}\\n")
"""


def compile_bytecode(
    lib_dir: Path,
    compile_python: str,
    invalidation_mode: str,
    optimize: int = 0,
) -> None:
    env = dict(os.environ)
    env["PYTHONHASHSEED"] = "0"
    env["PYTHONNOUSERSITE"] = "1"
    env["PYTHONSAFEPATH"] = "1"
    subprocess.run(
        [
            compile_python,
            "-S",
            "-s",
            "-B",
            "-c",
            _COMPILE_SCRIPT,
            str(lib_dir),
            invalidation_mode,
            str(optimize),
        ],
        env=env,
        check=True,
    )


class NormalizedDistInfoDestination(SchemeDictionaryDestination):
    """SchemeDictionaryDestination that remaps the wheel's .dist-info directory name."""

    def __init__(
        self,
        *args: Any,
        src_dist_info_dir: str,
        dst_dist_info_dir: str,
        **kwargs: Any,
    ) -> None:
        super().__init__(*args, **kwargs)
        self._src_dist_info_dir = src_dist_info_dir
        self._dst_dist_info_dir = dst_dist_info_dir

    def _remap_dist_info_path(self, path: str) -> str:
        if path == self._src_dist_info_dir:
            return self._dst_dist_info_dir
        prefix = self._src_dist_info_dir + "/"
        if path.startswith(prefix):
            return self._dst_dist_info_dir + "/" + path[len(prefix) :]
        return path

    def write_file(
        self,
        scheme: Scheme,
        path: Union[str, os.PathLike[str]],
        stream: Any,
        is_executable: bool,
    ) -> RecordEntry:
        remapped = self._remap_dist_info_path(os.fspath(path))
        return super().write_file(scheme, remapped, stream, is_executable)

    def finalize_installation(
        self,
        scheme: Scheme,
        record_file_path: Union[str, os.PathLike[str]],
        records: Any,
    ) -> None:
        remapped_record_file_path = self._remap_dist_info_path(os.fspath(record_file_path))
        remapped_records = [
            (
                scheme_,
                RecordEntry(
                    self._remap_dist_info_path(record.path),
                    record.hash_,
                    record.size,
                ),
            )
            for scheme_, record in records
        ]
        super().finalize_installation(scheme, remapped_record_file_path, remapped_records)


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

    # A wheel filename may carry a local version segment (e.g. a CUDA
    # build `3.0.0+cu130torch2110`) that the locked version (`3.0.0`) omits.
    # Compare only the public version (everything before `+`) so such wheels
    # are accepted while genuine version differences are still rejected.
    if expected_version and actual_version.split("+", 1)[0] != expected_version.split("+", 1)[0]:
        raise SystemExit(
            f"error: wheel version mismatch for {wheel_path.name}: "
            f"expected version '{expected_version}' "
            f"but wheel filename has '{actual_version}'"
        )


def main(args: Any) -> None:
    dest_dir = args.directory
    lib_dir = dest_dir / "site-packages"
    scheme_dict = {
        "platlib": str(lib_dir),
        "purelib": str(lib_dir),
        "headers": str(dest_dir / "include"),
        "scripts": str(dest_dir / "bin"),
        "data": str(dest_dir / "data"),
    }

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
            dist_info_dir = getattr(args, "dist_info_dir", None)
            if dist_info_dir and dist_info_dir != source.dist_info_dir:
                destination: SchemeDictionaryDestination = NormalizedDistInfoDestination(
                    scheme_dict=scheme_dict,
                    interpreter="python",  # Generic; it's not feasible to run these scripts directly.
                    script_kind="posix",
                    bytecode_optimization_levels=[],  # Setting to empty list to disable generation of .pyc files.
                    src_dist_info_dir=source.dist_info_dir,
                    dst_dist_info_dir=dist_info_dir,
                )
            else:
                destination = SchemeDictionaryDestination(
                    scheme_dict=scheme_dict,
                    interpreter="python",  # Generic; it's not feasible to run these scripts directly.
                    script_kind="posix",
                    bytecode_optimization_levels=[],  # Setting to empty list to disable generation of .pyc files.
                )
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

    compile_python = getattr(args, "compile_python", None)
    if compile_python:
        invalidation_mode = getattr(args, "compile_invalidation_mode", None) or "checked_hash"
        compile_optimize = getattr(args, "compile_optimize", None) or 0
        compile_bytecode(lib_dir, compile_python, invalidation_mode, compile_optimize)

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

    parser.add_argument(
        "--dist-info-dir",
        type=str,
        required=False,
        default=None,
        help="Normalized .dist-info directory name to write under site-packages.",
    )

    parser.add_argument(
        "--compile-python",
        type=str,
        required=False,
        default=None,
        help="Python interpreter executable to use for .pyc precompilation.",
    )

    parser.add_argument(
        "--compile-invalidation-mode",
        type=str,
        choices=["checked_hash", "unchecked_hash"],
        required=False,
        default=None,
        help="PycInvalidationMode for .pyc precompilation.",
    )

    parser.add_argument(
        "--compile-optimize",
        type=int,
        required=False,
        default=0,
        help="Optimization level for .pyc precompilation.",
    )

    return parser.parse_args()


# Alias for testing
_parse_args = parse_flags


if __name__ == "__main__":
    logging.getLogger("patch_ng").setLevel(logging.WARNING)
    main(parse_flags())
