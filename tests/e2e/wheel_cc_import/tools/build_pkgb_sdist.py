import io
import sys
import tarfile
from pathlib import Path


def _add_file(archive: tarfile.TarFile, source: Path, dest: Path) -> None:
    data = source.read_bytes()
    info = tarfile.TarInfo(str(dest))
    info.size = len(data)
    info.mode = 0o644
    archive.addfile(info, io.BytesIO(data))


def main() -> None:
    out_path = Path(sys.argv[1])
    pyproject = Path(sys.argv[2])
    setup = Path(sys.argv[3])
    pkg_init = Path(sys.argv[4])
    ext_c = Path(sys.argv[5])

    root = Path("pkgb-0.1")

    with tarfile.open(out_path, "w:gz") as archive:
        _add_file(archive, pyproject, root / "pyproject.toml")
        _add_file(archive, setup, root / "setup.py")
        _add_file(archive, pkg_init, root / "pkgb" / "__init__.py")
        _add_file(archive, ext_c, root / "pkgb" / "_ext.c")


if __name__ == "__main__":
    main()
