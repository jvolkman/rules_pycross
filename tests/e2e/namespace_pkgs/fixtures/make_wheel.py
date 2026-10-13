"""Writes one of the synthetic fixture wheels for the import index tests.

Usage: make_wheel.py <fixture> <distribution> <version> <output.whl>
"""

import base64
import hashlib
import sys
import zipfile
import zlib

NVIDIA_COMPONENTS = ("cublas", "cudnn", "nccl")

# Tiny prebuilt x86_64 ELF shared objects (zlib-compressed base64):
# - libfixture_cublas.so.12: SONAME libfixture_cublas.so.12, exports `fixture_cublas() -> 12`
# - libfixture_cudnn.so.12: SONAME libfixture_cudnn.so.12, exports `fixture_cudnn() -> 9`
# - libuser.so: DT_NEEDED libfixture_cublas.so.12 (`eager_cublas()`), plus `lazy_cudnn()` calling
#   `dlopen("libfixture_cudnn.so.12", RTLD_NOW)`, with original DT_RUNPATH:
#   `$ORIGIN/../nvidia/fixture_cublas/lib:$ORIGIN/../nvidia/fixture_cudnn/lib`
_LIBFIXTURE_CUBLAS_SO_12 = zlib.decompress(
    base64.b64decode(
        "eNrtW19oHEUYn91r0o2Nua0kWJtqDkkw9c/mUj1oLUkOEuNaDNSSQgRls5fby53cn7q7oUkoGggitQZiX/TRxzz2"
        "MfhiQ0sJpQ/1odDHvBQiiAZKpfEh6+ztN5eZaTcp+CDK94Pd33zfzG++nT+7x97OfPneh6OqohCGBBkkuxYhWeD1"
        "NO87STR67iDt9bIHSDw2EiITPaJQ18TZMrcoIvO6erwU+CX+gYjM65rpMWFE9sSgyNcgzqoUTwVdEXTFQZEnFZE1"
        "kJ994Of3us5uIjLrw4+orpk8O1i3nYN4ce1bUURmzVRhHFj/1C9RjTj0O58t7TW8ZJRrGo83Y/x6jF+J8Z+nxwu0"
        "V7ehoY2+sazpSq1qeb7t+pZFrA/Gx6y84zrTJc933PGx4XKt6ozbubIT5T09x5qata1CqWqXS/MOKZRm/RnXsaZm"
        "cmXbI+VSTvQYXs3oPyH0KxvvLbi+Scl/TRdvJE26sdaHdtvF33d3Ob/K+e9z/gR/n3H+AwSBQCAQCAQCgUAgnoS5"
        "+JtmXmm610eTX1331eCuuXhTu9HIDzK3aVbQc4eek11ZmrpKU4Xlhn5pYC3ULjX9FNKpx34Hre4LqK4l2Eh2LYTl"
        "bgDT8t/Vy2e+Cen4jnl5y1z7fchce5wwlVvmLzt+O60gAxVowUYh2TWyq3+YfOWvhYExmk1m3jhvLg6oYdK8/MBv"
        "Na8MGNTY/DgIgs08Pd1q6qG28inVCvpfL9LM1dbwqqL2Cy1GIBAIBAKBQCAQCATi/welM3E6/AYdfktMbQVBlnKa"
        "cpHyNuUFKNfOys+fI8qsrnS2HtSWlej79TF63P8jCOqfOtv00bYjZ5KHLmoLZOjo6dff7n6V6elrPLlOy2lc/FDz"
        "CT0+p7GacTgQCAQCgUAgEAgE4j8Hth6WrX9tA38euJV/AaR4ntmHI3oJTLbOthNs9u54FJittz0m5T/aCWr1BLeW"
        "OcQq2Oxdsxfs58C+BHwI+AgwW2u7CetsD4J9MiHGXQFukfTbQXQ9iX9pPNh69SeQjej94eF3U70jTq5kV1P9GeOE"
        "kX6r/53jkCTE8Iqe7/p2jhjT1RmjaHtFYuTnqt5cJWLfJYbrlO3QIEapWvKJcaHsG9M1mvCdWXouUC8xnKJVcO2K"
        "YxXz7q4VSSzbde25qCRL0/rsSmmKhDWFNVKP7dvEyHkeMaZqlYpT9f95/4Tj/Scdo8Zaa1XkbsmtSfoOqEOV5hXj"
        "ZW4eKZyezY+XIU+V5injS/L/NpLdQ6J136o0LxmvxFw/i99HxD0A8n6MF6V48hrzryV9ShdZl8rL2z4ykj6tiyz3"
        "tybxoKTP6iL/HBOfYURu/2GRW/Zp/xnQN+ZPSuTuffQTkr43JfKFmPYz5OAZm5Cem2w/yH79V6VHktOz5+rkM+rn"
        "ibgnobFPBvRsf0xC0rFxOAXtZ/lsX8R6n9idcfEXJT17Tm/2ifM8Tv+tpG9sfErv3X6Gq+BrtA/0Woxevn+/B19a"
        "jgOOrhg9z0/7bXkN9D/u"
        "E/9v7Gcvhw=="
    )
)
_LIBFIXTURE_CUDNN_SO_12 = zlib.decompress(
    base64.b64decode(
        "eNrtW19oHEUYn73rpXs25q6SYG2qOSTB1D+bS/WgtSQ5SIxrMaAlhQjKZu9uL3dwt1f3NjS5Bw0cIrUWYl/00cc8"
        "SR+DLzZUShAf2odCH/NSiCAaEKURyTp7+83dzLSbFHwQ5fvB3m++b+Y33/zbDZud+fiNt6cjikIYomScdCxCssCb"
        "ad53mqj0t4/0tsoeIuHYiopMkgH5uhhnyxxXROZ1rXgp8Ev8FRGZ13XRa04L7Llxka9DnHUpXgR0JdCVxkWeV0RW"
        "Qf7OfbewXzsHichsDN+lui7y+GDDdh7ihfVvTRGZdTMC88DGR+Va4/ubf32j7Rd/musaj5dD/MkQvxLiv0Cvp2ir"
        "dqGj7bExjIVqzTbqrum4hkGMt2ZnjILlWAvlums5szOTlZptzZq5ihXkPTrHyC+ZRrFsm5VywyLF8pK76FhGfrFg"
        "26RSzgkOrV7TRk8RcVzZfO9A++Yl//WkeCOp0o21OdHpF3/f3eb8Ec5/j/NH+fuM8x8iCAQCgUAgEAgEAvEw9ObP"
        "qn4ldneEJj+54Ua823rze/VmO9/L/ECzvKEf6W9iIEtT12iquNrWXx3b8LVXY9/6dOaB20er+wiqi3tbiYEVv9xN"
        "YFr+i1b5zGc+ndzTL+/oG79M6BsPorpyS7+z5/bSCjJQgeptFRMDUx39b4nn/lwZm6HZZPGlC3pzLOIn9cv33W79"
        "yphGje33PM/bLtCfW7EhaisfUK2g/+kSzVyP+60K+i/0GIFAIBAIBAKBQCAQiP8flP7oWf8btP8tMbXjeVnKacol"
        "yruUV6BcLyvfOE+UpaTS331YXVWC79cn6HXvV89rfersSU73HDuXOHJJXSETx8+++Org80xPX+PJDVpO5eL7mvfp"
        "9SGN1YXTgUAgEAgEAoFAIBD/ObD9sGz/aw/488Dd/AsgxZPMPhrQM2Cyfbb9YLN3x+PAbL/tCSn/9z2v1krA5tkY"
        "+NfBZu+aw2A/AXYD+AjwMWC213Yb9tkeBvt0VIy7BhyX9Lte0J7ovzQfbL/6Q8gG9Obk5Oup4SkrVzbt1GhGO6Wl"
        "Xxl97SQkCdHqpbrruGaOaAv2olYy6yWiFZbt+nI1YNchmmNVTN8gWtkuu0S7WHG1hRpNuNYS/S1SL9GsklF0zKpl"
        "lApOxwokhuk45nJQkqVpfWa1nCd+TX6N1GO6JtFy9TrR8rVq1bLdfz4+/nz/Qeeovdc6IvKg5FYlfR/UEZHWFeNV"
        "bh0pnJ6tj2chLyKtU8YN+f82kj1Egn3fEWldMl4LaT+LP0I6ZwD4+5Lx01I8eY/5p5I+lRQ5KZWXj31kJH06KbI8"
        "3qrE45I+mxT5u5D4DFNy/4+KHD+g/+dA314/KZEHD9DPSfrhlMgXQ/rPkINnbFR6brLzIAeNn02vBKdnz9X5x9Q3"
        "iHgmoX1OBvTsfExU0rF5OAP9Z/nsXMTmiDicYfGbkp49p7dHxHUepv9c0rcPPqX37z/DNfC1+wd6NUQv379fgi8t"
        "xwHHQIie50f9bXkB9F8fEP9v3ncvoA=="
    )
)
_LIBUSER_SO = zlib.decompress(
    base64.b64decode(
        "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"
        "QP/NPPX/Caf28Vw="
    )
)
_NATIVE_LIBS = {
    "cublas": _LIBFIXTURE_CUBLAS_SO_12,
    "cudnn": _LIBFIXTURE_CUDNN_SO_12,
    "nccl": b"",
}

