"""Tests for pycross_patch. See patch_conformance_test.py for the adopted upstream fixtures."""

import os
import re
import stat
import tempfile
import unittest
from pathlib import Path

import pycross_patch

# Header helper: git-style `a/` + `b/` file header pair.
H = lambda a, b: b"--- a/" + a + b"\n+++ b/" + b + b"\n"  # noqa: E731
F = {"x.py": b"a\nb\nc\nd\ne\n"}


class _TreeTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.root = self.tmp / "root"
        self.root.mkdir()
        self._n = 0

    def tearDown(self):
        self._tmp.cleanup()

    def write_tree(self, files, root=None):
        root = root or self.root
        for rel, data in files.items():
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)

    def snapshot(self, root=None):
        root = root or self.root
        return {p.relative_to(root).as_posix(): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}

    def write_patch(self, data):
        self._n += 1
        p = self.tmp / f"p{self._n}.patch"
        p.write_bytes(data)
        return p


class EffectiveStripTest(unittest.TestCase):
    """At strip 0, git-style a/ b/ prefixes are stripped, as patch_ng (pycross's old engine) did."""

    def test_git_style_pair_gets_strip_1(self):
        self.assertEqual(pycross_patch.effective_strip(H(b"x.py", b"x.py") + b"@@ -1 +1 @@\n-a\n+b\n"), 1)

    def test_dev_null_on_either_side_gets_strip_1(self):
        create = b"--- /dev/null\n+++ b/new.py\n@@ -0,0 +1 @@\n+x\n"
        delete = b"--- a/old.py\n+++ /dev/null\n@@ -1 +0,0 @@\n-x\n"
        self.assertEqual(pycross_patch.effective_strip(create), 1)
        self.assertEqual(pycross_patch.effective_strip(delete), 1)
        self.assertEqual(pycross_patch.effective_strip(create + delete), 1)

    def test_git_extended_headers_and_timestamps(self):
        patch = (
            b"diff --git a/pkg/new.py b/pkg/new.py\n"
            b"new file mode 100644\n"
            b"--- /dev/null\n"
            b"+++ b/pkg/new.py\t2026-06-04 13:23:03.082422796 +0000\n"
            b"@@ -0,0 +1 @@\n+x\n"
        )
        self.assertEqual(pycross_patch.effective_strip(patch), 1)

    def test_plain_headers_keep_strip_0(self):
        self.assertEqual(pycross_patch.effective_strip(b"--- x.py\n+++ x.py\n@@ -1 +1 @@\n-a\n+b\n"), 0)
        self.assertEqual(pycross_patch.effective_strip(b"--- x.py.orig\n+++ x.py\n@@ -1 +1 @@\n-a\n+b\n"), 0)

    def test_mixed_headers_keep_strip_0(self):
        patch = H(b"x.py", b"x.py") + b"@@ -1 +1 @@\n-a\n+b\n" + b"--- y.py\n+++ y.py\n@@ -1 +1 @@\n-a\n+b\n"
        self.assertEqual(pycross_patch.effective_strip(patch), 0)

    def test_explicit_strip_is_used_as_given(self):
        patch = H(b"x.py", b"x.py") + b"@@ -1 +1 @@\n-a\n+b\n"
        self.assertEqual(pycross_patch.effective_strip(patch, 1), 1)
        self.assertEqual(pycross_patch.effective_strip(patch, 2), 2)

    def test_hunk_bodies_are_not_mistaken_for_headers(self):
        # Removing a line `-- x.py` and adding `++ x.py` produces body lines that look like a
        # plain `--- `/`+++ ` header. They must not turn off the git-style strip.
        patch = H(b"f.sql", b"f.sql") + b"@@ -1,2 +1,2 @@\n a\n--- x.py\n+++ x.py\n"
        self.assertEqual(pycross_patch.effective_strip(patch), 1)

    def test_format_patch_preamble_and_signature(self):
        patch = (
            b"From 0123 Mon Sep 17 00:00:00 2001\nSubject: [PATCH] u\n\nmsg\n---\n x.py | 2 +-\n\n"
            b"diff --git a/x.py b/x.py\nindex 1..2 100644\n"
            + H(b"x.py", b"x.py")
            + b"@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n-- \n2.40\n"
        )
        self.assertEqual(pycross_patch.effective_strip(patch), 1)

    def test_no_headers_keeps_strip(self):
        self.assertEqual(pycross_patch.effective_strip(b"not a patch\n"), 0)


