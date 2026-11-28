import os
import site
import sys
import unittest
from pathlib import Path


class TestHybridNamespace(unittest.TestCase):
    def test_code_bearing_extend_path_and_sibling_plugin(self):
        # hybrid_core ships hybrid_ns/__init__.py with pkgutil.extend_path plus real init code,
        # while hybrid_plugin ships hybrid_ns/plugins/ext without hybrid_ns/__init__.py.
        # Under venvs_site_packages=yes, both must coexist in site-packages/hybrid_ns/.
        import hybrid_ns
        from hybrid_ns import core
        from hybrid_ns import helpers
        from hybrid_ns.plugins import ext

        self.assertEqual(hybrid_ns.__version__, "1.0.0")
        self.assertEqual(hybrid_ns.CORE_MARKER, "from_core")
        self.assertEqual(core.VALUE, 1)
        self.assertEqual(helpers.HELPER, "ok")
        self.assertEqual(ext.PLUGIN_VALUE, 2)

        # Static non-Python asset subdirectories stay linked as a single directory symlink.
        pkg_dir = Path(hybrid_ns.__file__).parent
        ui_dir = pkg_dir / "ui"
        self.assertTrue(os.path.islink(ui_dir), f"expected {ui_dir} to be a directory symlink")
        self.assertEqual((ui_dir / "index.html").read_text(encoding="utf-8"), "<html>ui</html>\n")

    def test_no_per_wheel_site_packages_on_sys_path(self):
        venv_site_packages = {os.path.realpath(p) for p in site.getsitepackages()}
        extra = [
            p
            for p in sys.path
            if os.path.basename(p.rstrip("/")) == "site-packages" and os.path.realpath(p) not in venv_site_packages
        ]
        self.assertEqual(extra, [])


if __name__ == "__main__":
    unittest.main()
