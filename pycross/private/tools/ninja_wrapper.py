#!/usr/bin/env python
"""Generic Ninja wrapper for rules_pycross.

Locates the real ninja binary from the PyPI ninja wheel's installed package
layout, copies it to a writable+executable location, and execs it.

This wrapper exists because Bazel's linux-sandbox mounts external wheel files
as read-only without execute permission.  Copying to a temp file and chmod +x
is the simplest workaround.
"""

import os
import shutil
import sys
import tempfile
from pathlib import Path


def main() -> None:
    # Locate our runfiles so we can import the ninja package.
    # Bazel stages the ninja wheel in the exec config runfiles of this target,
    # but doesn't automatically add them to sys.path when executed via a
    # shell launcher stub.
    try:
        script_path = Path(__file__).resolve()
        runfiles_dir = script_path.parent / (script_path.name + ".runfiles")
        if runfiles_dir.exists():
            for site_path in runfiles_dir.glob("**/ninja*/site-packages"):
                if site_path.exists() and str(site_path) not in sys.path:
                    sys.path.append(str(site_path))
    except Exception as e:
        print(f"Warning: ninja wrapper failed to scan runfiles: {e}", file=sys.stderr)

    try:
        import ninja
    except ImportError as ie:
        print("Error: ninja wrapper could not import 'ninja' package.", file=sys.stderr)
        print(f"  {ie}", file=sys.stderr)
        print("Make sure 'ninja' is listed in your build target's 'deps'.", file=sys.stderr)
        sys.exit(1)

    # Remove PYTHONSAFEPATH so subprocesses spawned by ninja don't run in
    # Bazel's isolated safe-path mode.
    os.environ.pop("PYTHONSAFEPATH", None)

    # Find the real binary from the installed ninja package.
    # rules_pycross extracts wheel scripts into a sibling bin/ directory
    # (e.g. _lock/ninja@1.13.0/bin/ninja).
    ninja_package_dir = Path(ninja.__file__).parent
    ninja_bin = ninja_package_dir.parent.parent / "bin" / "ninja"

    if not ninja_bin.exists():
        print(f"Error: ninja wrapper could not find binary at: {ninja_bin}", file=sys.stderr)
        sys.exit(1)

    # Copy to a writable location and make executable.
    fd, tmp_path = tempfile.mkstemp(prefix="ninja_")
    os.close(fd)
    try:
        shutil.copy2(str(ninja_bin), tmp_path)
        os.chmod(tmp_path, 0o755)
        os.execv(tmp_path, [tmp_path] + sys.argv[1:])
    except Exception:
        # Clean up on failure
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


if __name__ == "__main__":
    main()
