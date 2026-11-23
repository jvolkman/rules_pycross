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
        #
        # The source also checks that the main-repo native_dep header is on
        # the include path, that transitive native_dep linkopts are forwarded
        # (-lm on Linux glibc for sin(); -framework Security on macOS for
        # SecRandomCopyBytes(); musl folds libm into libc), and that quoted
        # flags (the toolchain's -D__DATE__="redacted", the PROBE_STR copt)
        # keep their quotes.
        with tempfile.TemporaryDirectory() as tmpdir:
            src = Path(tmpdir) / "probe.c"
            src.write_text(
                "#include <math.h>\n"
                "#include <probe_hdr.h>\n"
                "#ifdef __APPLE__\n"
                "extern int SecRandomCopyBytes(const void *, unsigned long, void *);\n"
                "#endif\n"
                "static const char build_date[] = __DATE__;\n"
                "static const char probe_str[] = PROBE_STR;\n"
                '_Static_assert(sizeof(probe_str) == sizeof("a b"), "PROBE_STR");\n'
                "int main(int argc, char **argv) {\n"
                "    (void)argv; (void)build_date; (void)probe_str;\n"
                "    volatile double x = (double)argc;\n"
                "    volatile double y = sin(x);\n"
                "#ifdef __APPLE__\n"
                "    unsigned char buf[1] = {0};\n"
                "    int rc = SecRandomCopyBytes((const void *)0, 1, buf);\n"
                "    return (rc != 0 ? 1 : 0) + (y > 2.0 ? 1 : 0) + (PROBE_HDR_VALUE - 42);\n"
                "#else\n"
                "    return (y > 2.0 ? 1 : 0) + (PROBE_HDR_VALUE - 42);\n"
                "#endif\n"
                "}\n"
            )
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