FIXTURES = {
    # nvidia-style split package: each distribution ships an empty nvidia/__init__.py (so nvidia
    # is a regular package, not a namespace) and keeps its native libraries in
    # nvidia/<component>/lib, which torch-style code globs for on sys.path.
    **{
        "nvidia_fixture_" + c: {
            "nvidia/__init__.py": "",
            "nvidia/fixture_{}/__init__.py".format(c): "",
            "nvidia/fixture_{0}/lib/libfixture_{0}.so.12".format(c): _NATIVE_LIBS[c],
        }
        for c in NVIDIA_COMPONENTS
    },
    # Cross-wheel $ORIGIN RUNPATH user: rpathfixture/libuser.so has DT_NEEDED
    # libfixture_cublas.so.12 and dlopens libfixture_cudnn.so.12 by SONAME via
    # $ORIGIN/../nvidia/fixture_{cublas,cudnn}/lib.
    "rpathfixture": {
        "rpathfixture/__init__.py": (
            "import ctypes, os\n"
            "LIB_PATH = os.path.join(os.path.dirname(__file__), 'libuser.so')\n"
            "def load_and_call():\n"
            "    lib = ctypes.CDLL(LIB_PATH)\n"
            "    return lib.eager_cublas(), lib.lazy_cudnn()\n"
        ),
        "rpathfixture/libuser.so": _LIBUSER_SO,
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
    entries = {
        path: (content if isinstance(content, bytes) else content.encode())
        for path, content in FIXTURES[fixture].items()
    }
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
