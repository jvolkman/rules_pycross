import os
import sys
from pathlib import Path
import ninja

# Find the real binary relative to the package
ninja_dir = Path(ninja.__file__).parent.parent.parent / "bin"
ninja_bin = ninja_dir / "ninja"

if not ninja_bin.exists():
    # Try fallback
    ninja_bin = Path(ninja.BIN_DIR) / "ninja"

if not ninja_bin.exists():
    print(f"Error: Could not find ninja binary at {ninja_bin}", file=sys.stderr)
    sys.exit(1)

# Remove PYTHONSAFEPATH so subprocesses spawned by ninja won't run in isolated safe-path mode.
# This wrapper inherits PYTHONSAFEPATH=1 from Bazel's python launcher.
os.environ.pop("PYTHONSAFEPATH", None)

# Run it
os.execv(ninja_bin, [str(ninja_bin)] + sys.argv[1:])