class ApplyPatchTest(_TreeTestCase):
    def test_git_style_patch_applies_at_strip_0(self):
        self.write_tree(F)
        touched = pycross_patch.apply_patch(
            self.root, self.write_patch(H(b"x.py", b"x.py") + b"@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n")
        )
        self.assertEqual(touched, {"x.py"})
        self.assertEqual(self.snapshot(), {"x.py": b"a\nb\nC\nd\ne\n"})

    def test_plain_patch_applies_at_literal_path(self):
        self.write_tree({"pkg/x.py": b"a\n"})
        pycross_patch.apply_patch(self.root, self.write_patch(b"--- pkg/x.py\n+++ pkg/x.py\n@@ -1 +1 @@\n-a\n+b\n"))
        self.assertEqual(self.snapshot(), {"pkg/x.py": b"b\n"})

    def test_git_style_strip_applies_even_with_literal_a_dir(self):
        # patch_ng only stripped a/ b/ when the literal path was missing. pycross_patch strips
        # whenever every header is git-style; a real top-level `b/` directory isn't used.
        self.write_tree({"x.py": b"a\n", "b/x.py": b"a\n"})
        pycross_patch.apply_patch(self.root, self.write_patch(H(b"x.py", b"x.py") + b"@@ -1 +1 @@\n-a\n+z\n"))
        self.assertEqual(self.snapshot(), {"x.py": b"z\n", "b/x.py": b"a\n"})

    def test_explicit_strip(self):
        self.write_tree({"x.py": b"a\n"})
        patch = b"--- one/two/x.py\n+++ one/two/x.py\n@@ -1 +1 @@\n-a\n+b\n"
        pycross_patch.apply_patch(self.root, self.write_patch(patch), strip=2)
        self.assertEqual(self.snapshot(), {"x.py": b"b\n"})

    def test_preserves_file_mode(self):
        self.write_tree({"tool.sh": b"echo a\n"})
        os.chmod(self.root / "tool.sh", 0o755)
        pycross_patch.apply_patch(
            self.root, self.write_patch(H(b"tool.sh", b"tool.sh") + b"@@ -1 +1 @@\n-echo a\n+echo b\n")
        )
        self.assertTrue(os.stat(self.root / "tool.sh").st_mode & stat.S_IXUSR)

    def test_errors(self):
        self.write_tree(F)
        with self.assertRaisesRegex(pycross_patch.PatchParseError, "no file changes found"):
            pycross_patch.apply_patch(self.root, self.write_patch(b"not a patch\n"))
        with self.assertRaisesRegex(pycross_patch.PatchParseError, "binary patches are not supported"):
            pycross_patch.apply_patch(
                self.root, self.write_patch(b"diff --git a/x.bin b/x.bin\nGIT binary patch\nliteral 0\n")
            )
        with self.assertRaisesRegex(pycross_patch.PatchError, "context mismatch") as ctx:
            pycross_patch.apply_patch(self.root, self.write_patch(H(b"x.py", b"x.py") + b"@@ -1 +1 @@\n-zzz\n+b\n"))
        self.assertNotIsInstance(ctx.exception, pycross_patch.PatchParseError)
        with self.assertRaisesRegex(pycross_patch.PatchError, "targets non-existent file 'missing.py'"):
            pycross_patch.apply_patch(
                self.root, self.write_patch(H(b"missing.py", b"missing.py") + b"@@ -1 +1 @@\n-a\n+b\n")
            )
        with self.assertRaises(pycross_patch.PatchError):
            pycross_patch.apply_patch(self.root, self.tmp / "does-not-exist.patch")

    def test_apply_patch_or_exit_messages(self):
        self.write_tree(F)
        with self.assertRaises(SystemExit) as ctx:
            pycross_patch.apply_patch_or_exit(self.root, self.write_patch(b"garbage\n"), display_name="//:bad.patch")
        self.assertRegex(
            str(ctx.exception), r"^error: failed to parse patch file: //:bad\.patch: no file changes found"
        )
        with self.assertRaises(SystemExit) as ctx:
            pycross_patch.apply_patch_or_exit(
                self.root, self.write_patch(H(b"x.py", b"x.py") + b"@@ -1 +1 @@\n-zzz\n+b\n")
            )
        self.assertRegex(str(ctx.exception), r"^error: failed to apply patch file: .*p\d+\.patch: .*context mismatch")


def _split_single_hunk(patch: bytes):
    """Return (old_start, old_lines, new_lines) for a single-hunk patch."""
    lines = patch.splitlines(keepends=True)
    idx = next(i for i, line in enumerate(lines) if line.startswith(b"@@ "))
    old_start = int(re.match(rb"@@ -(\d+)", lines[idx]).group(1))
    old, new = [], []
    for line in lines[idx + 1 :]:
        op, body = (b" ", b"\n") if line == b"\n" else (line[:1], line[1:])
        if op in (b" ", b"-"):
            old.append(body)
        if op in (b" ", b"+"):
            new.append(body)
    return old_start, old, new


