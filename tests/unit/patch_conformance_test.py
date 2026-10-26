"""Conformance tests for pycross_patch, using fixtures from two other patch libraries.

`testdata/patch_conformance` holds unmodified fixtures from:

- diffy (https://github.com/bmwill/diffy, `tests/compat`): each case is a
  directory with `in/foo.patch`, the files it applies to, and the expected
  `out/` files, checked against `git apply` or GNU patch.
- go-gitdiff (https://github.com/bluekeyes/go-gitdiff, `gitdiff/testdata/apply`):
  each case is `<name>.patch` with a `.src` input and an `.out` result.

File names are percent-encoded; see `import_fixtures.py` there.

Where pycross deliberately differs from the upstream expectation, the tables
below say so.
"""

import os
import re
import shutil
import tempfile
import unittest
import urllib.parse
from pathlib import Path

import pycross_patch

TESTDATA = Path(__file__).resolve().parent / "testdata" / "patch_conformance"

BINARY = "binary patches are not supported"
CONTEXT = "context mismatch"

# The strip level for each diffy case, from diffy's tests/compat/*/mod.rs. Most git cases
# use 1 and most GNU patch cases use 0.
DIFFY_STRIP = {
    "git": (1, {"path_no_prefix": 0}),
    "gnu_patch": (0, {"create_empty_file_gitdiff": 1, "format_patch_mbox": 1, "nested_diff_signature": 1}),
}

# diffy cases that must fail, with the expected error.
DIFFY_FAILURES = {
    ("git", "fail_ambiguous_suffix_tie"): "can't find the file name",  # git fails too; diffy guesses.
    ("git", "fail_both_devnull"): "both file names are /dev/null",
    ("git", "fail_prefix_no_slash"): "can't strip 1 components",
    # git fails too. GNU patch and diffy skip the junk and apply the second hunk.
    ("git", "junk_between_hunks"): "hunk has no '--- '/'\\+\\+\\+ ' file header",
    ("gnu_patch", "junk_between_hunks"): "hunk has no '--- '/'\\+\\+\\+ ' file header",
    ("gnu_patch", "fail_both_devnull"): "both file names are /dev/null",
    ("gnu_patch", "fail_context_mismatch"): CONTEXT,
    ("gnu_patch", "fail_hunk_not_found"): CONTEXT,
    ("gnu_patch", "fail_truncated_file"): CONTEXT,
    ("gnu_patch", "no_hunk"): "file header has no hunks",  # GNU patch fails too; diffy creates the file.
}

# Expected results for diffy cases that diffy expects to fail, but pycross applies.
DIFFY_EXTRA_RESULTS = {
    # A git-style empty file. `git apply` creates it; diffy's GNU patch mode doesn't.
    ("gnu_patch", "create_empty_file_gitdiff"): {"empty.txt": b""},
    # A CRLF patch for an LF file. GNU patch applies it too; diffy refuses.
    ("gnu_patch", "crlf_patch_lf_file"): {"file.txt": b"line1\nchanged\nline3\n"},
}

# diffy writes a deleted file to `out/` as an empty file. pycross removes it.
DIFFY_DELETED = {
    ("git", "nested_diff_signature"): ["mir-test.diff"],
    ("gnu_patch", "nested_diff_signature"): ["mir-test.diff"],
    ("gnu_patch", "delete_file"): ["file.txt"],
}

# go-gitdiff cases that must fail, with the expected error.
GO_GITDIFF_FAILURES = {
    "file_bin_modify": BINARY,
    "file_text_error_partial_delete": "doesn't remove all of its lines",
    "text_fragment_error_context_conflict": CONTEXT,
    "text_fragment_error_delete_conflict": CONTEXT,
    "text_fragment_error_overflow": CONTEXT,
    "text_fragment_error_short_src": CONTEXT,
    "text_fragment_error_short_src_before": CONTEXT,
    "text_fragment_error_short_src_extreme": CONTEXT,
}

# go-gitdiff and `git apply` reject an `@@ -0,0 +1,3 @@` hunk for a non-empty file.
# pycross follows GNU patch and inserts the lines at the top, like any other `-U0` hunk.
GO_GITDIFF_INSERT_AT_TOP = {"text_fragment_error_new_file"}


def _decode(name: str) -> str:
    return os.fsdecode(urllib.parse.unquote_to_bytes(name))


def _copy_tree(src: Path, dst: Path, skip=()) -> None:
    for child in src.iterdir():
        if child.name in skip:
            continue
        target = dst / _decode(child.name)
        if child.is_dir():
            target.mkdir()
            _copy_tree(child, target)
        else:
            shutil.copyfile(child, target)


def _snapshot(root: Path) -> dict:
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}


