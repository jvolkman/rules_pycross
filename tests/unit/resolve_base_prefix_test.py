"""Tests for resolve_base_prefix in venv_utils.

Covers the installed_base / installed_platbase resolution logic including
the .exists() fallback for copied Python outputs (PR #242 regression fix).
"""

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from pycross.private.build.tools.utils.venv_utils import resolve_base_prefix


class ResolveBasePrefixTest(unittest.TestCase):
    """Unit tests for resolve_base_prefix()."""

    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.tmp = Path(self.temp_dir.name)
        # Simulate a sandbox layout:
        #   /tmp/xxx/sandbox/execroot/_main/  (prefix)
        #   /tmp/xxx/sandbox/execroot/_main/bazel-out/.../bin/python3  (target_python)
        self.prefix = self.tmp / "sandbox" / "execroot" / "_main"
        self.prefix.mkdir(parents=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    # ── installed_base exists on disk ─────────────────────────────────────

    def test_installed_base_exists_returns_it(self):
        """When installed_base points to a real directory, use it directly."""
        installed_dir = self.prefix / "bazel-out" / "k8" / "bin" / "python_root"
        installed_dir.mkdir(parents=True)
        target_python = self.prefix / "bazel-out" / "k8" / "bin" / "wrapper" / "bin" / "python3"

        result = resolve_base_prefix(
            installed_value=str(installed_dir),
            target_python=target_python,
            prefix=self.prefix,
        )

        self.assertEqual(result, installed_dir)

    # ── installed_base is stale (doesn't exist) ───────────────────────────

    def test_stale_installed_base_falls_back_to_grandparent(self):
        """Regression test for PR #242: copied Python outputs have stale
        installed_base in sysconfig.  Should fall back to target_python
        grandparent when the sysconfig path doesn't exist on disk."""
        stale_path = str(self.prefix / "bazel-out" / "k8" / "bin" / "original_root")
        # Intentionally NOT creating stale_path on disk.

        target_python = self.prefix / "bazel-out" / "k8" / "bin" / "copied" / "bin" / "python3"

        result = resolve_base_prefix(
            installed_value=stale_path,
            target_python=target_python,
            prefix=self.prefix,
        )

        self.assertEqual(result, target_python.parent.parent)

    def test_stale_installed_base_returns_none_when_python_outside_prefix(self):
        """When installed_base is stale AND target_python is not under prefix
        (e.g. system python), result should be None."""
        stale_path = str(self.prefix / "bazel-out" / "k8" / "bin" / "no_such_dir")
        target_python = Path("/usr/bin/python3")

        result = resolve_base_prefix(
            installed_value=stale_path,
            target_python=target_python,
            prefix=self.prefix,
        )

        self.assertIsNone(result)

    # ── no installed_base at all ──────────────────────────────────────────

    def test_no_installed_base_falls_back_to_grandparent(self):
        """When sysconfig has no installed_base, use the target_python
        grandparent heuristic (python3 -> bin -> python_root)."""
        target_python = self.prefix / "external" / "python_3_13" / "bin" / "python3.13"

        result = resolve_base_prefix(
            installed_value=None,
            target_python=target_python,
            prefix=self.prefix,
        )

        self.assertEqual(result, self.prefix / "external" / "python_3_13")

    def test_no_installed_base_returns_none_for_system_python(self):
        """When there's no installed_base and target_python is system python
        (not under prefix), result should be None."""
        target_python = Path("/usr/local/bin/python3")

        result = resolve_base_prefix(
            installed_value=None,
            target_python=target_python,
            prefix=self.prefix,
        )

        self.assertIsNone(result)

    # ── empty string installed_base ───────────────────────────────────────

    def test_empty_string_treated_as_missing(self):
        """An empty string installed_base should behave like None."""
        target_python = self.prefix / "external" / "python_3_13" / "bin" / "python3"

        result = resolve_base_prefix(
            installed_value="",
            target_python=target_python,
            prefix=self.prefix,
        )

        # Empty string is falsy, so should fall back to grandparent.
        self.assertEqual(result, self.prefix / "external" / "python_3_13")

    # ── installed_base exists but is outside prefix ───────────────────────

    def test_installed_base_outside_prefix_still_used_if_exists(self):
        """An installed_base outside the sandbox is valid if it exists
        (e.g. system Python with real sysconfig)."""
        real_dir = self.tmp / "usr" / "lib" / "python3.13"
        real_dir.mkdir(parents=True)
        target_python = Path("/usr/bin/python3")

        result = resolve_base_prefix(
            installed_value=str(real_dir),
            target_python=target_python,
            prefix=self.prefix,
        )

        self.assertEqual(result, real_dir)

    def test_installed_base_via_bazel_execroot_symlink(self):
        """When installed_base is accessed via a bazel-execroot symlink (as done during wheel builds),
        it should be resolved to the real absolute path within the prefix."""
        # Create the actual directory
        installed_dir = self.prefix / "bazel-out" / "k8" / "bin" / "python_root"
        installed_dir.mkdir(parents=True)

        # Create a sdist-like temp dir and a bazel-execroot symlink
        sdist_dir = self.tmp / "sdist"
        sdist_dir.mkdir(parents=True)
        bazel_execroot = self.tmp / "bazel-execroot"
        bazel_execroot.symlink_to(self.prefix.parent)

        # The path from sysconfig might look like this
        symlink_path = sdist_dir / ".." / "bazel-execroot" / "_main" / "bazel-out" / "k8" / "bin" / "python_root"
        target_python = self.prefix / "bazel-out" / "k8" / "bin" / "wrapper" / "bin" / "python3"

        result = resolve_base_prefix(
            installed_value=str(symlink_path),
            target_python=target_python,
            prefix=self.prefix,
        )

        # It should resolve to the real installed_dir
        self.assertEqual(result, installed_dir)


if __name__ == "__main__":
    unittest.main()
