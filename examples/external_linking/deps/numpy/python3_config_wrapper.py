import os
import subprocess
import sys
from pathlib import Path

target_bin_dir_env = os.environ.get("PYCROSS_TARGET_PYTHON_BIN_DIR")
if not target_bin_dir_env:
    print("Error: PYCROSS_TARGET_PYTHON_BIN_DIR not set in env!", file=sys.stderr)
    sys.exit(1)

real_config = Path(target_bin_dir_env) / "python3-config"
if not real_config.exists():
    # Fall back to versioned python3.X-config
    import glob
    candidates = sorted(glob.glob(str(Path(target_bin_dir_env) / "python3.*-config")), reverse=True)
    if candidates:
        real_config = Path(candidates[0])

if not real_config.exists():
    print(f"Error: Could not find python3-config in {target_bin_dir_env}", file=sys.stderr)
    sys.exit(1)

# Run the real config and capture output
args = [str(real_config)] + sys.argv[1:]
try:
    output = subprocess.check_output(args).decode("utf-8")
except subprocess.CalledProcessError as cpe:
    sys.exit(cpe.returncode)

target_system = os.environ.get("PYCROSS_TARGET_SYSTEM")

# Filter out -lpython ONLY on macOS (darwin)
filtered_parts = []
for part in output.split():
    if target_system == "darwin" and part.startswith("-lpython"):
        continue
    filtered_parts.append(part)

print(" ".join(filtered_parts))
