#!/usr/bin/env python3
"""Compare wheels built on different hosts for reproducibility.

For each target platform, finds matching .whl files from both build
directories and compares them. Also checks that every extension module's
filename suffix matches its wheel's platform tag (e.g. no Linux suffix in a
macOS wheel). Exits with code 1 if any wheels differ or have mismatched
extension suffixes, failing the CI check.
"""

import difflib
import hashlib
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def hash_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare_binaries(file_a: Path, file_b: Path, name: str):
    """Compare two binary files and output useful diagnostics."""
    for tool, args in [
        ("readelf", ["-a"]),
        ("otool", ["-l"]),
        ("objdump", ["-h"]),
    ]:
        try:
            out_a = subprocess.run(
                [tool] + args + [str(file_a)],
                capture_output=True,
                text=True,
                timeout=10,
            )
            out_b = subprocess.run(
                [tool] + args + [str(file_b)],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if out_a.returncode == 0 and out_b.returncode == 0:
                if out_a.stdout != out_b.stdout:
                    print(f"  {tool} diff for {name}:")
                    diff = difflib.unified_diff(
                        out_a.stdout.splitlines(),
                        out_b.stdout.splitlines(),
                        fromfile=f"host-a/{name}",
                        tofile=f"host-b/{name}",
                        lineterm="",
                    )
                    for line in list(diff)[:50]:
                        print(f"    {line}")
                else:
                    print(f"  {tool} output identical for {name} (binary diff is metadata only)")
                return
        except FileNotFoundError:
            continue


# Wheel platform tag architecture -> CPython multiarch architecture.
_MULTIARCH_ARCH = {
    "armv7l": "arm",
    "i686": "i386",
    "ppc64": "powerpc64",
    "ppc64le": "powerpc64le",
}

# Extension module ABI tag, e.g. "cpython-315-x86_64-linux-gnu", "abi3-darwin", or "abi3".
_EXTENSION_TAG = re.compile(r"^(?:cpython-\d+t?|abi3t?|pypy\d+-pp\d+)(?:-(?P<platform>.+))?$")


def _platform_matcher(platform_tag: str):
    """Return a predicate for extension-suffix platforms compatible with a wheel platform tag."""
    if platform_tag.startswith("macosx_"):
        return lambda p: p == "darwin"
    m = re.match(r"^(?P<kind>many|musl)?linux(?:\d+|_\d+_\d+)?_(?P<arch>.+)$", platform_tag)
    if m:
        libc = "musl" if m.group("kind") == "musl" else "gnu"
        arch = _MULTIARCH_ARCH.get(m.group("arch"), m.group("arch"))
        return lambda p: p.startswith(f"{arch}-linux-{libc}")
    return None


def check_extension_suffixes(whl: Path) -> list[str]:
    """Return extension modules in `whl` whose suffix names a platform other than the wheel's."""
    platform_tag = whl.name[: -len(".whl")].split("-")[-1].split(".")[0]
    matches = _platform_matcher(platform_tag)
    if matches is None:
        return []

    bad = []
    with zipfile.ZipFile(whl) as zf:
        for name in zf.namelist():
            parts = name.rsplit("/", 1)[-1].split(".")
            if len(parts) < 3 or parts[-1] != "so":
                continue
            m = _EXTENSION_TAG.match(parts[-2])
            if m and m.group("platform") and not matches(m.group("platform")):
                bad.append(name)
    return bad


def compare_wheels(whl_a: Path, whl_b: Path) -> bool:
    """Compare two wheel files. Returns True if identical."""
    if hash_file(whl_a) == hash_file(whl_b):
        print(f"  \u2705 IDENTICAL: {whl_a.name}")
        return True

    print(f"  \u26a0\ufe0f  DIFFERS: {whl_a.name}")

    with tempfile.TemporaryDirectory() as tmpdir:
        dir_a = Path(tmpdir) / "a"
        dir_b = Path(tmpdir) / "b"

        with zipfile.ZipFile(whl_a) as z:
            z.extractall(dir_a)
        with zipfile.ZipFile(whl_b) as z:
            z.extractall(dir_b)

        files_a = {p.relative_to(dir_a) for p in dir_a.rglob("*") if p.is_file()}
        files_b = {p.relative_to(dir_b) for p in dir_b.rglob("*") if p.is_file()}

        only_a = files_a - files_b
        only_b = files_b - files_a
        common = files_a & files_b

        if only_a:
            print(f"    Only in host-a: {sorted(str(f) for f in only_a)}")
        if only_b:
            print(f"    Only in host-b: {sorted(str(f) for f in only_b)}")

        for f in sorted(common):
            fa, fb = dir_a / f, dir_b / f
            if hash_file(fa) != hash_file(fb):
                size_a, size_b = fa.stat().st_size, fb.stat().st_size
                print(f"    Changed: {f} ({size_a} vs {size_b} bytes)")
                if fa.suffix in (".so", ".dylib", ".pyd"):
                    compare_binaries(fa, fb, str(f))

    return False


def compare_wheel_dirs(dir_a: Path, dir_b: Path) -> bool:
    """Compare all .whl files in two directories. Returns True if sets match and all wheels are identical."""
    wheels_a = {w.name: w for w in dir_a.rglob("*.whl")}
    wheels_b = {w.name: w for w in dir_b.rglob("*.whl")}

    only_in_a = sorted(set(wheels_a) - set(wheels_b))
    only_in_b = sorted(set(wheels_b) - set(wheels_a))
    common = set(wheels_a) & set(wheels_b)
    all_identical = True

    if only_in_a:
        print(f"Wheels only in host A: {only_in_a}")
        all_identical = False
    if only_in_b:
        print(f"Wheels only in host B: {only_in_b}")
        all_identical = False

    if not common:
        print("No matching wheel filenames found to compare.")
        print(f"  Host A: {sorted(wheels_a.keys())}")
        print(f"  Host B: {sorted(wheels_b.keys())}")
        return False

    print(f"Comparing {len(common)} wheel(s):")
    for name in sorted(common):
        if not compare_wheels(wheels_a[name], wheels_b[name]):
            all_identical = False

    for host, wheels in (("host-a", wheels_a), ("host-b", wheels_b)):
        for name in sorted(wheels):
            bad = check_extension_suffixes(wheels[name])
            if bad:
                print(f"  \u274c WRONG EXTENSION SUFFIX ({host}): {name}: {bad}")
                all_identical = False

    return all_identical


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <dir-a> <dir-b>", file=sys.stderr)
        sys.exit(2)

    dir_a, dir_b = Path(sys.argv[1]), Path(sys.argv[2])
    if compare_wheel_dirs(dir_a, dir_b):
        print("\n\U0001f389 All wheels are byte-identical across build hosts!")
    else:
        print("\n\u26a0\ufe0f  Some wheels differ or are missing. See details above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
