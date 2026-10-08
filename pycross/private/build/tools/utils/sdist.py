import shutil
import tarfile
import zipfile

from pycross.private.build.tools.utils.context import BuildContext

# Keep in sync with the sdist formats accepted by inspect_package.py.
_TAR_SUFFIXES = (".tar.gz", ".tgz", ".tar.bz2", ".tar")


def extract_sdist(ctx: BuildContext) -> None:
    """Extracts the source distribution into the build sandbox."""
    # The scratch and sdist dirs are not declared outputs, so non-sandboxed
    # strategies leave them behind from earlier runs. Start clean.
    shutil.rmtree(ctx.temp_dir, ignore_errors=True)
    shutil.rmtree(ctx.sdist_root_dir, ignore_errors=True)

    extract_parent = ctx.temp_dir / "extracted"
    extract_parent.mkdir(parents=True, exist_ok=True)

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
