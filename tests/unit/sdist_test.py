import io
import os
import shutil
import stat
import tarfile
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import Mock
from unittest.mock import patch

from pycross.private.build.tools.utils import sdist
from pycross.private.build.tools.utils.sdist import extract_sdist


def _write_sdist(path: Path, mode: str) -> None:
    data = b"new"
    with tarfile.open(path, mode) as tf:
        info = tarfile.TarInfo("pkg-1.0/new.txt")
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))


def _mock_windows_os():
    def lstat(path):
        info = os.lstat(path)
        attributes = 0
        if not info.st_mode & stat.S_IWRITE:
            attributes |= stat.FILE_ATTRIBUTE_READONLY
        if stat.S_ISLNK(info.st_mode):
            attributes |= stat.FILE_ATTRIBUTE_REPARSE_POINT
        return SimpleNamespace(
            st_mode=info.st_mode,
            st_file_attributes=getattr(info, "st_file_attributes", attributes),
        )

    return SimpleNamespace(name="nt", lstat=lstat, walk=os.walk, path=os.path, chmod=Mock(wraps=os.chmod))


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
        self.assertFalse((self.ctx.temp_dir / "env").exists())
        self.assertFalse((self.ctx.temp_dir / "extracted").exists())

    def test_aborts_extraction_when_stale_source_cannot_be_removed(self):
        stale_file = self.ctx.sdist_root_dir / "locked.txt"
        stale_file.parent.mkdir()
        stale_file.write_text("stale")
        _write_sdist(self.ctx.sdist_path, "w:gz")
        unlink = os.unlink

        def unlink_with_locked_file(path, *args, **kwargs):
            if Path(path).name == stale_file.name:
                raise PermissionError("file is in use")
            return unlink(path, *args, **kwargs)

        with patch.object(os, "unlink", side_effect=unlink_with_locked_file):
            with self.assertRaises(PermissionError):
                extract_sdist(self.ctx)

        self.assertEqual(list(self.ctx.sdist_root_dir.iterdir()), [stale_file])
        self.assertFalse(self.ctx.temp_dir.exists())

    def test_tar_formats(self):
        for name, mode in [("pkg-1.0.tgz", "w:gz"), ("pkg-1.0.tar.bz2", "w:bz2"), ("pkg-1.0.tar", "w")]:
            with self.subTest(name=name):
                self.ctx.sdist_path = self.tmp / name
                _write_sdist(self.ctx.sdist_path, mode)
                extract_sdist(self.ctx)
                self.assertEqual((self.ctx.sdist_root_dir / "new.txt").read_text(), "new")

    def test_windows_uses_short_stage_and_cleans_stale_readonly_trees(self):
        self.ctx.temp_dir = self.tmp / ("long-build-output-" * 8) / "_tmp"
        self.ctx.sdist_root_dir = self.tmp / "bazel-out" / "_pcr" / "0123456789abcdef"
        stage_dir = self.ctx.sdist_root_dir.with_name(self.ctx.sdist_root_dir.name + "_extract")
        stale_trees = [self.ctx.temp_dir, self.ctx.sdist_root_dir, stage_dir]
        for stale_tree in stale_trees:
            stale_file = stale_tree / "stale.txt"
            stale_file.parent.mkdir(parents=True)
            stale_file.write_text("stale")
            stale_file.chmod(stat.S_IREAD)
        _write_sdist(self.ctx.sdist_path, "w:gz")

        platform_os = _mock_windows_os()
        original_move = shutil.move
        with (
            patch.object(sdist, "os", platform_os),
            patch.object(
                sdist.shutil,
                "move",
                side_effect=lambda source, destination: original_move(source, destination),
            ) as move,
        ):
            extract_sdist(self.ctx)

        self.assertEqual(Path(move.call_args.args[0]).parent, stage_dir)
        self.assertTrue(str(stage_dir).startswith(str(self.ctx.sdist_root_dir.parent)))
        self.assertFalse(self.ctx.temp_dir.exists())
        self.assertFalse(stage_dir.exists())
        self.assertEqual((self.ctx.sdist_root_dir / "new.txt").read_text(), "new")
        self.assertGreaterEqual(platform_os.chmod.call_count, len(stale_trees))

    def test_rejects_stage_left_by_failed_cleanup(self):
        stage_dir = self.tmp / "sdist_extract"
        stage_dir.mkdir()
        _write_sdist(self.ctx.sdist_path, "w:gz")

        with patch.object(sdist, "os", _mock_windows_os()), patch.object(sdist, "_remove_scratch_dir"):
            with self.assertRaises(FileExistsError):
                extract_sdist(self.ctx)

        self.assertEqual(list(stage_dir.iterdir()), [])

    @unittest.skipIf(os.name == "nt", "creating Windows symlinks requires extra privileges")
    def test_rejects_stage_symlink_before_extracting(self):
        outside = self.tmp / "outside"
        outside.mkdir()
        stage_dir = self.tmp / "sdist_extract"
        stage_dir.symlink_to(outside, target_is_directory=True)
        _write_sdist(self.ctx.sdist_path, "w:gz")

        with patch.object(sdist, "os", _mock_windows_os()):
            with self.assertRaises(OSError):
                extract_sdist(self.ctx)

        self.assertTrue(stage_dir.is_symlink())
        self.assertEqual(list(outside.iterdir()), [])

    @unittest.skipUnless(os.name == "nt", "requires Windows read-only file semantics")
    def test_removes_readonly_file_from_stale_environment(self):
        stale_file = self.ctx.temp_dir / "env" / "Scripts" / "activate"
        stale_file.parent.mkdir(parents=True)
        stale_file.write_text("stale activation script")
        stale_file.chmod(stat.S_IREAD)
        _write_sdist(self.ctx.sdist_path, "w:gz")

        try:
            extract_sdist(self.ctx)
            self.assertFalse(self.ctx.temp_dir.exists())
            self.assertEqual((self.ctx.sdist_root_dir / "new.txt").read_text(), "new")
        finally:
            if stale_file.exists():
                stale_file.chmod(stat.S_IREAD | stat.S_IWRITE)