class RealPatchTest(_TreeTestCase):
    """Real patches pycross users apply, verbatim, at pycross's default strip (0).

    Each pre-image puts the hunk's old side at its stated line number. These
    patches were also applied to the real wheels/sdists and produced trees
    byte-identical to patch_ng's.
    """

    MATPLOTLIB = (  # examples/bzlmod/matplotlib.patch
        b"--- a/matplotlib/__init__.py\n"
        b"+++ b/matplotlib/__init__.py\n"
        b"@@ -154,6 +154,12 @@\n"
        b" import sys\n"
        b" import tempfile\n"
        b" \n"
        b"+# Python initially loaded mpl_toolkits in site-packages by pth might not be the one we need,"
        b" so we explicitly reload it\n"
        b"+try:\n"
        b"+    __import__('importlib').reload(sys.modules['mpl_toolkits'])\n"
        b"+except:\n"
        b"+    pass\n"
        b"+\n"
        b" from packaging.version import parse as parse_version\n"
        b"\n"
        b" # cbook must import matplotlib only within function\n"
    )
    SETPROCTITLE_PREBUILD = (  # tests/e2e/patches_and_hooks/patches/setproctitle-prebuild.patch
        b"--- a/pkg/setproctitle/__init__.py\t2026-06-04 13:22:25.044466888 +0000\n"
        b"+++ b/pkg/setproctitle/__init__.py\t2026-06-04 13:23:03.082422796 +0000\n"
        b"@@ -55,3 +55,4 @@\n"
        b" # by fork() on macOS (see #113).\n"
        b' if sys.platform == "darwin":\n'
        b"     getproctitle()\n"
        b"+PATCHED = True\n"
    )
    SETPROCTITLE_POSTINSTALL = (  # tests/e2e/patches_and_hooks/patches/setproctitle-postinstall.patch
        b"--- a/setproctitle/__init__.py\n"
        b"+++ b/setproctitle/__init__.py\n"
        b"@@ -56,3 +56,4 @@\n"
        b' if sys.platform == "darwin":\n'
        b"     getproctitle()\n"
        b" PATCHED = True\n"
        b"+POST_PATCHED = True\n"
    )
    USE_HATCHLING = (  # tests/e2e/sdist_repo/use_hatchling.patch
        b"--- a/pyproject.toml\n"
        b"+++ b/pyproject.toml\n"
        b"@@ -1,3 +1,3 @@\n"
        b" [build-system]\n"
        b'-requires = ["setuptools", "unknown_dep"]\n'
        b'-build-backend = "setuptools.build_meta"\n'
        b'+requires = ["hatchling"]\n'
        b'+build-backend = "hatchling.build"\n'
    )

    def _check(self, patch, rel, trailer=b""):
        old_start, old, new = _split_single_hunk(patch)
        filler = b"".join(b"# filler %d\n" % i for i in range(1, old_start))
        self.write_tree({rel: filler + b"".join(old) + trailer})
        self.assertEqual(pycross_patch.effective_strip(patch), 1)
        touched = pycross_patch.apply_patch(self.root, self.write_patch(patch))
        self.assertEqual(touched, {rel})
        self.assertEqual(self.snapshot(), {rel: filler + b"".join(new) + trailer})

    def test_matplotlib(self):
        self._check(self.MATPLOTLIB, "matplotlib/__init__.py", trailer=b"from . import _api\n")

    def test_setproctitle_prebuild(self):
        self._check(self.SETPROCTITLE_PREBUILD, "pkg/setproctitle/__init__.py")

    def test_setproctitle_postinstall_with_site_hook_lines(self):
        # In the e2e build, the site hook appends these lines after `PATCHED = True`. GNU patch
        # treats the hunk (3 leading, 0 trailing context lines) as anchored to EOF and rejects it;
        # patch_ng and pycross_patch both apply it, which the e2e test relies on.
        self._check(
            self.SETPROCTITLE_POSTINSTALL,
            "setproctitle/__init__.py",
            trailer=b"SITE_HOOK_RAN = True\nSITE_HOOK_RAN = True\n",
        )

    def test_use_hatchling(self):
        # Exact pyproject.toml from tests/e2e/sdist_repo/sdists/with_setuptools.tar.gz.
        self.write_tree(
            {
                "pyproject.toml": b'[build-system]\nrequires = ["setuptools", "unknown_dep"]\nbuild-backend = "setuptools.build_meta"\n'
            }
        )
        pycross_patch.apply_patch(self.root, self.write_patch(self.USE_HATCHLING))
        self.assertEqual(
            self.snapshot(),
            {"pyproject.toml": b'[build-system]\nrequires = ["hatchling"]\nbuild-backend = "hatchling.build"\n'},
        )

    def test_git_style_create_new_file(self):
        # A git-style post_install patch that adds a package `__init__.py` next to existing files.
        patch = (
            b"diff --git a/pkg/__init__.py b/pkg/__init__.py\n"
            b"new file mode 100644\n"
            b"--- /dev/null\n"
            b"+++ b/pkg/__init__.py\n"
            b"@@ -0,0 +1,2 @@\n"
            b"+X = 1\n"
            b"+\n"
        )
        self.write_tree({"pkg/lib/libfoo.so.1": b"\x7fELF"})
        pycross_patch.apply_patch(self.root, self.write_patch(patch))
        self.assertEqual(self.snapshot(), {"pkg/lib/libfoo.so.1": b"\x7fELF", "pkg/__init__.py": b"X = 1\n\n"})


