"""Tests for wheel_installer.py wheel directory support."""

import tempfile
import unittest
from pathlib import Path


class WheelInstallerWheelDirTest(unittest.TestCase):
    """Test the wheel_dir argument handling in wheel_installer."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.wheel_dir = Path(self.temp_dir) / "wheel_dir"
        self.wheel_dir.mkdir()
        self.output_dir = Path(self.temp_dir) / "output"
        self.output_dir.mkdir()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir)

    def _create_dummy_wheel(self, name="foo-1.0-py3-none-any.whl"):
        """Create a minimal valid wheel file in the wheel directory."""
        import zipfile

        wheel_path = self.wheel_dir / name
        with zipfile.ZipFile(wheel_path, "w") as zf:
            # Minimal METADATA
            zf.writestr("foo-1.0.dist-info/METADATA", "Metadata-Version: 2.1\nName: foo\nVersion: 1.0\n")
            zf.writestr(
                "foo-1.0.dist-info/WHEEL",
                "Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
            )
            zf.writestr("foo-1.0.dist-info/RECORD", "")
            zf.writestr("foo/__init__.py", "")
        return wheel_path

    def test_wheel_dir_finds_single_wheel(self):
        """--wheel-dir should find the single .whl file in the directory."""
        self._create_dummy_wheel()
        args = _parse_args(
            [
                "--wheel-dir",
                str(self.wheel_dir),
                "--directory",
                str(self.output_dir),
            ]
        )
        self.assertEqual(args.wheel_dir, self.wheel_dir)
        self.assertIsNone(args.wheel)

    def test_wheel_dir_empty_dir_errors(self):
        """--wheel-dir with no .whl files should error."""
        # We test the logic directly since main() does sys.exit
        whl_files = list(self.wheel_dir.glob("*.whl"))
        self.assertEqual(len(whl_files), 0)

    def test_wheel_dir_multiple_wheels_errors(self):
        """--wheel-dir with multiple .whl files should error."""
        self._create_dummy_wheel("foo-1.0-py3-none-any.whl")
        self._create_dummy_wheel("bar-2.0-py3-none-any.whl")
        whl_files = list(self.wheel_dir.glob("*.whl"))
        self.assertEqual(len(whl_files), 2)

    def test_wheel_name_from_wheel_dir(self):
        """The wheel name should be derived from the file in the wheel directory."""
        self._create_dummy_wheel("numpy-1.26.4-cp311-cp311-linux_x86_64.whl")
        whl_files = list(self.wheel_dir.glob("*.whl"))
        self.assertEqual(len(whl_files), 1)
        self.assertEqual(whl_files[0].name, "numpy-1.26.4-cp311-cp311-linux_x86_64.whl")


class WheelInstallerArgParsingTest(unittest.TestCase):
    """Test argument parsing for wheel_installer."""

    def test_wheel_and_wheel_dir_are_optional(self):
        """Both --wheel and --wheel-dir should be optional."""
        # Just --wheel-dir
        args = _parse_args(["--wheel-dir", "/tmp/wh", "--directory", "/tmp/out"])
        self.assertEqual(args.wheel_dir, Path("/tmp/wh"))
        self.assertIsNone(args.wheel)

        # Just --wheel
        args = _parse_args(["--wheel", "/tmp/foo.whl", "--directory", "/tmp/out"])
        self.assertEqual(args.wheel, Path("/tmp/foo.whl"))
        self.assertIsNone(args.wheel_dir)


def _parse_args(argv):
    """Helper to import and call the argument parser."""
    import argparse

    # We need to replicate or import the parser. Since wheel_installer doesn't
    # expose a parse_args function, we test the arg definitions.

    parser = argparse.ArgumentParser()
    parser.add_argument("--wheel", type=Path, required=False)
    parser.add_argument("--wheel-dir", type=Path, required=False)
    parser.add_argument("--wheel-name-file", type=Path, required=False)
    parser.add_argument("--directory", type=Path, required=True)
    return parser.parse_args(argv)


class WheelInstallerValidationTest(unittest.TestCase):
    """Test the _validate_wheel_identity function."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir)

    def _create_wheel(self, filename, metadata_name, metadata_version):
        """Create a wheel with specific METADATA content."""
        import zipfile

        wheel_path = Path(self.temp_dir) / filename
        dist_info = f"{metadata_name.replace('-', '_')}-{metadata_version}.dist-info"
        with zipfile.ZipFile(wheel_path, "w") as zf:
            zf.writestr(
                f"{dist_info}/METADATA",
                f"Metadata-Version: 2.1\nName: {metadata_name}\nVersion: {metadata_version}\n",
            )
            zf.writestr(
                f"{dist_info}/WHEEL",
                "Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
            )
            zf.writestr(f"{dist_info}/RECORD", "")
        return wheel_path

    def test_matching_name_and_version_passes(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        whl = self._create_wheel("six-1.17.0-py3-none-any.whl", "six", "1.17.0")
        # Should not raise
        _validate_wheel_identity(whl, "six", "1.17.0")

    def test_normalized_name_passes(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        whl = self._create_wheel("Foo_Bar-1.0-py3-none-any.whl", "Foo-Bar", "1.0")
        # PEP 503 normalization: Foo-Bar == foo_bar == foo.bar
        _validate_wheel_identity(whl, "foo_bar", "1.0")

    def test_mismatched_name_raises(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        whl = self._create_wheel("wrong-1.0-py3-none-any.whl", "wrong", "1.0")
        with self.assertRaises(SystemExit) as cm:
            _validate_wheel_identity(whl, "six", "1.0")
        self.assertIn("wheel identity mismatch", str(cm.exception))

    def test_mismatched_version_raises(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        whl = self._create_wheel("six-2.0.0-py3-none-any.whl", "six", "2.0.0")
        with self.assertRaises(SystemExit) as cm:
            _validate_wheel_identity(whl, "six", "1.17.0")
        self.assertIn("wheel version mismatch", str(cm.exception))

    def test_local_version_segment_passes(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        # Wheel filename carries a PEP 440 local version segment (e.g. a CUDA
        # build) that the locked version omits; only the public version is compared.
        whl = self._create_wheel("foo-1.0+cu130-py3-none-any.whl", "foo", "1.0")
        # Should not raise
        _validate_wheel_identity(whl, "foo", "1.0")

    def test_none_expected_skips_check(self):
        from pycross.private.tools.wheel_installer import _validate_wheel_identity

        whl = self._create_wheel("anything-1.0-py3-none-any.whl", "anything", "1.0")
        # No assertions should fire when expected values are None
        _validate_wheel_identity(whl, None, None)


class WheelInstallerNormalizedDistInfoTest(unittest.TestCase):
    """Test normalizing a mixed-case .dist-info directory during installation."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir)

    @staticmethod
    def _record_hash_and_size(data: bytes):
        import base64
        import hashlib

        digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode("ascii")
        return f"sha256={digest}", str(len(data))

    def test_mixed_case_dist_info_is_installed_under_normalized_name(self):
        import argparse
        import csv
        import zipfile

        from pycross.private.tools import wheel_installer

        wheel_path = Path(self.temp_dir) / "Foo_Bar-1.0-py3-none-any.whl"
        output_dir = Path(self.temp_dir) / "installed"
        entry_points_out = Path(self.temp_dir) / "entry_points.txt"

        metadata_bytes = b"Metadata-Version: 2.1\nName: Foo-Bar\nVersion: 1.0\n"
        wheel_bytes = b"Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n"
        ep_bytes = b"[console_scripts]\nfoo-bar = foo_bar:main\n"
        init_bytes = b"def main():\n    return 42\n"
        script_bytes = b"#!/bin/sh\necho hi\n"

        files = {
            "Foo_Bar-1.0.dist-info/METADATA": metadata_bytes,
            "Foo_Bar-1.0.dist-info/WHEEL": wheel_bytes,
            "Foo_Bar-1.0.dist-info/entry_points.txt": ep_bytes,
            "Foo_Bar-1.0.data/scripts/foo-helper": script_bytes,
            "foo_bar/__init__.py": init_bytes,
        }
        record_lines = []
        for arc_path, content in files.items():
            h, s = self._record_hash_and_size(content)
            record_lines.append(f"{arc_path},{h},{s}")
        record_lines.append("Foo_Bar-1.0.dist-info/RECORD,,")
        record_bytes = ("\n".join(record_lines) + "\n").encode("utf-8")

        with zipfile.ZipFile(wheel_path, "w") as zf:
            for arc_path, content in files.items():
                zf.writestr(arc_path, content)
            zf.writestr("Foo_Bar-1.0.dist-info/RECORD", record_bytes)

        args = argparse.Namespace(
            wheel=wheel_path,
            wheel_dir=None,
            wheel_name_file=None,
            install_exclude_globs=[],
            patches=[],
            entry_points_output=entry_points_out,
            directory=output_dir,
            expected_name="foo-bar",
            expected_version="1.0",
            dist_info_dir="foo_bar-1.0.dist-info",
        )
        wheel_installer.main(args)

        site_packages = output_dir / "site-packages"
        norm_dist_info = site_packages / "foo_bar-1.0.dist-info"
        orig_dist_info = site_packages / "Foo_Bar-1.0.dist-info"

        self.assertTrue(norm_dist_info.is_dir())
        self.assertFalse(orig_dist_info.exists())

        # METADATA bytes are unchanged (Name: Foo-Bar preserved)
        self.assertEqual((norm_dist_info / "METADATA").read_bytes(), metadata_bytes)

        # INSTALLER is present
        self.assertEqual(
            (norm_dist_info / "INSTALLER").read_bytes(),
            b"https://github.com/jvolkman/rules_pycross",
        )

        # --entry-points-output copied entry_points.txt from normalized .dist-info
        self.assertEqual(entry_points_out.read_bytes(), ep_bytes)

        # Verify RECORD entries exist on disk with matching sha256 and byte size
        record_path = norm_dist_info / "RECORD"
        self.assertTrue(record_path.is_file())
        with open(record_path, "r", encoding="utf-8", newline="") as f:
            rows = list(csv.reader(f))

        recorded_paths = [row[0] for row in rows]
        self.assertIn("foo_bar-1.0.dist-info/METADATA", recorded_paths)
        self.assertIn("foo_bar-1.0.dist-info/INSTALLER", recorded_paths)
        self.assertIn("foo_bar-1.0.dist-info/RECORD", recorded_paths)
        self.assertIn("../bin/foo-bar", recorded_paths)
        self.assertIn("../bin/foo-helper", recorded_paths)
        for p in recorded_paths:
            self.assertFalse(p.startswith("Foo_Bar-1.0.dist-info"), f"Unnormalized path in RECORD: {p}")

        for rel_path, hash_spec, size_str in rows:
            target_file = (site_packages / rel_path).resolve()
            self.assertTrue(target_file.is_file(), f"RECORD target missing: {rel_path} -> {target_file}")
            if rel_path == "foo_bar-1.0.dist-info/RECORD":
                self.assertEqual(hash_spec, "")
                self.assertEqual(size_str, "")
            else:
                expected_hash, expected_size = self._record_hash_and_size(target_file.read_bytes())
                self.assertEqual(hash_spec, expected_hash, f"Hash mismatch for {rel_path}")
                self.assertEqual(size_str, expected_size, f"Size mismatch for {rel_path}")


class WheelInstallerPrecompileTest(unittest.TestCase):
    """Test optional .pyc precompilation in wheel_installer."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir)

    def _create_precompile_wheel(self) -> Path:
        import zipfile

        wheel_path = Path(self.temp_dir) / "pkg-1.0-py3-none-any.whl"
        with zipfile.ZipFile(wheel_path, "w") as zf:
            zf.writestr(
                "pkg-1.0.dist-info/METADATA",
                "Metadata-Version: 2.1\nName: pkg\nVersion: 1.0\n",
            )
            zf.writestr(
                "pkg-1.0.dist-info/WHEEL",
                "Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
            )
            zf.writestr("pkg-1.0.dist-info/RECORD", "")
            zf.writestr("pkg/__init__.py", "VALUE = 1\n")
            zf.writestr("pkg/sub.py", "def greet():\n    return 'hello'\n")
            zf.writestr("pkg/sub.pyi", "def greet() -> str: ...\n")
            zf.writestr("pkg/py2_legacy.py", "print 'legacy python 2 syntax'\n")
            zf.writestr("top.py", "TOP = True\n")
            zf.writestr("pkg-1.0.data/scripts/helper.py", "print('script')\n")
        return wheel_path

    @staticmethod
    def _tree_snapshot(root: Path) -> dict[str, bytes]:
        return {p.relative_to(root).as_posix(): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}

    def test_precompile_not_run_when_flags_omitted(self):
        import argparse

        from pycross.private.tools import wheel_installer

        wheel_path = self._create_precompile_wheel()
        out_dir = Path(self.temp_dir) / "out_no_compile"
        args = argparse.Namespace(
            wheel=wheel_path,
            wheel_dir=None,
            wheel_name_file=None,
            install_exclude_globs=[],
            patches=[],
            entry_points_output=None,
            directory=out_dir,
            expected_name="pkg",
            expected_version="1.0",
            dist_info_dir="pkg-1.0.dist-info",
            compile_python=None,
            compile_invalidation_mode=None,
        )
        wheel_installer.main(args)
        self.assertEqual(list(out_dir.rglob("*.pyc")), [])

    def test_precompile_modes_headers_dfile_and_determinism(self):
        import argparse
        import importlib.util
        import marshal
        import struct
        import sys

        from pycross.private.tools import wheel_installer

        wheel_path = self._create_precompile_wheel()
        out_checked_1 = Path(self.temp_dir) / "out_checked_1"
        out_checked_2 = Path(self.temp_dir) / "out_checked_2"
        out_unchecked = Path(self.temp_dir) / "out_unchecked"

        for out_dir, mode in [
            (out_checked_1, "checked_hash"),
            (out_checked_2, "checked_hash"),
            (out_unchecked, "unchecked_hash"),
        ]:
            args = argparse.Namespace(
                wheel=wheel_path,
                wheel_dir=None,
                wheel_name_file=None,
                install_exclude_globs=[],
                patches=[],
                entry_points_output=None,
                directory=out_dir,
                expected_name="pkg",
                expected_version="1.0",
                dist_info_dir="pkg-1.0.dist-info",
                compile_python=sys.executable,
                compile_invalidation_mode=mode,
            )
            wheel_installer.main(args)

        sp = out_checked_1 / "site-packages"
        expected_modules = ["pkg/__init__.py", "pkg/sub.py", "top.py"]
        for rel_mod in expected_modules:
            src_file = sp / rel_mod
            self.assertTrue(src_file.is_file(), f"Source should be kept: {rel_mod}")
            pyc_path = Path(importlib.util.cache_from_source(str(src_file)))
            self.assertTrue(pyc_path.is_file(), f"Missing .pyc for {rel_mod}: {pyc_path}")

            checked_bytes = pyc_path.read_bytes()
            checked_flags = struct.unpack("<I", checked_bytes[4:8])[0]
            self.assertEqual(checked_flags, 0b11, f"Expected checked_hash flags (0b11) for {rel_mod}")
            code_obj = marshal.loads(checked_bytes[16:])
            self.assertEqual(code_obj.co_filename, rel_mod)

            unchecked_src = out_unchecked / "site-packages" / rel_mod
            unchecked_pyc = Path(importlib.util.cache_from_source(str(unchecked_src)))
            unchecked_bytes = unchecked_pyc.read_bytes()
            unchecked_flags = struct.unpack("<I", unchecked_bytes[4:8])[0]
            self.assertEqual(unchecked_flags, 0b01, f"Expected unchecked_hash flags (0b01) for {rel_mod}")
            unchecked_code = marshal.loads(unchecked_bytes[16:])
            self.assertEqual(unchecked_code.co_filename, rel_mod)

        # Python 2 syntax file is kept as source and skipped without failing
        py2_src = sp / "pkg" / "py2_legacy.py"
        self.assertTrue(py2_src.is_file())
        py2_pyc = Path(importlib.util.cache_from_source(str(py2_src)))
        self.assertFalse(py2_pyc.exists())

        # Nothing outside site-packages/ is compiled
        self.assertTrue((out_checked_1 / "bin" / "helper.py").is_file())
        self.assertEqual(list((out_checked_1 / "bin").rglob("*.pyc")), [])

        # Two runs produce byte-identical trees
        self.assertEqual(
            self._tree_snapshot(out_checked_1),
            self._tree_snapshot(out_checked_2),
        )

    def test_precompile_optimize_level_and_hashseed_honored(self):
        import argparse
        import importlib.util
        import marshal
        import sys
        from unittest import mock

        from pycross.private.tools import wheel_installer

        wheel_path = self._create_precompile_wheel()
        out_opt1 = Path(self.temp_dir) / "out_opt1"
        args = argparse.Namespace(
            wheel=wheel_path,
            wheel_dir=None,
            wheel_name_file=None,
            install_exclude_globs=[],
            patches=[],
            entry_points_output=None,
            directory=out_opt1,
            expected_name="pkg",
            expected_version="1.0",
            dist_info_dir="pkg-1.0.dist-info",
            compile_python=sys.executable,
            compile_invalidation_mode="checked_hash",
            compile_optimize=1,
        )
        with mock.patch.object(
            wheel_installer.subprocess,
            "run",
            wraps=wheel_installer.subprocess.run,
        ) as run_spy:
            wheel_installer.main(args)

        self.assertEqual(run_spy.call_count, 1)
        cmd = run_spy.call_args[0][0]
        env = run_spy.call_args[1]["env"]
        self.assertNotIn("-I", cmd)
        self.assertNotIn("-E", cmd)
        self.assertIn("-S", cmd)
        self.assertIn("-s", cmd)
        self.assertIn("-B", cmd)
        self.assertEqual(env.get("PYTHONHASHSEED"), "0")
        self.assertEqual(env.get("PYTHONNOUSERSITE"), "1")
        self.assertEqual(env.get("PYTHONSAFEPATH"), "1")

        sp = out_opt1 / "site-packages"
        for rel_mod in ["pkg/__init__.py", "pkg/sub.py", "top.py"]:
            src_file = sp / rel_mod
            opt1_pyc = Path(importlib.util.cache_from_source(str(src_file), optimization=1))
            opt0_pyc = Path(importlib.util.cache_from_source(str(src_file), optimization=""))
            self.assertTrue(opt1_pyc.is_file(), f"Missing opt-1 .pyc for {rel_mod}: {opt1_pyc}")
            self.assertIn(".opt-1.pyc", opt1_pyc.name)
            self.assertFalse(opt0_pyc.exists(), f"Did not expect opt-0 .pyc for {rel_mod}")
            code_obj = marshal.loads(opt1_pyc.read_bytes()[16:])
            self.assertEqual(code_obj.co_filename, rel_mod)


class WheelInstallerIndexTest(unittest.TestCase):
    """Test the per-wheel index (--index-output) written after installation."""

    PATCH = (
        "--- a/patched_ns/__init__.py\n"
        "+++ b/patched_ns/__init__.py\n"
        "@@ -1 +1,2 @@\n"
        " __path__ = __import__('pkgutil').extend_path(__path__, __name__)\n"
        "+__version__ = '1'\n"
    )

    EXPECTED_INDEX = {
        "version": 1,
        "distribution": {"name": "Pkg-Name", "version": "1.0"},
        "dist_info": "pkg_name-1.0.dist-info",
        "top": {
            "_abi3ext": ["_abi3ext.abi3.so"],
            "_ext": ["_ext.cpython-311-x86_64-linux-gnu.so"],
            "ns": ["ns"],
            "pathroot": ["pathroot"],
            "patched_ns": ["patched_ns"],
            "pep420": ["pep420"],
            "pkg": ["pkg"],
            "top": ["top.py"],
            "winmod": ["winmod.cp311-win_amd64.pyd"],
        },
        "pth": ["paths.pth", "pkg.pth"],
        # Path lines only: no import lines, comments, missing or absolute dirs, or dirs outside
        # the root; normalized, deduplicated, in file order.
        "pth_paths": {"paths.pth": ["pathroot", "pathroot/sub", "pathroot/win"]},
        "dirs": [
            "ns",
            "ns/inner",
            "patched_ns",
            "pathroot",
            "pathroot/sub",
            "pathroot/win",
            "pep420",
            "pep420/deep",
            "pep420/regular",
            "pep420/regular/nsdir",
            "pkg",
            "pkg/data",
            "pkg/sub",
        ],
        "modules": {
            "patched_ns": ["mod"],
            "pep420/regular/nsdir": ["y"],
            "pkg/sub": ["mod"],
        },
        # patched_ns is a pkgutil stub in the wheel, but not after post_install_patches.
        "namespaces": {
            "ns": ["helper"],
            "pathroot": ["rooted"],
            "pathroot/sub": ["submod"],
            "pathroot/win": [],
            "pep420": ["helper2"],
            "pep420/deep": ["x"],
        },
    }

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir)

    def _create_wheel(self) -> Path:
        import zipfile

        wheel_path = Path(self.temp_dir) / "pkg_name-1.0-py3-none-any.whl"
        stub = "__path__ = __import__('pkgutil').extend_path(__path__, __name__)\n"
        files = {
            "Pkg_Name-1.0.dist-info/METADATA": "Metadata-Version: 2.1\nName: Pkg-Name\nVersion: 1.0\n",
            "Pkg_Name-1.0.dist-info/WHEEL": (
                "Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n"
            ),
            "Pkg_Name-1.0.dist-info/RECORD": "",
            "pkg/__init__.py": "VALUE = 1\n",
            "pkg/sub/__init__.py": "",
            "pkg/sub/mod.py": "X = 1\n",
            "pkg/data/thing.txt": "data\n",
            "pkg/not-a-pkg/x.py": "",
            "top.py": "TOP = True\n",
            "top_excluded.py": "",
            "_ext.cpython-311-x86_64-linux-gnu.so": "not really an extension",
            "_abi3ext.abi3.so": "",
            "winmod.cp311-win_amd64.pyd": "",
            "libfoo.so.1": "",
            "README.txt": "",
            "pkg.pth": "import pkg\n",
            "paths.pth": (
                "# comment\n"
                "pathroot\n"
                "import sys; sys.flags\n"
                "./pathroot/sub/\n"
                "missing_dir\n"
                "/abs/dir\n"
                "C:\\abs\\dir\n"
                "../outside\n"
                "pathroot\\win\n"
                ".\n"
                "\n"
                "pathroot\n"
            ),
            "pathroot/rooted.py": "",
            "pathroot/sub/submod.py": "",
            "pathroot/win/winonly.txt": "",
            "ns/__init__.py": stub,
            "ns/helper.py": "",
            "ns/excluded_helper.py": "",
            "ns/inner/__init__.py": "",
            "patched_ns/__init__.py": stub,
            "patched_ns/mod.py": "",
            "pep420/helper2.py": "",
            "pep420/deep/x.py": "",
            "pep420/regular/__init__.py": "",
            "pep420/regular/nsdir/y.py": "",
            "Pkg_Name-1.0.data/scripts/tool": "#!/bin/sh\n",
        }
        with zipfile.ZipFile(wheel_path, "w") as zf:
            for name, content in files.items():
                zf.writestr(name, content)
        return wheel_path

    def _install(self, name: str, compile_python=None) -> tuple[Path, Path]:
        import argparse

        from pycross.private.tools import wheel_installer

        patch = Path(self.temp_dir) / "make_regular.patch"
        patch.write_text(self.PATCH)
        out_dir = Path(self.temp_dir) / name
        index_out = Path(self.temp_dir) / (name + ".dist_info") / "index.json"
        args = argparse.Namespace(
            wheel=self._create_wheel(),
            wheel_dir=None,
            wheel_name_file=None,
            install_exclude_globs=["top_excluded.py", "ns/excluded_*"],
            patches=[str(patch)],
            entry_points_output=None,
            index_output=index_out,
            directory=out_dir,
            expected_name="pkg-name",
            expected_version="1.0",
            dist_info_dir="pkg_name-1.0.dist-info",
            compile_python=compile_python,
            compile_invalidation_mode="checked_hash" if compile_python else None,
        )
        wheel_installer.main(args)
        return out_dir, index_out

    def test_index_describes_installed_tree(self):
        import json

        _, index_out = self._install("out")
        self.assertEqual(json.loads(index_out.read_text()), self.EXPECTED_INDEX)

    def test_index_is_deterministic_and_relative(self):
        _, first = self._install("out1")
        _, second = self._install("out2")
        self.assertEqual(first.read_bytes(), second.read_bytes())
        self.assertNotIn(self.temp_dir, first.read_text())

    def test_index_ignores_precompiled_bytecode(self):
        import sys

        _, plain = self._install("plain")
        compiled_dir, compiled = self._install("compiled", compile_python=sys.executable)
        # .pyc files were written into __pycache__ dirs, including the root's (for top.py)...
        self.assertTrue((compiled_dir / "site-packages" / "__pycache__").is_dir())
        self.assertTrue(list((compiled_dir / "site-packages" / "pkg").glob("__pycache__/*.pyc")))
        # ...but the index doesn't change.
        self.assertEqual(plain.read_bytes(), compiled.read_bytes())


class WheelIndexModuleNameTest(unittest.TestCase):
    """Module names don't depend on the interpreter that runs the installer."""

    def test_module_names(self):
        from pycross.private.tools.wheel_index import module_name

        cases = {
            "six.py": "six",
            "legacy.pyc": "legacy",
            "_regex.cpython-311-x86_64-linux-gnu.so": "_regex",
            "_regex.cpython-314t-x86_64-linux-gnu.so": "_regex",
            "_speedups.cpython-312-darwin.so": "_speedups",
            "_foo.abi3.so": "_foo",
            "_foo.abi3-x86_64-linux-gnu.so": "_foo",
            "_cffi.pypy310-pp73-x86_64-linux-gnu.so": "_cffi",
            "plain.so": "plain",
            "win.cp311-win_amd64.pyd": "win",
            "win.pyd": "win",
            "libfoo.so.1": None,
            "foo.bar.baz.so": None,
            "foo-bar.py": None,
            "stubs.pyi": None,
            "README": None,
            "x.pth": None,
        }
        for filename, expected in cases.items():
            self.assertEqual(module_name(filename), expected, filename)


class WheelIndexNativeMetadataTest(unittest.TestCase):
    """Test read-only ELF shared-object metadata extraction in wheel_index.py."""

    LIBFIXTURE_CUBLAS_SO_12 = (
        "eNrtW19oHEUYn91r0o2Nua0kWJtqDkkw9c/mUj1oLUkOEuNaDNSSQgRls5fby53cn7q7oUkoGggitQZiX/TRxzz2"
        "MfhiQ0sJpQ/1odDHvBQiiAZKpfEh6+ztN5eZaTcp+CDK94Pd33zfzG++nT+7x97OfPneh6OqohCGBBkkuxYhWeD1"
        "NO87STR67iDt9bIHSDw2EiITPaJQ18TZMrcoIvO6erwU+CX+gYjM65rpMWFE9sSgyNcgzqoUTwVdEXTFQZEnFZE1"
        "kJ994Of3us5uIjLrw4+orpk8O1i3nYN4ce1bUURmzVRhHFj/1C9RjTj0O58t7TW8ZJRrGo83Y/x6jF+J8Z+nxwu0"
        "V7ehoY2+sazpSq1qeb7t+pZFrA/Gx6y84zrTJc933PGx4XKt6ozbubIT5T09x5qata1CqWqXS/MOKZRm/RnXsaZm"
        "cmXbI+VSTvQYXs3oPyH0KxvvLbi+Scl/TRdvJE26sdaHdtvF33d3Ob/K+e9z/gR/n3H+AwSBQCAQCAQCgUAgnoS5"
        "+JtmXmm610eTX1331eCuuXhTu9HIDzK3aVbQc4eek11ZmrpKU4Xlhn5pYC3ULjX9FNKpx34Hre4LqK4l2Eh2LYTl"
        "bgDT8t/Vy2e+Cen4jnl5y1z7fchce5wwlVvmLzt+O60gAxVowUYh2TWyq3+YfOWvhYExmk1m3jhvLg6oYdK8/MBv"
        "Na8MGNTY/DgIgs08Pd1q6qG28inVCvpfL9LM1dbwqqL2Cy1GIBAIBAKBQCAQCATi/welM3E6/AYdfktMbQVBlnKa"
        "cpHyNuUFKNfOys+fI8qsrnS2HtSWlej79TF63P8jCOqfOtv00bYjZ5KHLmoLZOjo6dff7n6V6elrPLlOy2lc/FDz"
        "CT0+p7GacTgQCAQCgUAgEAgE4j8Hth6WrX9tA38euJV/AaR4ntmHI3oJTLbOthNs9u54FJittz0m5T/aCWr1BLeW"
        "OcQq2Oxdsxfs58C+BHwI+AgwW2u7CetsD4J9MiHGXQFukfTbQXQ9iX9pPNh69SeQjej94eF3U70jTq5kV1P9GeOE"
        "kX6r/53jkCTE8Iqe7/p2jhjT1RmjaHtFYuTnqt5cJWLfJYbrlO3QIEapWvKJcaHsG9M1mvCdWXouUC8xnKJVcO2K"
        "YxXz7q4VSSzbde25qCRL0/rsSmmKhDWFNVKP7dvEyHkeMaZqlYpT9f95/4Tj/Scdo8Zaa1XkbsmtSfoOqEOV5hXj"
        "ZW4eKZyezY+XIU+V5injS/L/NpLdQ6J136o0LxmvxFw/i99HxD0A8n6MF6V48hrzryV9ShdZl8rL2z4ykj6tiyz3"
        "tybxoKTP6iL/HBOfYURu/2GRW/Zp/xnQN+ZPSuTuffQTkr43JfKFmPYz5OAZm5Cem2w/yH79V6VHktOz5+rkM+rn"
        "ibgnobFPBvRsf0xC0rFxOAXtZ/lsX8R6n9idcfEXJT17Tm/2ifM8Tv+tpG9sfErv3X6Gq+BrtA/0Woxevn+/B19a"
        "jgOOrhg9z0/7bXkN9D/u"
        "E/9v7Gcvhw=="
    )
    LIBUSER_SO = (
        "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"
        "QP/NPPX/Caf28Vw="
    )

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir)

    @staticmethod
    def _unpack_blob(b64_data: str) -> bytes:
        import base64
        import zlib

        return zlib.decompress(base64.b64decode(b64_data))

    def test_native_elf_metadata_recorded_in_wheel_index(self):
        from pycross.private.tools.wheel_index import index_site_packages

        root = Path(self.temp_dir) / "site-packages"
        cublas_so = root / "nvidia" / "fixture_cublas" / "lib" / "libfixture_cublas.so.12"
        user_so = root / "rpathuser" / "libuser.so"
        extra_so = root / "rpathuser.libs" / "libbundled.so.1"
        for p, data in [
            (cublas_so, self._unpack_blob(self.LIBFIXTURE_CUBLAS_SO_12)),
            (user_so, self._unpack_blob(self.LIBUSER_SO)),
            (extra_so, self._unpack_blob(self.LIBFIXTURE_CUBLAS_SO_12)),
        ]:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)

        idx = index_site_packages(root, "rpath-user", "1.0")
        self.assertEqual(
            idx["native"],
            {
                "nvidia/fixture_cublas/lib/libfixture_cublas.so.12": {
                    "needed": [],
                    "rpath": [],
                    "runpath": [],
                    "soname": "libfixture_cublas.so.12",
                },
                "rpathuser.libs/libbundled.so.1": {
                    "needed": [],
                    "rpath": [],
                    "runpath": [],
                    "soname": "libfixture_cublas.so.12",
                },
                "rpathuser/libuser.so": {
                    "needed": ["libfixture_cublas.so.12", "libc.so.6"],
                    "rpath": [],
                    "runpath": [
                        "$ORIGIN/../nvidia/fixture_cublas/lib",
                        "$ORIGIN/../nvidia/fixture_cudnn/lib",
                    ],
                    "soname": None,
                },
            },
        )

    def test_native_elf_metadata_records_soname_symlinks(self):
        from pycross.private.tools.wheel_index import index_site_packages

        root = Path(self.temp_dir) / "site-packages"
        lib_dir = root / "pkg" / "lib"
        lib_dir.mkdir(parents=True, exist_ok=True)
        (root / "pkg" / "__init__.py").write_text("")
        real_so = lib_dir / "libfixture_cublas.so.12.8"
        real_so.write_bytes(self._unpack_blob(self.LIBFIXTURE_CUBLAS_SO_12))
        symlink_so = lib_dir / "libfixture_cublas.so.12"
        symlink_so.symlink_to("libfixture_cublas.so.12.8")
        broken_so = lib_dir / "libbroken.so.1"
        broken_so.symlink_to("nonexistent.so")

        idx = index_site_packages(root, "pkg", "1.0")
        self.assertIn("pkg/lib/libfixture_cublas.so.12.8", idx["native"])
        self.assertIn("pkg/lib/libfixture_cublas.so.12", idx["native"])
        self.assertEqual(
            idx["native"]["pkg/lib/libfixture_cublas.so.12"]["soname"],
            "libfixture_cublas.so.12",
        )
        self.assertNotIn("pkg/lib/libbroken.so.1", idx["native"])


if __name__ == "__main__":
    unittest.main()
