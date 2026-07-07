"""Build a minimal Python wheel from source files.

Creates a valid PEP 427 wheel (.whl) zip archive with proper METADATA,
WHEEL, and RECORD files.
"""

import argparse
import base64
import hashlib
import os
import zipfile


def _record_entry(name, data):
    """Create a RECORD entry for a file."""
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
    return f"{name},sha256={digest},{len(data)}"


def main():
    parser = argparse.ArgumentParser(description="Build a minimal Python wheel.")
    parser.add_argument("--name", required=True, help="Package name")
    parser.add_argument("--version", required=True, help="Package version")
    parser.add_argument("--source", required=True, action="append", help="Source files to include")
    parser.add_argument("--output", required=True, help="Output .whl path")
    args = parser.parse_args()

    tag = "py3-none-any"
    dist_info = f"{args.name}-{args.version}.dist-info"

    with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as whl:
        records = []

        # Add source files at the root of the wheel
        for src in args.source:
            arcname = os.path.basename(src)
            with open(src, "rb") as f:
                data = f.read()
            whl.writestr(arcname, data)
            records.append(_record_entry(arcname, data))

        # METADATA
        metadata = f"Metadata-Version: 2.1\nName: {args.name}\nVersion: {args.version}\n"
        data = metadata.encode()
        whl.writestr(f"{dist_info}/METADATA", data)
        records.append(_record_entry(f"{dist_info}/METADATA", data))

        # WHEEL
        wheel_meta = (
            f"Wheel-Version: 1.0\n"
            f"Generator: make_wheel.py\n"
            f"Root-Is-Purelib: true\n"
            f"Tag: {tag}\n"
        )
        data = wheel_meta.encode()
        whl.writestr(f"{dist_info}/WHEEL", data)
        records.append(_record_entry(f"{dist_info}/WHEEL", data))

        # top_level.txt (for site-packages discovery)
        top_level = args.name + "\n"
        data = top_level.encode()
        whl.writestr(f"{dist_info}/top_level.txt", data)
        records.append(_record_entry(f"{dist_info}/top_level.txt", data))

        # RECORD (self-entry has no hash)
        records.append(f"{dist_info}/RECORD,,")
        whl.writestr(f"{dist_info}/RECORD", "\n".join(records) + "\n")


if __name__ == "__main__":
    main()
