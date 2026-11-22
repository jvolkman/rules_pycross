import base64
import csv
import hashlib
import io
import unittest
import zipfile
from pathlib import Path
from tempfile import TemporaryDirectory

from pycross.private.build.tools.scrub_build_paths import scrub_text
from pycross.private.build.tools.scrub_build_paths import scrub_wheel


def _expected_hash(data: bytes) -> str:
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode("ascii")
    return f"sha256={digest}"


class ScrubBuildPathsTest(unittest.TestCase):
    def test_scrub_text_anchors_external_prefix(self):
        prefix = "/sandbox/execroot/_main"
        raw = (
            'CC = "/sandbox/execroot/_main/bazel-out/k8-fastbuild/bin/external/llvm/clang"\n'
            'CFLAGS = "-Iexternal/foo/inc -Lexternal/bar/lib -isystemexternal/baz/inc --sysroot=external/sys"\n'
            'PKG = "my_external/pkg/external/mod.py"\n'
        )
        scrubbed = scrub_text(raw, prefix)
        self.assertEqual(
            scrubbed,
            'CC = "llvm/clang"\n'
            'CFLAGS = "-Ifoo/inc -Lbar/lib -isystembaz/inc --sysroot=sys"\n'
            'PKG = "my_external/pkg/external/mod.py"\n',
        )

    def test_scrub_wheel_updates_record_hashes_and_sizes(self):
        with TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            in_whl = tmp_path / "demo-1.0-py3-none-any.whl"
            out_whl = tmp_path / "out-demo-1.0-py3-none-any.whl"

            orig_cfg = b'ROOT = "/tmp/sandbox/bazel-out/k8-fastbuild/bin/external/dep/lib"\n'
            untouched = b"x = 1\n"
            record_content = (
                f"demo/__config__.py,{_expected_hash(orig_cfg)},{len(orig_cfg)}\n"
                f"demo/mod.py,{_expected_hash(untouched)},{len(untouched)}\n"
                "demo-1.0.dist-info/RECORD,,\n"
            ).encode("utf-8")

            # Deliberately put RECORD before the scrubbed file to verify deferred rewrite.
            with zipfile.ZipFile(in_whl, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                zf.writestr("demo-1.0.dist-info/RECORD", record_content)
                zf.writestr("demo/__config__.py", orig_cfg)
                zf.writestr("demo/mod.py", untouched)

            modified = scrub_wheel(in_whl, out_whl, "/tmp/sandbox", {"demo/__config__.py"})
            self.assertTrue(modified)

            with zipfile.ZipFile(out_whl, "r") as zf:
                self.assertIsNone(zf.testzip())
                new_cfg = zf.read("demo/__config__.py")
                self.assertEqual(new_cfg, b'ROOT = "dep/lib"\n')
                self.assertEqual(zf.read("demo/mod.py"), untouched)

                rows = list(csv.reader(io.StringIO(zf.read("demo-1.0.dist-info/RECORD").decode("utf-8"))))
                self.assertEqual(
                    rows,
                    [
                        ["demo/__config__.py", _expected_hash(new_cfg), str(len(new_cfg))],
                        ["demo/mod.py", _expected_hash(untouched), str(len(untouched))],
                        ["demo-1.0.dist-info/RECORD", "", ""],
                    ],
                )

    def test_scrub_wheel_preserves_crlf_record_line_endings(self):
        with TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            in_whl = tmp_path / "demo-1.0-py3-none-any.whl"
            out_whl = tmp_path / "out-demo-1.0-py3-none-any.whl"

            orig_cfg = b'ROOT = "/tmp/sandbox/external/dep/lib"\n'
            record_content = (
                f"demo/__config__.py,{_expected_hash(orig_cfg)},{len(orig_cfg)}\r\ndemo-1.0.dist-info/RECORD,,\r\n"
            ).encode("utf-8")

            with zipfile.ZipFile(in_whl, "w") as zf:
                zf.writestr("demo/__config__.py", orig_cfg)
                zf.writestr("demo-1.0.dist-info/RECORD", record_content)

            scrub_wheel(in_whl, out_whl, "/tmp/sandbox", {"demo/__config__.py"})
            with zipfile.ZipFile(out_whl, "r") as zf:
                rec = zf.read("demo-1.0.dist-info/RECORD")
                self.assertIn(b"\r\n", rec)
                self.assertNotIn(b"\n", rec.replace(b"\r\n", b""))


if __name__ == "__main__":
    unittest.main()
