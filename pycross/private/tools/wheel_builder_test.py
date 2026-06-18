import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from pycross.private.tools import wheel_builder


class WheelBuilderShebangTest(unittest.TestCase):
    def test_darwin_script_python_uses_env(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            python_exe = Path(tmp) / "python_wrapper"
            python_exe.write_bytes(b'#!/bin/sh\nexec python3 "$@"\n')

            with mock.patch.object(wheel_builder.sys, "platform", "darwin"):
                shebang = wheel_builder._python_wrapper_shebang(python_exe)

            self.assertEqual(shebang, f"#!/usr/bin/env {python_exe.absolute()}")

    def test_darwin_non_script_python_uses_direct_shebang(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            python_exe = Path(tmp) / "python"
            python_exe.write_bytes(b"\xcf\xfa\xed\xfe")

            with mock.patch.object(wheel_builder.sys, "platform", "darwin"):
                shebang = wheel_builder._python_wrapper_shebang(python_exe)

            self.assertEqual(shebang, f"#!{python_exe.absolute()}")

    def test_linux_script_python_uses_direct_shebang(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            python_exe = Path(tmp) / "python_wrapper"
            python_exe.write_bytes(b'#!/bin/sh\nexec python3 "$@"\n')

            with mock.patch.object(wheel_builder.sys, "platform", "linux"):
                shebang = wheel_builder._python_wrapper_shebang(python_exe)

            self.assertEqual(shebang, f"#!{python_exe.absolute()}")

    def test_missing_python_uses_direct_shebang(self) -> None:
        python_exe = Path("/missing/python_wrapper")

        with mock.patch.object(wheel_builder.sys, "platform", "darwin"):
            shebang = wheel_builder._python_wrapper_shebang(python_exe)

        self.assertEqual(shebang, f"#!{python_exe.absolute()}")


class WheelBuilderPathTest(unittest.TestCase):
    def test_execroot_relative_path_rewrites_execroot_path(self) -> None:
        execroot = Path("/tmp/sandbox/execroot/_main")
        prefix = Path("..") / "bazel-execroot" / "_main"
        path = Path("/tmp/sandbox/execroot/_main/bazel-out/k8-fastbuild/bin/pkg/python_root")

        self.assertEqual(
            wheel_builder.execroot_relative_path(path, execroot, prefix),
            Path("../bazel-execroot/_main/bazel-out/k8-fastbuild/bin/pkg/python_root"),
        )

    def test_execroot_relative_path_rejects_outside_execroot_path(self) -> None:
        execroot = Path("/tmp/sandbox/execroot/_main")
        prefix = Path("..") / "bazel-execroot" / "_main"
        path = Path("/tmp/output_base/external/rules_python++python+python_3_13_x86_64-unknown-linux-gnu")

        self.assertEqual(
            wheel_builder.execroot_relative_path(path, execroot, prefix),
            None,
        )

    def test_execroot_relative_path_rewrites_output_base_execroot_path(self) -> None:
        execroot = Path("/tmp/sandbox/execroot/_main")
        prefix = Path("..") / "bazel-execroot" / "_main"
        path = Path("/tmp/output_base/execroot/_main/bazel-out/k8-fastbuild/bin/pkg/python_root")

        self.assertEqual(
            wheel_builder.execroot_relative_path(path, execroot, prefix),
            Path("../bazel-execroot/_main/bazel-out/k8-fastbuild/bin/pkg/python_root"),
        )

    def test_execroot_relative_path_rewrites_temp_bazel_execroot_path(self) -> None:
        execroot = Path("/tmp/sandbox/execroot/_main")
        prefix = Path("..") / "bazel-execroot" / "_main"
        path = Path("/tmp/wheelbuild/sdist/../bazel-execroot/_main/bazel-out/k8-fastbuild/bin/pkg/python_root")

        self.assertEqual(
            wheel_builder.execroot_relative_path(path, execroot, prefix),
            Path("../bazel-execroot/_main/bazel-out/k8-fastbuild/bin/pkg/python_root"),
        )

    def test_target_base_prefixes_use_installed_base(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            execroot = tmp_path / "sandbox/execroot/_main"
            sdist_dir = tmp_path / "sdist"
            sdist_dir.mkdir()
            prefix = Path("..") / "bazel-execroot" / "_main"
            installed_base = "bazel-out/k8-fastbuild/bin/pkg/python_root"
            (sdist_dir / prefix / installed_base).mkdir(parents=True)
            target_python_exe = prefix / "bazel-out/k8-fastbuild/bin/pkg/python_wrapper"
            target_sysconfig_vars = {
                "installed_base": str(execroot / installed_base),
                "installed_platbase": str(execroot / installed_base),
            }

            cwd = Path.cwd()
            try:
                os.chdir(sdist_dir)
                base_prefix, base_exec_prefix = wheel_builder.target_base_prefixes(
                    target_sysconfig_vars,
                    target_python_exe,
                    execroot,
                    prefix,
                )
            finally:
                os.chdir(cwd)

        expected = Path("../bazel-execroot/_main") / installed_base
        self.assertEqual(base_prefix, expected)
        self.assertEqual(base_exec_prefix, expected)

    def test_target_base_prefixes_falls_back_to_python_grandparent(self) -> None:
        execroot = Path("/tmp/sandbox/execroot/_main")
        prefix = Path("..") / "bazel-execroot" / "_main"
        target_python_exe = prefix / "external/python_3_13/bin/python3.13"

        base_prefix, base_exec_prefix = wheel_builder.target_base_prefixes(
            {},
            target_python_exe,
            execroot,
            prefix,
        )

        self.assertEqual(base_prefix, prefix / "external/python_3_13")
        self.assertEqual(base_exec_prefix, prefix / "external/python_3_13")

    def test_target_base_prefixes_falls_back_for_outside_execroot_installed_base(self) -> None:
        execroot = Path("/tmp/sandbox/execroot/_main")
        prefix = Path("..") / "bazel-execroot" / "_main"
        target_python_exe = prefix / "external/python_3_13/bin/python3.13"
        target_sysconfig_vars = {
            "installed_base": ("/tmp/output_base/external/rules_python++python+python_3_13_x86_64-unknown-linux-gnu"),
        }

        base_prefix, base_exec_prefix = wheel_builder.target_base_prefixes(
            target_sysconfig_vars,
            target_python_exe,
            execroot,
            prefix,
        )

        self.assertEqual(base_prefix, prefix / "external/python_3_13")
        self.assertEqual(base_exec_prefix, prefix / "external/python_3_13")


if __name__ == "__main__":
    unittest.main()
