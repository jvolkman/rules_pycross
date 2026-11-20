#!/bin/bash
set -euo pipefail

bazel build "$@" //...
bazel test "$@" //...

# The setproctitle `visibility` annotation applies to the pin package and to the root alias.
for target in //denied:via_pin_package //denied:via_root_alias; do
  if out=$(bazel build "$@" "$target" 2>&1); then
    echo "Expected $target to fail: setproctitle is not visible to //denied"
    exit 1
  fi
  if [[ "$out" != *"is not visible from"* ]]; then
    echo "Expected a visibility error for $target, got:"
    echo "$out"
    exit 1
  fi
done
echo "Visibility test passed."
