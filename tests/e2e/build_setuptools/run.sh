#!/bin/bash
set -euo pipefail

bazel test "$@" //...

# Free-threaded (PEP 703) Python: build setproctitle from its sdist for cp314t, natively and
# cross-compiled, and import the native build on a free-threaded interpreter.
FREETHREADED=--@rules_python//python/config_settings:py_freethreaded=yes
bazel test "$@" "$FREETHREADED" --test_env=EXPECT_FREETHREADED=1 //tests:test_freethreaded

for platform in linux_x86_64 macos_aarch64; do
  flags=("$@" "$FREETHREADED" "--platforms=@llvm//platforms:$platform")
  bazel build "${flags[@]}" @uv//setproctitle:wheel
  wheel_dir=$(bazel cquery "${flags[@]}" --output=files @uv//setproctitle:wheel 2>/dev/null)
  wheels=$(ls "$wheel_dir")
  echo "$platform: $wheels"
  case "$platform:$wheels" in
    linux_x86_64:setproctitle-*-cp314-cp314t-*manylinux*_x86_64.whl) ;;
    macos_aarch64:setproctitle-*-cp314-cp314t-macosx_*_arm64.whl) ;;
    *)
      echo "Expected a cp314t setproctitle wheel for $platform, got: $wheels"
      exit 1
      ;;
  esac
done
echo "Free-threaded checks passed."
