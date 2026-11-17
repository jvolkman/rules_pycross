import base64
import hashlib
import sys
import zipfile
from pathlib import Path


def _hash_bytes(data: bytes) -> str:
    digest = hashlib.sha256(data).digest()
    b64 = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return f"sha256={b64},{len(data)}"


def main() -> None:
    out_whl = Path(sys.argv[1])
    init_py = Path(sys.argv[2]).read_bytes()
    foo_h = Path(sys.argv[3]).read_bytes()
    libfoo_so = Path(sys.argv[4]).read_bytes()

    dist_info = "pkga-0.1.dist-info"
    metadata = ("Metadata-Version: 2.1\nName: pkga\nVersion: 0.1\n").encode("utf-8")
    wheel_meta = (
        "Wheel-Version: 1.0\nGenerator: build_pkga_wheel\nRoot-Is-Purelib: false\nTag: py3-none-any\n"
    ).encode("utf-8")

    files = [
        ("pkga/__init__.py", init_py),
        ("pkga/include/foo.h", foo_h),
        ("pkga/lib/libfoo.so", libfoo_so),
        (f"{dist_info}/METADATA", metadata),
        (f"{dist_info}/WHEEL", wheel_meta),
    ]

    record_lines = [f"{arcname},{_hash_bytes(data)}" for arcname, data in files]
    record_lines.append(f"{dist_info}/RECORD,,")
    record_data = ("\n".join(record_lines) + "\n").encode("utf-8")
    files.append((f"{dist_info}/RECORD", record_data))

    with zipfile.ZipFile(out_whl, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for arcname, data in files:
            info = zipfile.ZipInfo(arcname)
            info.external_attr = (0o755 if arcname.endswith(".so") else 0o644) << 16
            zf.writestr(info, data)


if __name__ == "__main__":
    main()
