import configparser
import sys
import zipfile
from pathlib import Path


def main():
    if len(sys.argv) != 4:
        print("Usage: extract_console_script.py <wheel_path> <script_name> <out_path>", file=sys.stderr)
        sys.exit(1)

    wheel_path = Path(sys.argv[1])
    script_name = sys.argv[2]
    out_path = Path(sys.argv[3])

    with zipfile.ZipFile(wheel_path) as z:
        # Find entry_points.txt
        entry_points_path = None
        for name in z.namelist():
            if name.endswith(".dist-info/entry_points.txt"):
                entry_points_path = name
                break

        if not entry_points_path:
            print(f"Error: No entry_points.txt found in {wheel_path}", file=sys.stderr)
            sys.exit(1)

        content = z.read(entry_points_path).decode("utf-8")

    parser = configparser.ConfigParser()
    parser.read_string(content)

    if "console_scripts" not in parser:
        print(f"Error: No [console_scripts] section in {wheel_path}", file=sys.stderr)
        sys.exit(1)

    if script_name not in parser["console_scripts"]:
        print(f"Error: Script '{script_name}' not found in [console_scripts] in {wheel_path}", file=sys.stderr)
        sys.exit(1)

    entry_point = parser["console_scripts"][script_name]

    # entry_point format is usually: module:function [extras]
    # We strip any extras or trailing whitespace
    entry_point = entry_point.split()[0]
    module, function = entry_point.split(":")

    with open(out_path, "w") as f:
        f.write(f"# Auto-generated console script for {script_name}\n")
        f.write("import sys\n")
        f.write(f"import {module}\n")
        f.write("if __name__ == '__main__':\n")
        f.write(f"    sys.exit({module}.{function}())\n")


if __name__ == "__main__":
    main()