class EngineEdgeCaseTest(_TreeTestCase):
    """Edge cases at an explicit strip level, including the cases rules_python's tests covered."""

    def test_stale_context_then_crlf_preservation(self):
        target = self.root / "pkg/mod.py"
        target.parent.mkdir(parents=True)
        target.write_bytes(b"line1 = 1\r\nline2 = 'changed'\r\n")
        stale_patch = self.write_patch(
            b"--- a/pkg/mod.py\n+++ b/pkg/mod.py\n@@ -1,2 +1,2 @@\n line1 = 1\n-line2 = 'expected'\n+line2 = 'patched'\n"
        )
        with self.assertRaisesRegex(pycross_patch.PatchError, "context mismatch"):
            pycross_patch.apply_patch(self.root, stale_patch, strip=1)

        target.write_bytes(b"line1 = 1\r\nline2 = 'expected'\r\n")
        touched = pycross_patch.apply_patch(self.root, stale_patch, strip=1)
        self.assertEqual(touched, {"pkg/mod.py"})
        self.assertEqual(target.read_bytes(), b"line1 = 1\r\nline2 = 'patched'\r\n")

    def test_edge_cases(self):
        for name, init_files, patch_bytes, strip, expected in [
            (
                "u0_insert_and_no_newline_and_format_patch_footer",
                {"pkg/f.py": b"a\n-- keep\nb"},
                b"--- a/pkg/f.py\n+++ b/pkg/f.py\n"
                b"@@ -1,0 +2,1 @@\n+mid\n"
                b"@@ -2,2 +3,1 @@\n--- keep\n b\n\\ No newline at end of file\n"
                b"-- \n2.45.0\n",
                1,
                {"pkg/f.py": b"a\nmid\nb"},
            ),
            (
                "trimmed_format_patch_footer",
                {"pkg/f.py": b"a\n"},
                b"--- a/pkg/f.py\n+++ b/pkg/f.py\n@@ -1 +1 @@\n-a\n+b\n--\n2.45.0\n",
                1,
                {"pkg/f.py": b"b\n"},
            ),
            (
                "non_utf8_bytes",
                {"pkg/bin.py": b"# \xff\xfe\nx = 1\n"},
                b"--- a/pkg/bin.py\n+++ b/pkg/bin.py\n@@ -1,2 +1,2 @@\n # \xff\xfe\n-x = 1\n+x = 2\n",
                1,
                {"pkg/bin.py": b"# \xff\xfe\nx = 2\n"},
            ),
            (
                "create_over_existing",
                {"pkg/e.py": b"old\n"},
                b"--- /dev/null\n+++ b/pkg/e.py\n@@ -0,0 +1 @@\n+new\n",
                1,
                "creates 'pkg/e.py', which already exists",
            ),
            (
                "partial_delete",
                {"pkg/d.py": b"1\n2\n"},
                b"--- a/pkg/d.py\n+++ /dev/null\n@@ -1,1 +0,0 @@\n-1\n",
                1,
                "doesn't remove all of its lines",
            ),
            (
                "out_of_order_hunks",
                {"pkg/o.py": b"1\n2\n3\n"},
                b"--- a/pkg/o.py\n+++ b/pkg/o.py\n@@ -3,1 +3,1 @@\n-3\n+three\n@@ -1,1 +1,1 @@\n-1\n+one\n",
                1,
                "hunk #2 .* context mismatch",
            ),
            (
                "traversal",
                {},
                b"--- /dev/null\n+++ b/../../escape.py\n@@ -0,0 +1 @@\n+x = 1\n",
                1,
                "unsafe file name",
            ),
            (
                "abs_path",
                {},
                b"--- /dev/null\n+++ /abs/escape.py\n@@ -0,0 +1 @@\n+x = 1\n",
                0,
                "unsafe file name",
            ),
            (
                "binary_patch",
                {},
                b"GIT binary patch\nliteral 0\n",
                1,
                "binary patches are not supported",
            ),
            (
                "rename_lines_without_diff_git",
                {},
                b"rename from a/x.py\nrename to b/y.py\n",
                1,
                "no file changes found",
            ),
            (
                "orphan_hunk_before_header",
                {},
                b"@@ -1,1 +1,1 @@\n-a\n+b\n",
                1,
                "hunk has no '--- '/'\\+\\+\\+ ' file header",
            ),
            (
                "stray_body_line",
                {"pkg/s.py": b"a\n"},
                b"--- a/pkg/s.py\n+++ b/pkg/s.py\n@@ -1,1 +1,1 @@\nSTRAY\n",
                1,
                "line 4: line doesn't fit the hunk",
            ),
        ]:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as case_tmp:
                case_root = Path(case_tmp)
                self.write_tree(init_files, root=case_root)
                pf = case_root / "case.patch"
                pf.write_bytes(patch_bytes)
                if isinstance(expected, str):
                    with self.assertRaisesRegex(pycross_patch.PatchError, expected):
                        pycross_patch.apply_patch(case_root, pf, strip=strip)
                else:
                    pycross_patch.apply_patch(case_root, pf, strip=strip)
                    for rel, exp_bytes in expected.items():
                        self.assertEqual((case_root / rel).read_bytes(), exp_bytes)


class RegressionTest(_TreeTestCase):
    """Bugs found while reviewing the engine."""

    def test_offset_from_earlier_hunk_carries_to_later_hunks(self):
        # Ten import lines were added above the code the patch was made against. After hunk 1
        # is found 10 lines down, hunk 2 must look 10 lines down too, at f3's body. f2's body
        # is identical and closer to the hunk's stated line, and must not be patched instead.
        body = b"    a = 1\n    y = 0\n    return y\n"
        code = b"def f1():\n    x = 1\n\ndef f2():\n" + body + b"\ndef f3():\n" + body
        imports = b"".join(b"import m%d\n" % i for i in range(10))
        self.write_tree({"m.py": imports + code})
        patch = H(b"m.py", b"m.py") + (
            b"@@ -1,2 +1,2 @@\n def f1():\n-    x = 1\n+    x = 2\n"
            b"@@ -10,3 +10,3 @@\n     a = 1\n-    y = 0\n+    y = 9\n     return y\n"
        )
        pycross_patch.apply_patch(self.root, self.write_patch(patch))
        f3 = code.index(b"def f3")
        expected = code[:f3].replace(b"x = 1", b"x = 2") + code[f3:].replace(b"y = 0", b"y = 9")
        self.assertEqual(self.snapshot(), {"m.py": imports + expected})

    def test_hunkless_git_sections_in_multi_file_patch(self):
        self.write_tree({"m.txt": b"a\n", "gone/py.typed": b"", "tool.sh": b"echo\n"})
        patch = (
            b"diff --git a/pkg/__init__.py b/pkg/__init__.py\nnew file mode 100644\nindex 0000000..e69de29\n"
            b"diff --git a/gone/py.typed b/gone/py.typed\ndeleted file mode 100644\nindex e69de29..0000000\n"
            b"diff --git a/tool.sh b/tool.sh\nold mode 100644\nnew mode 100755\n"
            b"diff --git a/m.txt b/m.txt\n--- a/m.txt\n+++ b/m.txt\n@@ -1 +1 @@\n-a\n+b\n"
        )
        touched = pycross_patch.apply_patch(self.root, self.write_patch(patch))
        self.assertEqual(touched, {"pkg/__init__.py", "gone/py.typed", "tool.sh", "m.txt"})
        self.assertEqual(self.snapshot(), {"pkg/__init__.py": b"", "m.txt": b"b\n", "tool.sh": b"echo\n"})
        self.assertTrue(os.stat(self.root / "tool.sh").st_mode & stat.S_IXUSR)

    def test_dot_dot_component_is_rejected_even_if_it_stays_inside_root(self):
        self.write_tree({"x.py": b"PRECIOUS\n"})
        patch = b"--- /dev/null\n+++ b/ghost/../x.py\n@@ -0,0 +1 @@\n+EVIL\n"
        with self.assertRaisesRegex(pycross_patch.PatchError, "unsafe file name"):
            pycross_patch.apply_patch(self.root, self.write_patch(patch))
        self.assertEqual(self.snapshot(), {"x.py": b"PRECIOUS\n"})
        self.assertFalse((self.root / "ghost").exists())

    def test_create_over_dangling_symlink_fails(self):
        os.symlink("missing-target", self.root / "link.py")
        patch = b"--- /dev/null\n+++ b/link.py\n@@ -0,0 +1 @@\n+x\n"
        with self.assertRaisesRegex(pycross_patch.PatchError, "already exists"):
            pycross_patch.apply_patch(self.root, self.write_patch(patch))

    def test_symlink_out_of_root_is_rejected(self):
        outside = self.tmp / "outside.py"
        outside.write_bytes(b"a\n")
        os.symlink(outside, self.root / "link.py")
        patch = H(b"link.py", b"link.py") + b"@@ -1 +1 @@\n-a\n+b\n"
        with self.assertRaisesRegex(pycross_patch.PatchError, "outside the patch root"):
            pycross_patch.apply_patch(self.root, self.write_patch(patch))
        self.assertEqual(outside.read_bytes(), b"a\n")

    def test_failed_patch_writes_nothing(self):
        self.write_tree({"x.py": b"a\n", "y.py": b"q\n"})
        patch = (
            H(b"x.py", b"x.py")
            + b"@@ -1 +1 @@\n-a\n+A\n"
            + b"--- /dev/null\n+++ b/new.py\n@@ -0,0 +1 @@\n+n\n"
            + H(b"y.py", b"y.py")
            + b"@@ -1 +1 @@\n-zzz\n+Z\n"
        )
        with self.assertRaisesRegex(pycross_patch.PatchError, "failed to apply to y.py"):
            pycross_patch.apply_patch(self.root, self.write_patch(patch))
        self.assertEqual(self.snapshot(), {"x.py": b"a\n", "y.py": b"q\n"})

    def test_huge_hunk_line_number_fails_quickly(self):
        self.write_tree({"x.py": b"a\n"})
        patch = H(b"x.py", b"x.py") + b"@@ -9223372036854775803 +9223372036854775803 @@\n-zzz\n+b\n"
        with self.assertRaisesRegex(pycross_patch.PatchError, "context mismatch"):
            pycross_patch.apply_patch(self.root, self.write_patch(patch))


