"""Tests for pycross's patch wrapper and the vendored rules_python unified-diff engine."""

import os
import re
import stat
import tempfile
import unittest
from pathlib import Path

import pycross_patch
import unified_patch

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
    """pycross keeps patch_ng's strip-0 handling of git-style a/ b/ prefixes."""

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
        # patch_ng only stripped a/ b/ when the literal path was missing. The wrapper strips
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
        with self.assertRaisesRegex(pycross_patch.PatchParseError, "No valid unified diff hunks"):
            pycross_patch.apply_patch(self.root, self.write_patch(b"not a patch\n"))
        with self.assertRaisesRegex(pycross_patch.PatchParseError, "Unsupported binary or rename/copy"):
            pycross_patch.apply_patch(
                self.root, self.write_patch(b"diff --git a/x.py b/y.py\nrename from x.py\nrename to y.py\n")
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
            str(ctx.exception), r"^error: failed to parse patch file: //:bad\.patch: No valid unified diff"
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
        # patch_ng and the engine both apply it, which the e2e test relies on.
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


class UpstreamEngineTest(_TreeTestCase):
    """Behavior tests ported from rules_python's wheel_layout_and_installer_test.py (engine, explicit strip)."""

    def test_stale_context_then_crlf_preservation(self):
        target = self.root / "pkg/mod.py"
        target.parent.mkdir(parents=True)
        target.write_bytes(b"line1 = 1\r\nline2 = 'changed'\r\n")
        stale_patch = self.write_patch(
            b"--- a/pkg/mod.py\n+++ b/pkg/mod.py\n@@ -1,2 +1,2 @@\n line1 = 1\n-line2 = 'expected'\n+line2 = 'patched'\n"
        )
        with self.assertRaisesRegex(ValueError, "context mismatch"):
            unified_patch.apply_unified_patch(self.root, stale_patch, strip=1)

        target.write_bytes(b"line1 = 1\r\nline2 = 'expected'\r\n")
        touched = unified_patch.apply_unified_patch(self.root, stale_patch, strip=1)
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
                "attempts to create existing file",
            ),
            (
                "partial_delete",
                {"pkg/d.py": b"1\n2\n"},
                b"--- a/pkg/d.py\n+++ /dev/null\n@@ -1,1 +0,0 @@\n-1\n",
                1,
                "did not consume entire file",
            ),
            (
                "out_of_order_hunks",
                {"pkg/o.py": b"1\n2\n3\n"},
                b"--- a/pkg/o.py\n+++ b/pkg/o.py\n@@ -3,1 +3,1 @@\n-3\n+three\n@@ -1,1 +1,1 @@\n-1\n+one\n",
                1,
                "context mismatch",
            ),
            (
                "traversal",
                {},
                b"--- /dev/null\n+++ b/../../escape.py\n@@ -0,0 +1 @@\n+x = 1\n",
                1,
                "escapes root",
            ),
            (
                "abs_path",
                {},
                b"--- /dev/null\n+++ /abs/escape.py\n@@ -0,0 +1 @@\n+x = 1\n",
                0,
                "Unsafe patch path",
            ),
            (
                "binary_patch",
                {},
                b"GIT binary patch\nliteral 0\n",
                1,
                "Unsupported binary or rename/copy",
            ),
            (
                "rename_directive",
                {},
                b"rename from a/x.py\nrename to b/y.py\n",
                1,
                "Unsupported binary or rename/copy",
            ),
            (
                "orphan_hunk_before_header",
                {},
                b"@@ -1,1 +1,1 @@\n-a\n+b\n",
                1,
                "Hunk without preceding",
            ),
            (
                "stray_body_line",
                {"pkg/s.py": b"a\n"},
                b"--- a/pkg/s.py\n+++ b/pkg/s.py\n@@ -1,1 +1,1 @@\nSTRAY\n",
                1,
                "Malformed hunk line",
            ),
            (
                "strip_0_is_literal",
                {"x.py": b"a\n"},
                b"--- a/x.py\n+++ b/x.py\n@@ -1 +1 @@\n-a\n+b\n",
                0,
                "targets non-existent file 'b/x.py'",
            ),
        ]:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as case_tmp:
                case_root = Path(case_tmp)
                self.write_tree(init_files, root=case_root)
                pf = case_root / "case.patch"
                pf.write_bytes(patch_bytes)
                if isinstance(expected, str):
                    with self.assertRaisesRegex(ValueError, expected):
                        unified_patch.apply_unified_patch(case_root, pf, strip=strip)
                else:
                    unified_patch.apply_unified_patch(case_root, pf, strip=strip)
                    for rel, exp_bytes in expected.items():
                        self.assertEqual((case_root / rel).read_bytes(), exp_bytes)


# The patch_ng / engine / GNU patch comparison cases, applied the way pycross does
# (wrapper, strip 0). Expected values are the engine's results; the comment says how
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
        "attempts to create existing file",
    ),
    ("10_delete_file", {"x.py": b"a\nb\n"}, b"--- a/x.py\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-a\n-b\n", {}),
    # patch_ng: deletes the whole file; GNU: fails
    (
        "11_partial_delete",
        {"x.py": b"a\nb\nc\n"},
        b"--- a/x.py\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-a\n-b\n",
        "did not consume entire file",
    ),
    # patch_ng: writes ../evil.txt inside the root as evil.txt; GNU: refuses
    ("12_path_traversal", {"x.py": b"a\n"}, b"--- /dev/null\n+++ b/../evil.txt\n@@ -0,0 +1 @@\n+pwn\n", "escapes root"),
    # patch_ng: writes tmp/evil.txt inside the root; GNU: refuses
    (
        "13_absolute_path",
        {"x.py": b"a\n"},
        b"--- /dev/null\n+++ /tmp/evil.txt\n@@ -0,0 +1 @@\n+pwn\n",
        "Unsafe patch path",
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
    # all three fail (none is atomic across files)
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
        "Unsupported binary or rename/copy",
    ),
    # patch_ng, GNU: rename x.py -> y.py
    (
        "19_rename",
        {"x.py": b"a\n"},
        b"diff --git a/x.py b/y.py\nsimilarity index 100%\nrename from x.py\nrename to y.py\n",
        "Unsupported binary or rename/copy",
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
        "Unexpected diff body line outside hunk",
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
