"""Writes one of the synthetic fixture wheels for the import index tests.

Usage: make_wheel.py <fixture> <distribution> <version> <output.whl>
"""

import base64
import hashlib
import sys
import zipfile

NVIDIA_COMPONENTS = ("cublas", "cudnn", "nccl")

FIXTURES = {
    # nvidia-style split package: each distribution ships an empty nvidia/__init__.py (so nvidia
    # is a regular package, not a namespace) and keeps its native libraries in
    # nvidia/<component>/lib, which torch-style code globs for on sys.path.
    **{
        "nvidia_fixture_" + c: {
            "nvidia/__init__.py": "",
            "nvidia/fixture_{}/__init__.py".format(c): "",
            "nvidia/fixture_{0}/lib/libfixture_{0}.so.12".format(c): "",
        }
        for c in NVIDIA_COMPONENTS
    },
    # azure-style plugin: the plugin installs a package into another distribution's regular
    # package (azfixture.core.tracing.ext), so only a merged view can import it.
    "azfixture_core": {
        "azfixture/core/__init__.py": "",
        "azfixture/core/tracing/__init__.py": "",
        "azfixture/core/tracing/ext/__init__.py": "",
    },
    "azfixture_core_tracing_plugin": {
        "azfixture/core/tracing/ext/fixture_span/__init__.py": "SPAN = True\n",
    },
    # A root .pth file with a path line and an import line.
    "pthfixture": {
        "pthfixture.pth": "pthfixture_extra\nimport sys; sys._pthfixture_ran = True\n",
        "pthfixture_extra/pthfixture_extramod.py": "EXTRA = True\n",
    },
    # enum34-style backport of a stdlib module: it must not shadow the stdlib.
    "enumfixture": {
        "enum/__init__.py": "SHADOW = True\n",
    },
}


def _record_hash(data: bytes) -> str:
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode("ascii")
    return "sha256=" + digest


def write_wheel(fixture: str, distribution: str, version: str, output: str) -> None:
    dist_info = "{}-{}.dist-info".format(distribution.replace("-", "_"), version)
    entries = {path: content.encode() for path, content in FIXTURES[fixture].items()}
    entries[dist_info + "/METADATA"] = "Metadata-Version: 2.1\nName: {}\nVersion: {}\n".format(
        distribution, version
    ).encode()
    entries[dist_info + "/WHEEL"] = (
        b"Wheel-Version: 1.0\nGenerator: make_wheel.py\nRoot-Is-Purelib: true\nTag: py3-none-any\n"
    )
    record = ["{},{},{}".format(path, _record_hash(data), len(data)) for path, data in sorted(entries.items())]
    record.append(dist_info + "/RECORD,,")
    entries[dist_info + "/RECORD"] = ("\n".join(record) + "\n").encode()

    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(entries):
            info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16
            zf.writestr(info, entries[path])


if __name__ == "__main__":
    write_wheel(*sys.argv[1:5])