class ReadonlyCleanupTest(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def _windows_os(self):
        # Simulate Windows file attributes so this test also runs on other platforms.
        return _mock_windows_os()

    def test_prepares_nested_readonly_files_for_deletion(self):
        scratch = self.root / "scratch"
        nested = scratch / "env" / "Scripts"
        nested.mkdir(parents=True)
        readonly = nested / "activate"
        readonly.write_text("activation script")
        readonly.chmod(stat.S_IREAD)
        writable = scratch / "writable.txt"
        writable.write_text("already writable")

        platform_os = self._windows_os()
        with patch.object(sdist, "os", platform_os):
            sdist._clear_readonly_files(scratch)

        self.assertTrue(readonly.stat().st_mode & stat.S_IWRITE)
        self.assertEqual(readonly.read_text(), "activation script")
        self.assertEqual(writable.read_text(), "already writable")
        self.assertEqual(platform_os.chmod.call_count, 1)
        shutil.rmtree(scratch)
        self.assertFalse(scratch.exists())

    def test_skips_reparse_points(self):
        for mode in [stat.S_IFLNK, stat.S_IFDIR, stat.S_IFREG]:
            with self.subTest(mode=mode):
                platform_os = SimpleNamespace(
                    lstat=Mock(
                        return_value=SimpleNamespace(
                            st_mode=mode,
                            st_file_attributes=stat.FILE_ATTRIBUTE_REPARSE_POINT | stat.FILE_ATTRIBUTE_READONLY,
                        )
                    ),
                    walk=Mock(),
                    chmod=Mock(),
                )
                with patch.object(sdist, "os", platform_os):
                    sdist._clear_readonly_files("link")
                platform_os.walk.assert_not_called()
                platform_os.chmod.assert_not_called()

    def test_prunes_reparse_entries_from_traversal(self):
        junction = self.root / "junction"
        junction.mkdir()
        target = junction / "target.txt"
        target.write_text("outside scratch tree")
        file_link = self.root / "file_link"
        file_link.write_text("linked file")
        target.chmod(stat.S_IREAD)
        file_link.chmod(stat.S_IREAD)

        platform_os = self._windows_os()
        original_lstat = platform_os.lstat

        def lstat(path):
            info = original_lstat(path)
            if Path(path) in [junction, file_link]:
                info.st_file_attributes |= stat.FILE_ATTRIBUTE_REPARSE_POINT
            return info

        platform_os.lstat = lstat
        try:
            with patch.object(sdist, "os", platform_os):
                sdist._clear_readonly_files(self.root)
            platform_os.chmod.assert_not_called()
        finally:
            target.chmod(stat.S_IREAD | stat.S_IWRITE)
            file_link.chmod(stat.S_IREAD | stat.S_IWRITE)


if __name__ == "__main__":
    unittest.main()
