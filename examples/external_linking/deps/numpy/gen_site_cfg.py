import os
from pathlib import Path

bazel_root = Path(os.environ["PYCROSS_BAZEL_ROOT"])
openblas_lib = Path(os.environ["OPENBLAS_LIB"])
openblas_include = Path(os.environ["OPENBLAS_INCLUDE"])

p = Path("openblas")
p.mkdir()

include_dir = os.path.relpath(bazel_root / openblas_include, p)
lib_dir = os.path.relpath(bazel_root / openblas_lib.parent, p)

(p / "include").symlink_to(include_dir, target_is_directory=True)
(p / "lib").symlink_to(lib_dir, target_is_directory=True)

site_cfg = f"""\
[openblas]
libraries = openblas
library_dirs = openblas/lib
include_dirs = openblas/include
search_static_first = 1
extra_link_args = -lm
"""

with open("site.cfg", "w") as f:
    f.write(site_cfg)
