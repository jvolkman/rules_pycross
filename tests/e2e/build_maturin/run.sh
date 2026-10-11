#!/bin/bash
set -euo pipefail

bazel test "$@" //...

# Cross-build python-geohash (a setuptools-rust abi3 extension) on Python 3.15.0, which is registered
# with python.single_version_override. This needs crossenv to work on 3.15, and the extension must
# get the target platform's suffix: 3.15 adds platform-tagged suffixes like .abi3-x86_64-linux-gnu.so,
# so the build host's suffix must not leak into the wheel.
case "$(uname -s)" in
  Linux) platform=macos_aarch64 want='^_geohash\.abi3(-darwin)?\.so$' ;;
  Darwin) platform=linux_x86_64 want='^_geohash\.abi3(-x86_64-linux-gnu)?\.so$' ;;
  *) echo "Unsupported host: $(uname -s)"; exit 1 ;;
esac
flags=("$@" "--platforms=@llvm//platforms:$platform" --@rules_python//python/config_settings:python_version=3.15.0)
bazel build "${flags[@]}" @uv//python_geohash:wheel
wheel_dir=$(bazel cquery "${flags[@]}" --output=files @uv//python_geohash:wheel 2>/dev/null)
python3 - "$wheel_dir" "$want" <<'PY'
import pathlib, re, sys, zipfile

wheel_dir, want = sys.argv[1:]
(wheel,) = pathlib.Path(wheel_dir).glob("*.whl")
exts = [pathlib.PurePosixPath(n).name for n in zipfile.ZipFile(wheel).namelist() if n.endswith(".so")]
print(f"{wheel.name}: {exts}")
if not exts or not all(re.match(want, e) for e in exts):
    sys.exit(f"Expected extension suffixes matching {want!r}")
PY
echo "3.15 cross-build check passed."
