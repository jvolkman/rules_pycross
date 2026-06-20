import unittest
from unittest.mock import MagicMock
from unittest.mock import patch

from pycross.private.tools.lock_model import FileKey
from pycross.private.tools.lock_model import FileReference
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import ResolvedLockSet
from pycross.private.tools.lock_model import ResolvedPackage
from pycross.private.tools.toml_lock_generator import main


class TomlLockGeneratorTest(unittest.TestCase):
    @patch("pycross.private.tools.raw_lock_resolver.resolve")
    def test_toml_output(self, mock_resolve):
        lock = ResolvedLockSet(
            environments={},
            remote_files={
                FileKey("mypkg-1.0-py3-none-any.whl/12345"): PackageFile(
                    name="mypkg-1.0-py3-none-any.whl",
                    sha256="12345",
                    urls=("https://ex.com/mypkg-1.0-py3-none-any.whl",),
                )
            },
            packages={
                PackageKey("mypkg@1.0"): ResolvedPackage(
                    key=PackageKey("mypkg@1.0"),
                    environment_files={"env1": FileReference(key=FileKey("mypkg-1.0-py3-none-any.whl/12345"))},
                )
            },
            pins={"mypkg": {"": PackageKey("mypkg@1.0")}},
        )
        mock_resolve.return_value = lock

        import os
        import tempfile

        with tempfile.TemporaryDirectory() as td:
            out_file = os.path.join(td, "out.toml")
            args = MagicMock()
            args.lock_model_file = "lock_model.json"
            args.output = out_file

            main(args)

            with open(out_file, "r") as f:
                content = f.read()

        self.assertIn("[pins]", content)
        self.assertIn('mypkg = "mypkg@1.0"', content)
        self.assertIn('[packages."mypkg@1.0"]', content)
        self.assertIn('name = "mypkg"', content)
        self.assertIn('version = "1.0"', content)
        self.assertIn('url = "https://ex.com/mypkg-1.0-py3-none-any.whl"', content)
        self.assertIn('sha256 = "12345"', content)


if __name__ == "__main__":
    unittest.main()
