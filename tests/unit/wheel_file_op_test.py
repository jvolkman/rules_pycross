"""Tests for wheel_file_op.py subcommands."""

import os
import stat
import tempfile
import unittest
from pathlib import Path

from pycross.private.tools import wheel_file_op


class WheelFileOpTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def test_wrap_wheel_copies_by_basename_and_overwrites_readonly(self):
        src = self.tmp / "foo-1.0-py3-none-any.whl"
        src.write_bytes(b"wheel-bytes")
        dest_dir = self.tmp / "out.whldir"
        dest_dir.mkdir()

        existing = dest_dir / src.name
        existing.write_bytes(b"stale")
        os.chmod(existing, 0o444)

        wheel_file_op.main(["wrap-wheel", str(src), str(dest_dir)])
        self.assertTrue(existing.is_file())
        self.assertFalse(existing.is_symlink())
        self.assertEqual(existing.read_bytes(), b"wheel-bytes")

        # Overwriting a stale symlink unlinks it without chmod-ing its read-only target.
        if os.name != "nt":
            target = self.tmp / "readonly_target"
            target.write_bytes(b"protected")
            os.chmod(target, 0o444)
            existing.unlink()
            existing.symlink_to(target)
            wheel_file_op.main(["wrap-wheel", str(src), str(dest_dir)])
            self.assertFalse(existing.is_symlink())
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o444)

    def test_unwrap_wheel_copies_single_wheel_and_validates_count(self):
        src_dir = self.tmp / "wheel.whldir"
        src_dir.mkdir()
        dst = self.tmp / "nested" / "stable.whl"

        # Empty directory fails.
        with self.assertRaises(SystemExit) as cm:
            wheel_file_op.main(["unwrap-wheel", str(src_dir), str(dst)])
        self.assertIn("No .whl files found", str(cm.exception))

        # Single wheel copies (never symlinks) and overwrites read-only output.
        whl = src_dir / "pkg-1.0-py3-none-any.whl"
        whl.write_bytes(b"zip-payload")
        dst.parent.mkdir(parents=True)
        dst.write_bytes(b"stale")
        os.chmod(dst, 0o444)

        wheel_file_op.main(["unwrap-wheel", str(src_dir), str(dst)])
        self.assertTrue(dst.is_file())
        self.assertFalse(dst.is_symlink())
        self.assertEqual(dst.read_bytes(), b"zip-payload")

        # Multiple wheels fail.
        (src_dir / "other-2.0-py3-none-any.whl").write_bytes(b"extra")
        with self.assertRaises(SystemExit) as cm:
            wheel_file_op.main(["unwrap-wheel", str(src_dir), str(dst)])
        self.assertIn("Multiple .whl files found", str(cm.exception))

    def test_extract_lib_copies_file_and_errors_when_missing(self):
        tree = self.tmp / "installed"
        lib_src = tree / "site-packages" / "pkg" / "lib" / "libfoo.so"
        lib_src.parent.mkdir(parents=True)
        lib_src.write_bytes(b"\x7fELFlib")

        out = self.tmp / "out" / "libfoo.so"
        out.parent.mkdir()
        out.write_bytes(b"stale")
        os.chmod(out, 0o444)

        wheel_file_op.main(["extract-lib", str(tree), "pkg/lib/libfoo.so", "shared_library", str(out)])
        self.assertEqual(out.read_bytes(), b"\x7fELFlib")

        with self.assertRaises(SystemExit) as cm:
            wheel_file_op.main(["extract-lib", str(tree), "pkg/lib/missing.so", "shared_library", str(out)])
        self.assertIn("shared_library 'pkg/lib/missing.so' is not a file", str(cm.exception))

    def test_extract_bin_rewrites_placeholder_shebang_and_exe_fallback(self):
        wheel_dir = self.tmp / "wheel"
        bin_dir = wheel_dir / "bin"
        bin_dir.mkdir(parents=True)

        # Console script with placeholder `#!python` shebang (LF and CRLF, including multi-chunk body).
        large_body = b"x = 1\n" * 20000
        (bin_dir / "meson").write_bytes(b"#!python\n" + large_body)
        (bin_dir / "cmake").write_bytes(b"#!python\r\nimport sys\r\n")
        # Native binary and .exe fallback should pass through unmodified.
        (bin_dir / "ninja").write_bytes(b"\x7fELF\x02\x01binary" + b"\x00" * 100000)
        (bin_dir / "win_tool.exe").write_bytes(b"MZbinary")

        out_dir = self.tmp / "out"
        out_dir.mkdir()

        for name, expected in [
            ("meson", b"#!/usr/bin/env python3\n" + large_body),
            ("cmake", b"#!/usr/bin/env python3\nimport sys\r\n"),
            ("ninja", b"\x7fELF\x02\x01binary" + b"\x00" * 100000),
            ("win_tool", b"MZbinary"),
        ]:
            out_file = out_dir / name
            out_file.write_bytes(b"stale")
            os.chmod(out_file, 0o444)
            wheel_file_op.main(["extract-bin", str(wheel_dir), name, str(out_file)])
            self.assertEqual(out_file.read_bytes(), expected, msg=name)
            if os.name != "nt":
                self.assertTrue(stat.S_IMODE(out_file.stat().st_mode) & stat.S_IXUSR, msg=name)

        with self.assertRaises(SystemExit) as cm:
            wheel_file_op.main(["extract-bin", str(wheel_dir), "missing_tool", str(out_dir / "missing")])
        self.assertIn("missing_tool", str(cm.exception))


if __name__ == "__main__":
    unittest.main()
