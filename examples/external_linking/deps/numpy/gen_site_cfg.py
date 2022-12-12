import os
from pathlib import Path

cwd_path = Path(os.environ["PYCROSS_BUILD_CWD"])
openblas_lib = Path(os.environ["OPENBLAS_LIB"])
openblas_include = Path(os.environ["OPENBLAS_INCLUDE"])

include_dir = cwd_path / openblas_include
lib_dir = cwd_path / openblas_lib.parent

p = Path("openblas")


p.mkdir()
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
