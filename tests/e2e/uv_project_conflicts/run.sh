#!/bin/bash
set -euo pipefail

# Per-project repos and a flag-pinned repo, all in one build.
bazel test "$@" //... --test_output=errors

# A repo with both projects selects one with a flag.
bazel test "$@" //:test_all_a --@all//_variants:package_a=True --test_output=errors

# Without a flag, it fails clearly, as `uv sync --all-packages` would.
if out=$(bazel build "$@" //:test_all_a 2>&1); then
  echo "Expected //:test_all_a to fail without a variant flag!"
  exit 1
fi
if [[ "$out" != *"Set one of the _variants flags on your pycross repo: package_a, package_b"* ]]; then
  echo "Unexpected error output:"
  echo "$out"
  exit 1
fi
# Same with every member, including the unconflicted `c`.
bazel test "$@" //:test_everything_a --@everything//_variants:package_a=True --test_output=errors
if out=$(bazel build "$@" //:test_everything_a 2>&1); then
  echo "Expected //:test_everything_a to fail without a variant flag!"
  exit 1
fi
if [[ "$out" != *"Set one of the _variants flags on your pycross repo: package_a, package_b"* ]]; then
  echo "Unexpected error output:"
  echo "$out"
  exit 1
fi
echo "Project conflict tests passed."
