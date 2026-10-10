"""Verify optional .pyc precompilation for installed wheels."""

import importlib
import importlib.util
import os
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True


class PrecompileTest(unittest.TestCase):
    """Check whether installed wheel modules have precompiled .pyc files."""

    def test_precompiled_bytecode(self):
        expect_precompile = os.environ.get("EXPECTED_PRECOMPILE") == "1"
        expected_tag = os.environ.get("EXPECTED_PYC_TAG")
        # tests/e2e/shared/.bazelrc.common sets `common -c opt`, which defaults to
        # unchecked_hash (0b01); `-c fastbuild` uses checked_hash (0b11).
        expected_flags = int(os.environ.get("EXPECTED_PYC_FLAGS", str(0b01)))
        if expected_tag:
            self.assertEqual(sys.implementation.cache_tag, expected_tag)

        # python-dateutil has package(precompile = "enabled"), so it is precompiled
        # even when --@rules_python//python/config_settings:precompile is at its
        # default ("auto"). pygments uses the default ("auto") and follows the flag.
        cases = [
            ("dateutil", True),
            ("pygments", expect_precompile),
        ]
        for mod_name, should_be_precompiled in cases:
            with self.subTest(module=mod_name, should_be_precompiled=should_be_precompiled):
                spec = importlib.util.find_spec(mod_name)
                self.assertIsNotNone(spec, f"{mod_name} spec not found")
                self.assertIsNotNone(spec.origin, f"{mod_name} has no origin")
                pyc_path = Path(importlib.util.cache_from_source(spec.origin))

                if not should_be_precompiled:
                    self.assertFalse(
                        pyc_path.exists(),
                        f"Expected no precompiled .pyc by default, found {pyc_path}",
                    )
                    mod = importlib.import_module(mod_name)
                    self.assertIsNotNone(mod)
                    continue

                self.assertTrue(
                    pyc_path.is_file(),
                    f"Expected precompiled .pyc to exist before import: {pyc_path}",
                )
                if expected_tag:
                    self.assertIn(f".{expected_tag}.pyc", pyc_path.name)

                data = pyc_path.read_bytes()
                self.assertEqual(data[:4], importlib.util.MAGIC_NUMBER)
                self.assertEqual(int.from_bytes(data[4:8], "little"), expected_flags)
                self.assertEqual(
                    data[8:16],
                    importlib.util.source_hash(Path(spec.origin).read_bytes()),
                )

                mod = importlib.import_module(mod_name)
                self.assertIsNotNone(mod)


if __name__ == "__main__":
    unittest.main()
