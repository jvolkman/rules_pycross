"""Tests for git_archive.py."""

import gzip
import os
import shutil
import stat
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

from pycross.private.tools import git_archive

_MTIME = 1700000000


def _make_tree(root: Path, file_mtime: int) -> None:
    (root / "pkg" / "vendor").mkdir(parents=True)
    (root / ".git" / "objects").mkdir(parents=True)
    (root / ".git" / "HEAD").write_text("ref: refs/heads/main\n")
    (root / "pyproject.toml").write_text("[project]\nname = 'pkg'\n")
    (root / "pkg" / "__init__.py").write_text("")
    (root / "pkg" / "run.sh").write_text("#!/bin/sh\n")
    (root / "pkg" / "run.sh").chmod(0o775)
    # A checked-out submodule: its contents plus a `.git` file.
    (root / "pkg" / "vendor" / ".git").write_text("gitdir: ../../.git/modules/vendor\n")
    (root / "pkg" / "vendor" / "data.py").write_text("DATA = 1\n")
    (root / "link.py").symlink_to("pkg/__init__.py")
    for path in root.rglob("*"):
        os.utime(path, (file_mtime, file_mtime), follow_symlinks=False)


class GitArchiveTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _archive(self, name: str, file_mtime: int, umask: int) -> Path:
        old = os.umask(umask)
        try:
            src = self.tmp / name
            src.mkdir()
            _make_tree(src, file_mtime)
        finally:
            os.umask(old)
        out = self.tmp / (name + ".tar.gz")
        git_archive.main(["--source", str(src), "--output", str(out), "--mtime", str(_MTIME)])
        return out

    def test_bytes_independent_of_checkout_metadata(self) -> None:
        first = self._archive("a", 1111111111, 0o022)
        second = self._archive("b", 1222222222, 0o002)
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_entries(self) -> None:
        out = self._archive("a", 1111111111, 0o022)
        with tarfile.open(out) as tar:
            members = tar.getmembers()
        names = [m.name for m in members]
        self.assertEqual(
            names,
            [
                "repo",
                "repo/link.py",
                "repo/pkg",
                "repo/pkg/__init__.py",
                "repo/pkg/run.sh",
                "repo/pkg/vendor",
                "repo/pkg/vendor/data.py",
                "repo/pyproject.toml",
            ],
        )
        by_name = {m.name: m for m in members}
        for m in members:
            self.assertEqual((m.mtime, m.uid, m.gid, m.uname, m.gname), (_MTIME, 0, 0, "", ""), m.name)
        self.assertTrue(by_name["repo/pkg"].isdir())
        self.assertEqual(by_name["repo/pkg"].mode, 0o755)
        self.assertEqual(by_name["repo/pkg/run.sh"].mode, 0o755)
        self.assertEqual(by_name["repo/pyproject.toml"].mode, 0o644)
        self.assertTrue(by_name["repo/link.py"].issym())
        self.assertEqual(by_name["repo/link.py"].linkname, "pkg/__init__.py")

    def test_gzip_header(self) -> None:
        data = self._archive("a", 1111111111, 0o022).read_bytes()
        # ID1 ID2 CM FLG MTIME(4): no FNAME flag and a zero timestamp.
        self.assertEqual(data[:3], b"\x1f\x8b\x08")
        self.assertEqual(data[3] & 0x08, 0)
        self.assertEqual(data[4:8], b"\x00\x00\x00\x00")
        self.assertTrue(gzip.decompress(data))

    def test_skips_special_files(self) -> None:
        src = self.tmp / "fifo"
        src.mkdir()
        (src / "a.txt").write_text("a")
        os.mkfifo(src / "pipe")
        self.assertTrue(stat.S_ISFIFO((src / "pipe").lstat().st_mode))
        out = self.tmp / "fifo.tar.gz"
        git_archive.create_archive(src, out, "repo", _MTIME)
        with tarfile.open(out) as tar:
            self.assertEqual(tar.getnames(), ["repo", "repo/a.txt"])

    @unittest.skipUnless(shutil.which("git"), "git not available")
    def test_preserves_git_index_executable_mode(self) -> None:
        """Tracked 100755 files stay executable in the archive even when working-tree mode is 0o644."""
        src = self.tmp / "gitrepo"
        src.mkdir()
        subprocess.run(["git", "init", "-q", str(src)], check=True)
        (src / "run.sh").write_text("#!/bin/sh\necho hi\n")
        (src / "plain.txt").write_text("hello\n")
        subprocess.run(["git", "-C", str(src), "add", "run.sh", "plain.txt"], check=True)
        subprocess.run(["git", "-C", str(src), "update-index", "--chmod=+x", "run.sh"], check=True)
        # Simulate Windows NTFS lacking POSIX execute bits on the checked-out file.
        (src / "run.sh").chmod(0o644)

        out = self.tmp / "gitrepo.tar.gz"
        git_archive.create_archive(src, out, "repo", _MTIME)
        with tarfile.open(out) as tar:
            by_name = {m.name: m for m in tar.getmembers()}
        self.assertEqual(by_name["repo/run.sh"].mode, 0o755)
        self.assertEqual(by_name["repo/plain.txt"].mode, 0o644)


if __name__ == "__main__":
    unittest.main()
