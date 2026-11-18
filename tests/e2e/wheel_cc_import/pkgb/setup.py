from setuptools import Extension
from setuptools import setup

# pkga's headers and libfoo come from the build's native_deps, which put them on
# the compiler's include and library paths.
setup(
    name="pkgb",
    version="0.1",
    packages=["pkgb"],
    ext_modules=[
        Extension(
            "pkgb._ext",
            sources=["pkgb/_ext.c"],
            libraries=["foo"],
        ),
    ],
)
