import shutil
import tarfile
import zipfile

from pycross.private.build.tools.utils.context import BuildContext


def extract_sdist(ctx: BuildContext) -> None:
    """Extracts the source distribution into the build sandbox."""
    extract_parent = ctx.temp_dir / "extracted"
    extract_parent.mkdir(parents=True, exist_ok=True)

    if ctx.sdist_path.name.endswith(".tar.gz"):
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

    ctx.sdist_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(extracted_dirs[0]), str(ctx.sdist_dir))
    shutil.rmtree(extract_parent)
