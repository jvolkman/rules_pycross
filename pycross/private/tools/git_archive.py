"""Create a reproducible .tar.gz of a git checkout.

The archive bytes depend only on the tree contents, file types, executable
bits and the given mtime: entries are sorted, owners are zeroed and gzip
records no name or timestamp. `.git` entries (the superproject's directory
and the files that submodules use to point at it) are skipped, so submodule
contents are included but repository metadata is not.
"""

import argparse
import gzip
import os
import stat
import tarfile
from pathlib import Path
from typing import List
from typing import Optional


def _walk(root: Path) -> List[str]:
    """Returns sorted root-relative POSIX paths, skipping `.git` entries."""
    paths = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        rel_dir = Path(os.path.relpath(dirpath, root))
        paths.extend((rel_dir / name).as_posix() for name in dirnames + filenames if name != ".git")
    return sorted(paths)


def _entry(name: str, mode: int, mtime: int, kind: bytes = tarfile.REGTYPE) -> tarfile.TarInfo:
    info = tarfile.TarInfo(name)
    info.type = kind
    info.mode = mode
    info.mtime = mtime
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    return info


def create_archive(source: Path, output: Path, prefix: str, mtime: int) -> None:
    """Writes `source`'s tree to `output` as a deterministic .tar.gz.

    Args:
      source: the directory to archive.
      output: the .tar.gz to write.
      prefix: the top-level directory name for every entry (e.g. "repo").
      mtime: the modification time recorded for every entry.
    """
    prefix = prefix.strip("/")
    with open(output, "wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as tar:
            tar.addfile(_entry(prefix + "/", 0o755, mtime, tarfile.DIRTYPE))
            for rel in _walk(source):
                path = source / rel
                name = prefix + "/" + rel
                st = path.lstat()
                if stat.S_ISLNK(st.st_mode):
                    info = _entry(name, 0o777, mtime, tarfile.SYMTYPE)
                    info.linkname = os.readlink(path)
                    tar.addfile(info)
                elif stat.S_ISDIR(st.st_mode):
                    tar.addfile(_entry(name + "/", 0o755, mtime, tarfile.DIRTYPE))
                elif stat.S_ISREG(st.st_mode):
                    info = _entry(name, 0o755 if st.st_mode & 0o111 else 0o644, mtime)
                    info.size = st.st_size
                    with open(path, "rb") as f:
                        tar.addfile(info, f)


def main(argv: Optional[List[str]] = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Directory to archive.")
    parser.add_argument("--output", type=Path, required=True, help="Output .tar.gz path.")
    parser.add_argument("--prefix", default="repo", help="Top-level directory in the archive.")
    parser.add_argument("--mtime", type=int, required=True, help="Timestamp recorded for every entry.")
    args = parser.parse_args(argv)
    create_archive(args.source, args.output, args.prefix, args.mtime)


if __name__ == "__main__":
    main()
