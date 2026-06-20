import argparse
import configparser
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Extract a console script.")
    parser.add_argument(
        "--site-packages", type=Path, required=True, help="Path to the extracted site-packages directory"
    )
    parser.add_argument("--script", required=True, help="Name of the console script")
    parser.add_argument("--out", type=Path, required=True, help="Output path for the script")

    args = parser.parse_args()

    script_name = args.script
    out_path = args.out

    entry_points_path = None
    for p in args.site_packages.glob("site-packages/*.dist-info/entry_points.txt"):
        entry_points_path = p
        break

    if not entry_points_path:
        # Maybe it's directly in the root (if the path actually is the site-packages dir)
        for p in args.site_packages.glob("*.dist-info/entry_points.txt"):
            entry_points_path = p
            break

    if not entry_points_path:
        print(f"Error: No entry_points.txt found in {args.site_packages}", file=sys.stderr)
        sys.exit(1)

    content = entry_points_path.read_text(encoding="utf-8")

    config = configparser.ConfigParser()
    config.read_string(content)

    if "console_scripts" not in config:
        print("Error: No [console_scripts] section in entry_points.txt", file=sys.stderr)
        sys.exit(1)

    if script_name not in config["console_scripts"]:
        print(f"Error: Script '{script_name}' not found in [console_scripts]", file=sys.stderr)
        sys.exit(1)

    entry_point = config["console_scripts"][script_name]

    # entry_point format is usually: module:function [extras]
    # We strip any extras or trailing whitespace
    entry_point = entry_point.split()[0]
    module, function = entry_point.split(":")

    with open(out_path, "w") as f:
        f.write("#!/usr/bin/env python3\n")
        f.write(f"# Auto-generated console script for {script_name}\n")
        f.write("import sys\n")
        f.write(f"import {module}\n")
        f.write("if __name__ == '__main__':\n")
        f.write(f"    sys.exit({module}.{function}())\n")

    import os

    os.chmod(out_path, 0o755)


if __name__ == "__main__":
    main()
