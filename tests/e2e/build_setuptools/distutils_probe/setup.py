import subprocess
import sys
import tempfile
from pathlib import Path

from setuptools import setup
from setuptools.command.build_ext import customize_compiler
from setuptools.command.build_ext import new_compiler
from setuptools.command.build_py import build_py as _build_py


class build_py(_build_py):
    def run(self):
        subprocess.check_call([sys.executable, "-c", "from distutils.util import byte_compile"])

        # Exercise compiler.link_executable (used by setup.py feature probes
        # such as netifaces), where distutils invokes linker_exe (= bare CC,
        # without LDFLAGS).
        with tempfile.TemporaryDirectory() as tmpdir:
            src = Path(tmpdir) / "probe.c"
            src.write_text("int main(void) { return 0; }\n")
            compiler = new_compiler()
            customize_compiler(compiler)
            objs = compiler.compile([str(src)], output_dir=tmpdir)
            compiler.link_executable(objs, "probe", output_dir=tmpdir)

        super().run()


setup(
    name="distutils_probe",
    version="0.1",
    packages=["distutils_probe_pkg"],
    cmdclass={"build_py": build_py},
)
