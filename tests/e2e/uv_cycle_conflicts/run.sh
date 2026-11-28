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
  local spoke="$1"
  local target="$2"
  local expected="$3"
  local count
  count=$(grep -c "__pkg_${spoke}/\(_reset_\)\?${target} (TreeArtifact)" <<<"$installs" || true)
  if [[ "$count" != "$expected" ]]; then
    echo "Expected ${expected} install(s) of __pkg_${spoke}/${target}, got ${count}:"
    echo "$installs"
    exit 1
  fi
}

assert_installs "above" "pkg" 1
assert_installs "cyc_p" "_raw" 1
assert_installs "cyc_q" "_raw" 1
assert_installs "cyc_y" "_raw" 1
assert_installs "cyc_x" "_raw" 2
assert_installs "iniconfig" "pkg_s0" 1
assert_installs "iniconfig" "pkg_s1" 1

total=$(wc -l <<<"$installs" | tr -d ' ')
if [[ "$total" != 8 ]]; then
  echo "Expected 8 total PycrossWheelInstall actions, got ${total}:"
  echo "$installs"
  exit 1
fi

echo "Cycle + conflict variant reset tests passed."