class ReviewFindingsTest(_TreeTestCase):
    """Cases from the second review of the engine."""

    def _apply(self, patch, strip=0):
        return pycross_patch.apply_patch(self.root, self.write_patch(patch), strip)

    def test_contradictory_git_headers_are_parse_errors(self):
        self.write_tree({"x.py": b"a\n"})
        for patch in [
            b"diff --git a/x.py b/x.py\nnew file mode 100644\ndeleted file mode 100644\n",
            b"diff --git a/x.py b/x.py\nnew file mode 100644\n--- a/x.py\n+++ /dev/null\n@@ -0,0 +0,0 @@\n",
            b"diff --git a/x.py b/y.py\nrename from x.py\nrename to y.py\ncopy from x.py\ncopy to y.py\n",
            b"diff --git a/x.py b/y.py\ndeleted file mode 100644\nrename from x.py\nrename to y.py\n",
        ]:
            with self.subTest(patch=patch):
                with self.assertRaises(SystemExit) as ctx:
                    pycross_patch.apply_patch_or_exit(self.root, self.write_patch(patch))
                self.assertIn("failed to parse patch file", str(ctx.exception))
        self.assertEqual(self.snapshot(), {"x.py": b"a\n"})

    def test_file_and_directory_conflicts_are_found_before_writing(self):
        self.write_tree({"existing.py": b"a\n"})
        patch = (
            H(b"existing.py", b"existing.py")
            + b"@@ -1 +1 @@\n-a\n+b\n"
            + b"--- /dev/null\n+++ b/foo\n@@ -0,0 +1 @@\n+f\n"
            + b"--- /dev/null\n+++ b/foo/bar.py\n@@ -0,0 +1 @@\n+g\n"
        )
        with self.assertRaisesRegex(pycross_patch.PatchError, "'foo' is a file"):
            self._apply(patch)
        self.assertEqual(self.snapshot(), {"existing.py": b"a\n"})

    def test_file_replaced_by_directory(self):
        self.write_tree({"foo": b"f\n"})
        patch = (
            b"diff --git a/foo b/foo\ndeleted file mode 100644\n--- a/foo\n+++ /dev/null\n@@ -1 +0,0 @@\n-f\n"
            b"diff --git a/foo/bar.py b/foo/bar.py\nnew file mode 100644\n--- /dev/null\n+++ b/foo/bar.py\n"
            b"@@ -0,0 +1 @@\n+g\n"
        )
        self._apply(patch)
        self.assertEqual(self.snapshot(), {"foo/bar.py": b"g\n"})

    def test_directory_replaced_by_file(self):
        self.write_tree({"foo/bar.py": b"g\n", "keep/x.py": b"x\n"})
        patch = (
            b"diff --git a/foo/bar.py b/foo/bar.py\ndeleted file mode 100644\n--- a/foo/bar.py\n+++ /dev/null\n"
            b"@@ -1 +0,0 @@\n-g\n"
            b"diff --git a/foo b/foo\nnew file mode 100644\n--- /dev/null\n+++ b/foo\n@@ -0,0 +1 @@\n+f\n"
        )
        self._apply(patch)
        self.assertEqual(self.snapshot(), {"foo": b"f\n", "keep/x.py": b"x\n"})

    def test_directory_with_remaining_files_blocks_file_creation(self):
        self.write_tree({"foo/a.py": b"a\n", "foo/b.py": b"b\n"})
        patch = b"--- a/foo/a.py\n+++ /dev/null\n@@ -1 +0,0 @@\n-a\n--- /dev/null\n+++ b/foo\n@@ -0,0 +1 @@\n+f\n"
        with self.assertRaisesRegex(pycross_patch.PatchError, "creates 'foo', which already exists"):
            self._apply(patch)

    def test_deleting_last_file_removes_empty_directory(self):
        self.write_tree({"pkg/sub/x.py": b"x\n", "pkg/y.py": b"y\n"})
        self._apply(b"--- a/pkg/sub/x.py\n+++ /dev/null\n@@ -1 +0,0 @@\n-x\n")
        self.assertFalse((self.root / "pkg/sub").exists())
        self.assertEqual(self.snapshot(), {"pkg/y.py": b"y\n"})

    def test_symlinks_inside_root_are_not_followed(self):
        self.write_tree({"target.py": b"a\n", "real/x.py": b"a\n"})
        os.symlink("target.py", self.root / "alias.py")
        os.symlink("real", self.root / "linkdir")
        with self.assertRaisesRegex(pycross_patch.PatchError, "'alias.py' is not a regular file"):
            self._apply(H(b"alias.py", b"alias.py") + b"@@ -1 +1 @@\n-a\n+b\n")
        with self.assertRaisesRegex(pycross_patch.PatchError, "beyond a symbolic link"):
            self._apply(H(b"linkdir/x.py", b"linkdir/x.py") + b"@@ -1 +1 @@\n-a\n+b\n")
        with self.assertRaisesRegex(pycross_patch.PatchError, "'alias.py' is not a regular file"):
            self._apply(b"diff --git a/alias.py b/alias.py\nold mode 100644\nnew mode 100755\n")
        self.assertEqual(self.snapshot()["target.py"], b"a\n")
        self.assertEqual(self.snapshot()["real/x.py"], b"a\n")

    def test_symlink_update_without_mode_lines_is_rejected(self):
        patch = b"diff --git a/lnk b/lnk\nindex 1111111..2222222 120000\n--- a/lnk\n+++ b/lnk\n@@ -1 +1 @@\n-t1\n+t2\n"
        with self.assertRaisesRegex(pycross_patch.PatchParseError, "only regular files"):
            self._apply(patch)

    def test_recreated_file_gets_the_new_mode(self):
        self.write_tree({"run.sh": b"old\n"})
        os.chmod(self.root / "run.sh", 0o755)
        patch = (
            b"diff --git a/run.sh b/run.sh\ndeleted file mode 100755\n--- a/run.sh\n+++ /dev/null\n"
            b"@@ -1 +0,0 @@\n-old\n"
            b"diff --git a/run.sh b/run.sh\nnew file mode 100644\n--- /dev/null\n+++ b/run.sh\n"
            b"@@ -0,0 +1 @@\n+new\n"
        )
        self._apply(patch)
        self.assertEqual(self.snapshot(), {"run.sh": b"new\n"})
        self.assertFalse(os.stat(self.root / "run.sh").st_mode & 0o111)

    def test_plain_diff_against_new_copy_patches_the_original(self):
        self.write_tree({"setup.py": b"a\n"})
        touched = self._apply(b"--- setup.py\t2026-01-01\n+++ setup.py.new\t2026-01-02\n@@ -1 +1 @@\n-a\n+b\n")
        self.assertEqual(touched, {"setup.py"})
        self.assertEqual(self.snapshot(), {"setup.py": b"b\n"})

    def test_git_header_name_edge_cases(self):
        self.assertEqual(pycross_patch._git_header_name(b"a//x.py b//x.py", 1, 1), b"x.py")
        self.assertIsNone(pycross_patch._git_header_name(b'"a/x" "b/x" extra', 1, 1))
        self.assertIsNone(pycross_patch._git_header_name(b'a/x "b/x" extra', 1, 1))
        self.assertEqual(pycross_patch._git_header_name(b'a/x "b/x"', 1, 1), b"x")

    def test_patches_read_only_file_preserving_mode(self):
        self.write_tree({"readonly.py": b"old = 1\n"})
        target = self.root / "readonly.py"
        os.chmod(target, 0o444)
        self.addCleanup(lambda: os.chmod(target, 0o644) if target.exists() else None)

        self._apply(H(b"readonly.py", b"readonly.py") + b"@@ -1 +1 @@\n-old = 1\n+new = 2\n")
        self.assertEqual(target.read_bytes(), b"new = 2\n")
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o444)

    def test_clean_path_rejects_dot_dot_before_strip_and_drive_after_strip(self):
        with self.assertRaisesRegex(pycross_patch.PatchError, "unsafe file name"):
            pycross_patch._clean_path(b"../x.py", strip=1, line_no=1)
        with self.assertRaisesRegex(pycross_patch.PatchError, "unsafe file name"):
            pycross_patch._clean_path(b"a/C:/Windows/x.py", strip=1, line_no=1)
        self.assertIsNone(pycross_patch._skip_components(b"../x.py", strip=1))


