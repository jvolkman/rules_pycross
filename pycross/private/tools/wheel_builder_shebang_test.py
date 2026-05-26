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


if __name__ == "__main__":
    unittest.main()
