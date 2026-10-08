"""lib is built from a git sdist; lib.vendor comes from a git submodule."""

import lib

assert lib.DATA == "from submodule", lib.DATA