class GitExtendedHeaderTest(_TreeTestCase):
    def test_rename_keeps_mode_and_applies_hunks(self):
        self.write_tree({"old.sh": b"#!/bin/sh\necho old\n"})
        os.chmod(self.root / "old.sh", 0o755)
        patch = (
            b"diff --git a/old.sh b/bin/new.sh\nsimilarity index 80%\n"
            b"rename from old.sh\nrename to bin/new.sh\n"
            b"--- a/old.sh\n+++ b/bin/new.sh\n@@ -1,2 +1,2 @@\n #!/bin/sh\n-echo old\n+echo new\n"
        )
        touched = pycross_patch.apply_patch(self.root, self.write_patch(patch))
        self.assertEqual(touched, {"old.sh", "bin/new.sh"})
        self.assertEqual(self.snapshot(), {"bin/new.sh": b"#!/bin/sh\necho new\n"})
        self.assertTrue(os.stat(self.root / "bin/new.sh").st_mode & stat.S_IXUSR)

    def test_pure_rename_and_copy(self):
        self.write_tree({"a.py": b"A\n", "b.py": b"B\n"})
        patch = (
            b"diff --git a/a.py b/a2.py\nsimilarity index 100%\nrename from a.py\nrename to a2.py\n"
            b"diff --git a/b.py b/b2.py\nsimilarity index 100%\ncopy from b.py\ncopy to b2.py\n"
        )
        pycross_patch.apply_patch(self.root, self.write_patch(patch))
        self.assertEqual(self.snapshot(), {"a2.py": b"A\n", "b.py": b"B\n", "b2.py": b"B\n"})

    def test_rename_onto_existing_file_fails(self):
        self.write_tree({"a.py": b"A\n", "b.py": b"B\n"})
        patch = b"diff --git a/a.py b/b.py\nrename from a.py\nrename to b.py\n"
        with self.assertRaisesRegex(pycross_patch.PatchError, "renames to 'b.py', which already exists"):
            pycross_patch.apply_patch(self.root, self.write_patch(patch))

    def test_new_executable_file_and_mode_removal(self):
        self.write_tree({"tool.sh": b"x\n"})
        os.chmod(self.root / "tool.sh", 0o755)
        patch = (
            b"diff --git a/run.sh b/run.sh\nnew file mode 100755\n--- /dev/null\n+++ b/run.sh\n"
            b"@@ -0,0 +1 @@\n+echo\n"
            b"diff --git a/tool.sh b/tool.sh\nold mode 100755\nnew mode 100644\n"
        )
        pycross_patch.apply_patch(self.root, self.write_patch(patch))
        self.assertTrue(os.stat(self.root / "run.sh").st_mode & stat.S_IXUSR)
        self.assertFalse(os.stat(self.root / "tool.sh").st_mode & 0o111)

    def test_deleting_non_empty_file_without_hunks_fails(self):
        self.write_tree({"x.py": b"a\n"})
        patch = b"diff --git a/x.py b/x.py\ndeleted file mode 100644\n"
        with self.assertRaisesRegex(pycross_patch.PatchError, "doesn't remove all of its lines"):
            pycross_patch.apply_patch(self.root, self.write_patch(patch))

    def test_symlinks_and_submodules_are_rejected(self):
        for mode in (b"120000", b"160000"):
            with self.subTest(mode=mode):
                patch = b"diff --git a/l b/l\nnew file mode " + mode + b"\n--- /dev/null\n+++ b/l\n@@ -0,0 +1 @@\n+t\n"
                with self.assertRaisesRegex(pycross_patch.PatchParseError, "only regular files"):
                    pycross_patch.apply_patch(self.root, self.write_patch(patch))

    def test_quoted_names(self):
        self.write_tree({"tab\tname.py": b"a\n"})
        patch = b'diff --git "a/tab\\tname.py" "b/tab\\tname.py"\n--- "a/tab\\tname.py"\n+++ "b/tab\\tname.py"\n'
        patch += b"@@ -1 +1 @@\n-a\n+b\n"
        pycross_patch.apply_patch(self.root, self.write_patch(patch))
        self.assertEqual(self.snapshot(), {"tab\tname.py": b"b\n"})


