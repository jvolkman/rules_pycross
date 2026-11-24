#!/usr/bin/env python3
"""Deterministically build the local synthetic wheels for this e2e fixture."""

import base64
import hashlib
import zipfile
from pathlib import Path

FIXED_ZIP_TIME = (2020, 1, 1, 0, 0, 0)

PACKAGES = [
    ("above", "above", "VALUE = 'above'\n", ["cyc-p"]),
    ("cyc-p", "cyc_p", "VALUE = 'p'\n", ["cyc-q"]),
    ("cyc-q", "cyc_q", "VALUE = 'q'\n", ["cyc-p"]),
    ("cyc-x", "cyc_x", "VALUE = 'x'\n", ["cyc-y", "iniconfig"]),
    ("cyc-y", "cyc_y", "VALUE = 'y'\n", ["cyc-x"]),
]


def _record_hash(data: bytes) -> str:
    digest = hashlib.sha256(data).digest()
    return "sha256=" + base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def build_wheel(out_dir: Path, dist_name: str, pkg_name: str, init_src: str, requires: list[str]) -> tuple[str, str]:
    version = "1.0.0"
    filename = f"{pkg_name}-{version}-py3-none-any.whl"
    dist_info = f"{pkg_name}-{version}.dist-info"

    metadata_lines = [
        "Metadata-Version: 2.1",
        f"Name: {dist_name}",
        f"Version: {version}",
    ] + [f"Requires-Dist: {req}" for req in requires]
    metadata = ("\n".join(metadata_lines) + "\n").encode("utf-8")

    wheel_meta = ("Wheel-Version: 1.0\nGenerator: build_wheels.py\nRoot-Is-Purelib: true\nTag: py3-none-any\n").encode(
        "utf-8"
    )

    entries = [
        (f"{pkg_name}/__init__.py", init_src.encode("utf-8")),
        (f"{dist_info}/METADATA", metadata),
        (f"{dist_info}/WHEEL", wheel_meta),
    ]
    record_lines = [f"{name},{_record_hash(data)},{len(data)}" for name, data in entries]
    record_lines.append(f"{dist_info}/RECORD,,")
    entries.append((f"{dist_info}/RECORD", ("\n".join(record_lines) + "\n").encode("utf-8")))

    whl_path = out_dir / filename
    with zipfile.ZipFile(whl_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=FIXED_ZIP_TIME)
            info.external_attr = 0o644 << 16
            zf.writestr(info, data)

    sha256 = hashlib.sha256(whl_path.read_bytes()).hexdigest()
    return filename, sha256


def main() -> None:
    out_dir = Path(__file__).resolve().parent
    for dist_name, pkg_name, init_src, requires in PACKAGES:
        filename, sha256 = build_wheel(out_dir, dist_name, pkg_name, init_src, requires)
        print(f"{filename}  sha256:{sha256}")


if __name__ == "__main__":
    main()
