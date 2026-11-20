import os
import shutil
import stat
import tarfile
import zipfile

from pycross.private.build.tools.utils.context import BuildContext

# Keep in sync with the sdist formats accepted by inspect_package.py.
_TAR_SUFFIXES = (".tar.gz", ".tgz", ".tar.bz2", ".tar")


def _clear_readonly_files(path) -> None:
    """Clear read-only attributes on Windows files, skipping links and junctions."""
    # Skip links and junctions to leave their targets unchanged.
    if os.lstat(path).st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:
        return
    for root, dirs, files in os.walk(path, followlinks=False):
        # Update dirs in place so os.walk skips junction targets.
        dirs[:] = [
            name
            for name in dirs
            if not os.lstat(os.path.join(root, name)).st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT
        ]
        for name in files:
            file_path = os.path.join(root, name)
            info = os.lstat(file_path)
            if info.st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:
                continue
            if stat.S_ISREG(info.st_mode) and info.st_file_attributes & stat.FILE_ATTRIBUTE_READONLY:
                os.chmod(file_path, info.st_mode | stat.S_IWRITE)


def _get_extraction_dir(ctx: BuildContext):
    """Return the temporary directory used to extract the sdist.

    Use a short directory beside the source root on Windows to avoid long
    paths during extraction.
    """
    if os.name == "nt":
        return ctx.sdist_root_dir.with_name(ctx.sdist_root_dir.name + "_extract")
    return ctx.temp_dir / "extracted"


def _remove_scratch_dir(path) -> None:
    """Remove a scratch directory and its contents.

    On Windows, clear read-only attributes first so those files can be deleted.
    """
    if os.name == "nt" and path.exists():
        _clear_readonly_files(path)
    shutil.rmtree(path, ignore_errors=True)


def extract_sdist(ctx: BuildContext) -> None:
    """Extracts the source distribution into the build sandbox."""
    # Without sandboxing, files from earlier builds can remain in these
    # directories. Remove them before extracting the source again.
    extract_parent = _get_extraction_dir(ctx)
    for scratch_dir in (ctx.temp_dir, ctx.sdist_root_dir, extract_parent):
        _remove_scratch_dir(scratch_dir)

    # Require a fresh directory so extraction stays in the intended location.
    extract_parent.mkdir(parents=True)

    if ctx.sdist_path.name.endswith(_TAR_SUFFIXES):
        with tarfile.open(ctx.sdist_path, "r") as f:
            if hasattr(tarfile, "data_filter"):
                f.extraction_filter = tarfile.data_filter
            f.extractall(extract_parent)
    elif ctx.sdist_path.name.endswith(".zip"):
        with zipfile.ZipFile(ctx.sdist_path, "r") as f:
            f.extractall(extract_parent)
    else:
        raise ValueError(f"Unsupported sdist format: {ctx.sdist_path}")

    extracted_dirs = list(extract_parent.glob("*"))
    if len(extracted_dirs) != 1:
        raise ValueError(f"Expected exactly one directory in sdist archive, got: {extracted_dirs}")

    ctx.sdist_root_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(extracted_dirs[0]), str(ctx.sdist_root_dir))
    shutil.rmtree(extract_parent)
