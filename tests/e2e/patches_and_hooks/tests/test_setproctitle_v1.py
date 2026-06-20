import os
import unittest

import setproctitle


class TestSetproctitleV1(unittest.TestCase):
    def test_v1_compat_variables(self):
        # 1. Verify build_env variables were passed and expanded
        self.assertEqual(getattr(setproctitle, "V1_CUSTOM_VAR", None), "hello_from_build_env")

        # 2. Verify data file was available and read
        self.assertEqual(getattr(setproctitle, "V1_DATA_CONTENT", None), "v1_compat_data_marker_v2")

        # 3. Verify pre_build_hook modified build env and setup.py saw it
        self.assertEqual(getattr(setproctitle, "V1_PRE_HOOK_MARKER", None), "pre_hook_was_here")

        # 3b. Verify path_tools renaming works and the tool is on PATH
        self.assertTrue(getattr(setproctitle, "V1_HAS_PATH_TOOL", False))

    def test_post_build_hook(self):
        # 4. Verify post_build_hook ran and modified the wheel
        package_dir = os.path.dirname(setproctitle.__file__)
        marker_file = os.path.join(package_dir, "POST_BUILD_HOOK_MARKER.txt")
        self.assertTrue(os.path.exists(marker_file), f"Marker file not found at {marker_file}")

        with open(marker_file, "r") as f:
            content = f.read().strip()
        self.assertEqual(content, "post_build_hook_was_here")


if __name__ == "__main__":
    unittest.main()
