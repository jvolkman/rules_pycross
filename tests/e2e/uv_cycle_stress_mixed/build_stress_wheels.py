#!/usr/bin/env python3
"""Build synthetic wheels for the 8-member cycle stress test with markers.

Creates minimal valid wheel files (.whl) directly as zip archives.
"""

import csv
import hashlib
import io
import os
import sys
import zipfile

PACKAGES = {
    "stress_airflow": ["stress-airflow-core", "stress-task-sdk"],
    "stress_airflow_core": [
        "stress-provider-compat",
        "stress-provider-io",
        "stress-provider-sql",
        "stress-provider-smtp",
        "stress-provider-standard",
        "stress-task-sdk",
        "stress-packaging",
        "stress-jinja2",
    ],
    "stress_task_sdk": ["stress-airflow-core", "stress-attrs"],
    "stress_provider_compat": ["stress-airflow"],
    "stress_provider_io": ["stress-airflow; python_version >= '3.11'"],
    "stress_provider_sql": ["stress-airflow; sys_platform == 'linux'"],
    "stress_provider_smtp": ["stress-airflow; sys_platform == 'win32'", "stress-provider-compat"],
    "stress_provider_standard": ["stress-airflow"],
    "stress_packaging": [],
    "stress_jinja2": [],
    "stress_attrs": [],
}

VERSION = "1.0.0"


def build_wheel(pkg_module: str, deps: list[str], out_dir: str) -> str:
    """Build a minimal valid wheel file directly."""
    pkg_name = pkg_module.replace("_", "-")
    whl_name = f"{pkg_module}-{VERSION}-py3-none-any.whl"
    whl_path = os.path.join(out_dir, whl_name)
    dist_info = f"{pkg_module}-{VERSION}.dist-info"

    records = []

    with zipfile.ZipFile(whl_path, "w", zipfile.ZIP_DEFLATED) as zf:
        # __init__.py
        init_path = f"{pkg_module}/__init__.py"
        init_content = f'"""Synthetic package {pkg_name} for cycle stress testing."""\n'
        zf.writestr(init_path, init_content)
        records.append((init_path, _sha256(init_content.encode()), len(init_content.encode())))

        # METADATA
        meta_path = f"{dist_info}/METADATA"
        meta_lines = [
            "Metadata-Version: 2.1",
            f"Name: {pkg_name}",
            f"Version: {VERSION}",
        ]
        for dep in deps:
            meta_lines.append(f"Requires-Dist: {dep}")
        meta_content = "\n".join(meta_lines) + "\n"
        zf.writestr(meta_path, meta_content)
        records.append((meta_path, _sha256(meta_content.encode()), len(meta_content.encode())))

        # WHEEL
        wheel_path = f"{dist_info}/WHEEL"
        wheel_content = "Wheel-Version: 1.0\nGenerator: stress-test-builder\nRoot-Is-Purelib: true\nTag: py3-none-any\n"
        zf.writestr(wheel_path, wheel_content)
        records.append((wheel_path, _sha256(wheel_content.encode()), len(wheel_content.encode())))

        # top_level.txt
        top_path = f"{dist_info}/top_level.txt"
        top_content = f"{pkg_module}\n"
        zf.writestr(top_path, top_content)
        records.append((top_path, _sha256(top_content.encode()), len(top_content.encode())))

        # RECORD (must be last)
        record_path = f"{dist_info}/RECORD"
        buf = io.StringIO(newline="\n")
        writer = csv.writer(buf, delimiter=",", quotechar='"', lineterminator="\n")
        for name, sha, size in records:
            writer.writerow([name, f"sha256={sha}", str(size)])
        writer.writerow([record_path, "", ""])
        zf.writestr(record_path, buf.getvalue())

    return whl_name


def _sha256(data: bytes) -> str:
    import base64

    digest = hashlib.sha256(data).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out_dir, exist_ok=True)

    for pkg_module, deps in sorted(PACKAGES.items()):
        whl_name = build_wheel(pkg_module, deps, out_dir)
        print(f"Built {whl_name}")


if __name__ == "__main__":
    main()