# The patch_ng / pycross_patch / GNU patch comparison cases, applied the way pycross does
# (strip 0). Expected values are pycross_patch's results; the comment says how
# patch_ng (the previous pycross engine) and GNU patch 2.8 behaved.
COMPARISON_CASES = [
    # (name, files, patch, expected tree dict or error regex)
    ("01_basic_change", F, H(b"x.py", b"x.py") + b"@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n", {"x.py": b"a\nb\nC\nd\ne\n"}),
    # patch_ng, GNU: fail
    (
        "02_stale_context",
        {"x.py": b"x=1\ny=2\nz=3\n"},
        H(b"x.py", b"x.py") + b"@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n",
        "context mismatch",
    ),
    # patch_ng: fail (no offset search); GNU: applies at offset
    (
        "03_offset_drift",
        {"x.py": b"0\n1\na\nb\nc\nd\ne\n"},
        H(b"x.py", b"x.py") + b"@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n",
        {"x.py": b"0\n1\na\nb\nC\nd\ne\n"},
    ),
    # patch_ng: fail; GNU: applies with fuzz
    (
        "04_needs_fuzz",
        {"x.py": b"a\nB!\nc\nd\ne\n"},
        H(b"x.py", b"x.py") + b"@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n",
        "context mismatch",
    ),
    # patch_ng: same; GNU: fails
    (
        "05_crlf_file_lf_patch",
        {"x.py": b"a\r\nb\r\nc\r\n"},
        H(b"x.py", b"x.py") + b"@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n",
        {"x.py": b"a\r\nB\r\nc\r\n"},
    ),
    (
        "06_crlf_file_crlf_patch",
        {"x.py": b"a\r\nb\r\nc\r\n"},
        b"--- a/x.py\r\n+++ b/x.py\r\n@@ -1,3 +1,3 @@\r\n a\r\n-b\r\n+B\r\n c\r\n",
        {"x.py": b"a\r\nB\r\nc\r\n"},
    ),
    # patch_ng: inserts at the top (b"NEW\na\nb\n")
    ("07_u0_insertion", {"x.py": b"a\nb\n"}, H(b"x.py", b"x.py") + b"@@ -1,0 +2 @@\n+NEW\n", {"x.py": b"a\nNEW\nb\n"}),
    ("08_create_new_file", {}, b"--- /dev/null\n+++ b/new.py\n@@ -0,0 +1,2 @@\n+x\n+y\n", {"new.py": b"x\ny\n"}),
    # patch_ng: silently overwrites; GNU: fails
    (
        "09_create_over_existing",
        {"new.py": b"keep\n"},
        b"--- /dev/null\n+++ b/new.py\n@@ -0,0 +1 @@\n+x\n",
        "which already exists",
    ),
    ("10_delete_file", {"x.py": b"a\nb\n"}, b"--- a/x.py\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-a\n-b\n", {}),
    # patch_ng: deletes the whole file; GNU: fails
    (
        "11_partial_delete",
        {"x.py": b"a\nb\nc\n"},
        b"--- a/x.py\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-a\n-b\n",
        "doesn't remove all of its lines",
    ),
    # patch_ng: writes ../evil.txt inside the root as evil.txt; GNU: refuses
    (
        "12_path_traversal",
        {"x.py": b"a\n"},
        b"--- /dev/null\n+++ b/../evil.txt\n@@ -0,0 +1 @@\n+pwn\n",
        "unsafe file name",
    ),
    # patch_ng: writes tmp/evil.txt inside the root; GNU: refuses
    (
        "13_absolute_path",
        {"x.py": b"a\n"},
        b"--- /dev/null\n+++ /tmp/evil.txt\n@@ -0,0 +1 @@\n+pwn\n",
        "unsafe file name",
    ),
    (
        "14_format_patch_preamble_and_signature",
        F,
        b"From 0123 Mon Sep 17 00:00:00 2001\nSubject: [PATCH] u\n\nmsg\n---\n x.py | 2 +-\n\n"
        b"diff --git a/x.py b/x.py\nindex 1..2 100644\n"
        + H(b"x.py", b"x.py")
        + b"@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n-- \n2.40\n",
        {"x.py": b"a\nb\nC\nd\ne\n"},
    ),
    (
        "15_git_show_indented_message",
        F,
        b"commit abc\nAuthor: x\n\n    - bullet\n    + plus\n\ndiff --git a/x.py b/x.py\n"
        + H(b"x.py", b"x.py")
        + b"@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n",
        {"x.py": b"a\nb\nC\nd\ne\n"},
    ),
    # patch_ng: ignores the marker and writes b"a\nB\n"
    (
        "16_no_newline_at_eof",
        {"x.py": b"a\nb"},
        H(b"x.py", b"x.py")
        + b"@@ -1,2 +1,2 @@\n a\n-b\n\\ No newline at end of file\n+B\n\\ No newline at end of file\n",
        {"x.py": b"a\nB"},
    ),
    # all three fail; patch_ng and GNU patch leave x.py patched, pycross_patch writes nothing
    (
        "17_second_file_stale",
        {"x.py": b"a\nb\n", "y.py": b"q\n"},
        H(b"x.py", b"x.py") + b"@@ -1,2 +1,2 @@\n a\n-b\n+B\n" + H(b"y.py", b"y.py") + b"@@ -1 +1 @@\n-zzz\n+Z\n",
        "failed to apply to y.py",
    ),
    # patch_ng: skips the binary section and applies the rest; GNU: fails
    (
        "18_binary_patch_marker",
        F,
        b"diff --git a/x.bin b/x.bin\nGIT binary patch\nliteral 3\nKcmZ?\n\n"
        + H(b"x.py", b"x.py")
        + b"@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n",
        "binary patches are not supported",
    ),
    # patch_ng, GNU: rename x.py -> y.py
    (
        "19_rename",
        {"x.py": b"a\n"},
        b"diff --git a/x.py b/y.py\nsimilarity index 100%\nrename from x.py\nrename to y.py\n",
        {"y.py": b"a\n"},
    ),
    (
        "20_empty_context_line_without_space",
        {"x.py": b"a\n\nc\n"},
        H(b"x.py", b"x.py") + b"@@ -1,3 +1,3 @@\n a\n\n-c\n+C\n",
        {"x.py": b"a\n\nC\n"},
    ),
    (
        "21_removed_line_starting_with_dashes",
        {"x.py": b"a\n-- sql\nc\n"},
        H(b"x.py", b"x.py") + b"@@ -1,3 +1,2 @@\n a\n--- sql\n c\n",
        {"x.py": b"a\nc\n"},
    ),
    (
        "22_non_utf8_content",
        {"x.py": b"a\n\xff\xfe\nc\n"},
        H(b"x.py", b"x.py") + b"@@ -1,3 +1,3 @@\n a\n-\xff\xfe\n+ok\n c\n",
        {"x.py": b"a\nok\nc\n"},
    ),
    # pycross strip 0 + git-style headers -> strip 1 (patch_ng: same; GNU -p0: fails)
    (
        "23_strip0_git_style",
        F,
        H(b"x.py", b"x.py") + b"@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n",
        {"x.py": b"a\nb\nC\nd\ne\n"},
    ),
    # patch_ng, GNU: ignore the extra line
    (
        "24_extra_body_line_past_hunk_count",
        F,
        H(b"x.py", b"x.py") + b"@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n+EXTRA\n",
        "after the end of the hunk",
    ),
    # all three fail
    (
        "25_out_of_order_hunks",
        {"x.py": b"".join(b"%d\n" % i for i in range(1, 15))},
        H(b"x.py", b"x.py") + b"@@ -10,3 +10,3 @@\n 10\n-11\n+X\n 12\n@@ -2,3 +2,3 @@\n 2\n-3\n+Y\n 4\n",
        "context mismatch",
    ),
]


class ComparisonCasesTest(_TreeTestCase):
    def test_cases(self):
        for name, files, patch, expected in COMPARISON_CASES:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as case_tmp:
                case_tmp = Path(case_tmp)
                root = case_tmp / "root"
                root.mkdir()
                self.write_tree(files, root=root)
                pf = case_tmp / "case.patch"
                pf.write_bytes(patch)
                if isinstance(expected, str):
                    with self.assertRaisesRegex(pycross_patch.PatchError, expected):
                        pycross_patch.apply_patch(root, pf)
                    self.assertFalse((case_tmp / "evil.txt").exists())
                else:
                    pycross_patch.apply_patch(root, pf)
                    self.assertEqual(self.snapshot(root), expected)


if __name__ == "__main__":
    unittest.main()
