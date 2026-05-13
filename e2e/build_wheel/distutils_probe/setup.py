import subprocess
import sys

from setuptools import setup
from setuptools.command.build_py import build_py as _build_py


class build_py(_build_py):
    def run(self):
        subprocess.check_call([sys.executable, "-c", "from distutils.util import byte_compile"])
        super().run()


setup(
    name="distutils_probe",
    version="0.1",
    packages=["distutils_probe_pkg"],
    cmdclass={"build_py": build_py},
)
