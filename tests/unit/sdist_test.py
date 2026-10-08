import io
import tarfile
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace

from pycross.private.build.tools.utils.sdist import extract_sdist


def _write_sdist(path: Path, mode: str) -> None:
    data = b"new"
    with tarfile.open(path, mode) as tf:
        info = tarfile.TarInfo("pkg-1.0/new.txt")
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))


class ExtractSdistTest(unittest.TestCase):
    def setUp(self):
        self._tmp = TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.ctx = SimpleNamespace(
            temp_dir=self.tmp / "_tmp",
            sdist_root_dir=self.tmp / "sdist",
            sdist_path=self.tmp / "pkg-1.0.tar.gz",
        )

    def tearDown(self):
        self._tmp.cleanup()

    def test_replaces_stale_dirs(self):
        # Simulate leftovers from an earlier non-sandboxed run.
        (self.ctx.sdist_root_dir / "build").mkdir(parents=True)
        (self.ctx.sdist_root_dir / "old.txt").write_text("old")
        (self.ctx.temp_dir / "extracted" / "junk").mkdir(parents=True)
        (self.ctx.temp_dir / "env").mkdir()
        _write_sdist(self.ctx.sdist_path, "w:gz")

        extract_sdist(self.ctx)

        self.assertEqual(sorted(p.name for p in self.ctx.sdist_root_dir.iterdir()), ["new.txt"])
        self.assertEqual(list(self.ctx.temp_dir.iterdir()), [])

    def test_tar_formats(self):
        for name, mode in [("pkg-1.0.tgz", "w:gz"), ("pkg-1.0.tar.bz2", "w:bz2"), ("pkg-1.0.tar", "w")]:
            with self.subTest(name=name):
                self.ctx.sdist_path = self.tmp / name
                _write_sdist(self.ctx.sdist_path, mode)
                extract_sdist(self.ctx)
                self.assertEqual((self.ctx.sdist_root_dir / "new.txt").read_text(), "new")


if __name__ == "__main__":
    unittest.main()
