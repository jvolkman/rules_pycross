import os
from pathlib import Path
import subprocess

wheel_path = Path(os.environ["PYCROSS_WHEEL_FILE"])
out_path = Path(os.environ["PYCROSS_WHEEL_OUTPUT_ROOT"])

subprocess.check_call(["/home/jvolkman/.local/bin/auditwheel", "repair", "--plat", "manylinux_2_35_x86_64", "-w", str(out_path), str(wheel_path)])
