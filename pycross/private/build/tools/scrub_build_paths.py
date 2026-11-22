"""Post-build hook to scrub sandbox paths from specific files inside a wheel.

Usage: Set the following environment variables before invoking this hook:
  PYCROSS_WHEEL_FILE       - Path to the wheel file to process.
  PYCROSS_WHEEL_OUTPUT_DIR - Directory to write the modified wheel to.
  PYCROSS_BAZEL_ROOT       - The sandbox prefix to strip.
  PYCROSS_SCRUB_PATHS      - Comma-separated list of file paths within the wheel
                             to scrub (e.g. "numpy/__config__.py,contourpy/util/_build_config.py").

The hook strips absolute sandbox paths, Bazel output directory prefixes
(bazel-out/<config>/bin/), and external/ prefixes from the specified files,
making build metadata reproducible across different build hosts.
"""

import base64
import csv
import hashlib
import io
import os
import re
import shutil
import sys
import zipfile
from pathlib import Path

_BAZEL_OUT_RE = re.compile(r"bazel-out/[^/]+/bin/")
# Anchor external/ so package/directory names like my_external/ or pkg/external/
# are not corrupted while flag-attached paths like -Iexternal/ still match.
_EXTERNAL_RE = re.compile(r"(^|[\s'\"=:,;(\[]|-[IL]|-isystem|/I)external/", re.MULTILINE)


def _is_record_file(filename: str) -> bool:
    parts = filename.split("/")
    return len(parts) == 2 and parts[0].endswith(".dist-info") and parts[1] == "RECORD"


def _record_hash_and_size(data: bytes) -> tuple[str, str]:
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode("ascii")
    return f"sha256={digest}", str(len(data))


def _update_record(record_bytes: bytes, updated_hashes: dict[str, tuple[str, str]]) -> bytes:
    text = record_bytes.decode("utf-8")
    lineterminator = "\r\n" if "\r\n" in text else "\n"
    out = io.StringIO()
    writer = csv.writer(out, lineterminator=lineterminator)
    for row in csv.reader(io.StringIO(text, newline="")):
        if row and row[0] in updated_hashes:
            hash_str, size_str = updated_hashes[row[0]]
            writer.writerow([row[0], hash_str, size_str])
        else:
            writer.writerow(row)
    return out.getvalue().encode("utf-8")


def scrub_text(text: str, prefix: str) -> str:
    prefix_clean = prefix.rstrip("/\\")
    if prefix_clean:
        text = text.replace(prefix_clean + "/", "")
        text = text.replace(prefix_clean, "")
    text = _BAZEL_OUT_RE.sub("", text)
    text = _EXTERNAL_RE.sub(r"\1", text)
    return text


def scrub_wheel(wheel_file: Path, output_wheel: Path, prefix: str, scrub_paths: set[str]) -> bool:
    updated_hashes: dict[str, tuple[str, str]] = {}
    deferred_records: list[tuple[zipfile.ZipInfo, bytes]] = []

    with zipfile.ZipFile(wheel_file, "r") as zin, zipfile.ZipFile(output_wheel, "w") as zout:
        for info in zin.infolist():
            data = zin.read(info.filename)
            if _is_record_file(info.filename):
                deferred_records.append((info, data))
                continue
            if info.filename in scrub_paths:
                text = scrub_text(data.decode("utf-8"), prefix)
                data = text.encode("utf-8")
                updated_hashes[info.filename] = _record_hash_and_size(data)
                print(f"Scrubbed build paths from {info.filename}", file=sys.stderr)
            zout.writestr(info, data)

        for info, data in deferred_records:
            if updated_hashes:
                data = _update_record(data, updated_hashes)
            zout.writestr(info, data)

    return bool(updated_hashes)


def main():
    wheel_file = Path(os.environ["PYCROSS_WHEEL_FILE"])
    output_dir = Path(os.environ["PYCROSS_WHEEL_OUTPUT_DIR"])
    prefix = os.environ["PYCROSS_BAZEL_ROOT"]
    scrub_paths_raw = os.environ.get("PYCROSS_SCRUB_PATHS", "")

    if not scrub_paths_raw:
        print("PYCROSS_SCRUB_PATHS not set, nothing to scrub", file=sys.stderr)
        shutil.copy2(str(wheel_file), str(output_dir / wheel_file.name))
        return

    scrub_paths = {p.strip() for p in scrub_paths_raw.split(",") if p.strip()}
    output_wheel = output_dir / wheel_file.name
    modified = scrub_wheel(wheel_file, output_wheel, prefix, scrub_paths)

    if modified:
        print(f"Wrote scrubbed wheel to {output_wheel}", file=sys.stderr)
    else:
        print(f"No matching files found to scrub in {wheel_file.name}", file=sys.stderr)


if __name__ == "__main__":
    main()
