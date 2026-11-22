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
import shutil
import stat
import subprocess
import tarfile
from pathlib import Path
from typing import Dict
from typing import List
from typing import Optional
from typing import Tuple

_GIT_ENV_VARS_TO_STRIP = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")


def _git_modes(root: Path, git_exe: Optional[str]) -> Dict[str, int]:
    """Read tracked regular-file modes (`100755` / `100644`) from the git index.

    On Windows NTFS, working-tree files lack POSIX execute bits, so reading
    git's index preserves `100755` modes consistently across operating systems.
    Recurses into checked-out submodules (`160000`). Returns `{}` when `root`
    is not a git checkout or `git` is unavailable.
    """
    if not git_exe or not (root / ".git").exists():
        return {}
    resolved_git = shutil.which(git_exe)
    if not resolved_git:
        return {}

    clean_env = {k: v for k, v in os.environ.items() if k not in _GIT_ENV_VARS_TO_STRIP}
    modes: Dict[str, int] = {}
    queue: List[Tuple[Path, str]] = [(root, "")]
    while queue:
        repo_dir, rel_prefix = queue.pop()
        if not (repo_dir / ".git").exists():
            continue
        try:
            proc = subprocess.run(
                [resolved_git, "-C", str(repo_dir), "ls-files", "--stage", "-z"],
                capture_output=True,
                check=False,
                env=clean_env,
            )
        except OSError:
            return {}
        if proc.returncode != 0:
            continue
        for record in proc.stdout.split(b"\0"):
            if not record or b"\t" not in record:
                continue
            meta, raw_path = record.split(b"\t", 1)
            mode_str = meta.split(b" ", 1)[0].decode("ascii", errors="ignore")
            rel_path = raw_path.decode("utf-8", errors="surrogateescape")
            full_rel = f"{rel_prefix}/{rel_path}" if rel_prefix else rel_path
            if mode_str == "100755":
                modes[full_rel] = 0o755
            elif mode_str == "100644":
                modes[full_rel] = 0o644
            elif mode_str == "160000":
                queue.append((repo_dir / rel_path, full_rel))
    return modes


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


def create_archive(
    source: Path,
    output: Path,
    prefix: str,
    mtime: int,
    git_exe: Optional[str] = "git",
) -> None:
    """Writes `source`'s tree to `output` as a deterministic .tar.gz.

    Args:
      source: the directory to archive.
      output: the .tar.gz to write.
      prefix: the top-level directory name for every entry (e.g. "repo").
      mtime: the modification time recorded for every entry.
      git_exe: optional path/name of the git executable used to preserve
        `100755` file modes from the git index on platforms without POSIX
        execute bits.
    """
    prefix = prefix.strip("/")
    git_modes = _git_modes(source, git_exe)
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
                    mode = git_modes.get(rel, 0o755 if st.st_mode & 0o111 else 0o644)
                    info = _entry(name, mode, mtime)
                    info.size = st.st_size
                    with open(path, "rb") as f:
                        tar.addfile(info, f)


def main(argv: Optional[List[str]] = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Directory to archive.")
    parser.add_argument("--output", type=Path, required=True, help="Output .tar.gz path.")
    parser.add_argument("--prefix", default="repo", help="Top-level directory in the archive.")
    parser.add_argument("--mtime", type=int, required=True, help="Timestamp recorded for every entry.")
    parser.add_argument("--git", default="git", help="Git executable used to read tracked file modes.")
    args = parser.parse_args(argv)
    create_archive(args.source, args.output, args.prefix, args.mtime, git_exe=args.git)


if __name__ == "__main__":
    main()