class _ConformanceTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def new_dir(self, name: str) -> Path:
        path = Path(tempfile.mkdtemp(prefix=name + ".", dir=self.tmp))
        return path

    def assert_fails_cleanly(self, root: Path, patch: Path, strip: int, error: str) -> None:
        before = _snapshot(root)
        with self.assertRaisesRegex(pycross_patch.PatchError, error):
            pycross_patch.apply_patch(root, patch, strip)
        self.assertEqual(_snapshot(root), before, "a failed patch changed the tree")


class DiffyCompatTest(_ConformanceTestCase):
    def _cases(self):
        for suite in ("git", "gnu_patch"):
            for case in sorted((TESTDATA / "diffy" / suite).iterdir()):
                yield suite, case

    def test_tables_name_real_cases(self):
        names = {(suite, case.name) for suite, case in self._cases()}
        for key in [*DIFFY_FAILURES, *DIFFY_EXTRA_RESULTS, *DIFFY_DELETED]:
            self.assertIn(key, names)
        for suite, (_, overrides) in DIFFY_STRIP.items():
            for name in overrides:
                self.assertIn((suite, name), names)

    def test_cases(self):
        for suite, case in self._cases():
            key = (suite, case.name)
            default_strip, overrides = DIFFY_STRIP[suite]
            strip = overrides.get(case.name, default_strip)
            with self.subTest(suite=suite, case=case.name):
                root = self.new_dir(case.name)
                _copy_tree(case / "in", root, skip=("foo.patch",))
                patch = case / "in" / "foo.patch"

                if case.name.startswith("binary_"):
                    self.assert_fails_cleanly(root, patch, strip, BINARY)
                    continue
                if key in DIFFY_FAILURES:
                    self.assert_fails_cleanly(root, patch, strip, DIFFY_FAILURES[key])
                    continue

                pycross_patch.apply_patch(root, patch, strip)
                if key in DIFFY_EXTRA_RESULTS:
                    expected = DIFFY_EXTRA_RESULTS[key]
                else:
                    expected_dir = self.new_dir(case.name + ".out")
                    _copy_tree(case / "out", expected_dir)
                    expected = _snapshot(expected_dir)
                actual = _snapshot(root)
                for rel in DIFFY_DELETED.get(key, []):
                    self.assertEqual(expected.pop(rel), b"")
                    self.assertNotIn(rel, actual)
                for rel, content in expected.items():
                    self.assertEqual(actual.get(rel), content, rel)


class GoGitdiffApplyTest(_ConformanceTestCase):
    DIR = TESTDATA / "go_gitdiff"

    def _source(self, name: str) -> Path:
        # Error cases share a source file, as in go-gitdiff's apply_test.go.
        for prefix in ("text_fragment_error", "file_text"):
            if name.startswith(prefix + "_"):
                return self.DIR / f"{prefix}.src"
        return self.DIR / f"{name}.src"

    def test_tables_name_real_cases(self):
        names = {p.stem for p in self.DIR.glob("*.patch")}
        for name in [*GO_GITDIFF_FAILURES, *GO_GITDIFF_INSERT_AT_TOP]:
            self.assertIn(name, names)

    def test_cases(self):
        for patch in sorted(self.DIR.glob("*.patch")):
            name = patch.stem
            with self.subTest(case=name):
                old, new = re.search(rb"^diff --git a/(\S+) b/(\S+)$", patch.read_bytes(), re.M).groups()
                old, new = old.decode(), new.decode()
                root = self.new_dir(name)
                (root / old).parent.mkdir(parents=True)
                src = self._source(name).read_bytes()
                (root / old).write_bytes(src)

                if name in GO_GITDIFF_FAILURES:
                    self.assert_fails_cleanly(root, patch, 1, GO_GITDIFF_FAILURES[name])
                    continue

                pycross_patch.apply_patch(root, patch, 1)
                if name in GO_GITDIFF_INSERT_AT_TOP:
                    self.assertEqual((root / new).read_bytes(), b"line 1\nline 2\nline 3\n" + src)
                    continue
                expected = (self.DIR / f"{name}.out").read_bytes()
                if name == "file_text_delete":
                    self.assertEqual(expected, b"")
                    self.assertFalse((root / new).exists())
                    continue
                actual = (root / new).read_bytes()
                if name.startswith("text_fragment_"):
                    # go-gitdiff applies one fragment and stops writing after it, so `.out`
                    # ends where the hunk ends.
                    self.assertTrue(actual.startswith(expected), (actual, expected))
                else:
                    self.assertEqual(actual, expected)
                if name == "file_mode_change":
                    self.assertTrue(os.access(root / new, os.X_OK))


if __name__ == "__main__":
    unittest.main()
