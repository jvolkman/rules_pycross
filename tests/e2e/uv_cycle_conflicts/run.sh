#!/bin/bash
set -euo pipefail

# Verify all cycle + conflict runtime imports and diamond combinations.
bazel test "$@" //... --test_output=errors

# Verify variant reset deduplicates wheel installs across cpu_only and gpu_only:
# - Pure-wheel cycle (cyc-p <-> cyc-q) and its caller (above) each install once.
# - In the mixed cycle (cyc-x <-> cyc-y), cyc-y has no variant-gated external
#   dep so _raw_cyc-y installs once; only _raw_cyc-x (which depends on
#   variant-gated iniconfig) installs once per config (2 total).
# - Each iniconfig fork installs once.
installs=$(bazel aquery "$@" 'mnemonic("PycrossWheelInstall", deps(//...))' \
  --output=text 2>/dev/null | grep "^  Outputs:")

assert_installs() {
  local pkg="$1"
  local expected="$2"
  local count
  count=$(grep -c "_lock/\(_reset_\)\?${pkg} (TreeArtifact)" <<<"$installs" || true)
  if [[ "$count" != "$expected" ]]; then
    echo "Expected ${expected} install(s) of ${pkg}, got ${count}:"
    echo "$installs"
    exit 1
  fi
}

assert_installs "above@1.0.0" 1
assert_installs "_raw_cyc-p@1.0.0" 1
assert_installs "_raw_cyc-q@1.0.0" 1
assert_installs "_raw_cyc-y@1.0.0" 1
assert_installs "_raw_cyc-x@1.0.0" 2
assert_installs "iniconfig@1.1.1" 1
assert_installs "iniconfig@2.0.0" 1

total=$(wc -l <<<"$installs" | tr -d ' ')
if [[ "$total" != 8 ]]; then
  echo "Expected 8 total PycrossWheelInstall actions, got ${total}:"
  echo "$installs"
  exit 1
fi

echo "Cycle + conflict variant reset tests passed."
