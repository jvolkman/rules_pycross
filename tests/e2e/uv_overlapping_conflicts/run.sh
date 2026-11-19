#!/bin/bash
set -euo pipefail

# `cpu_only` needs no flags.
bazel test "$@" //:test_cpu_only --test_output=errors

# `runtime` selects with a flag. Selecting `gpu` leaves the second set
# unselected, which must not make the select ambiguous.
bazel test "$@" //:test_runtime_cpu //:test_gpu_only_pytest //:test_gpu_dev_pytest --@runtime//_variants:extra_cpu=True --test_output=errors

# Two configurations of one package in one binary.
bazel test "$@" //:test_diamond --@runtime//_variants:extra_cpu=True --test_output=errors
bazel test "$@" //:test_runtime_gpu --@runtime//_variants:extra_gpu=True --test_output=errors

# Without a flag, `runtime` fails with the first set's message.
if out=$(bazel build "$@" //:test_runtime_cpu 2>&1); then
  echo "Expected //:test_runtime_cpu to fail without flags!"
  exit 1
fi
if [[ "$out" != *"Set one of the _variants flags on your pycross repo: extra_cpu, extra_gpu"* ]]; then
  echo "Unexpected error message:"
  echo "$out"
  exit 1
fi
# Packages that don't depend on the variants install once, however many repo
# configurations reach them. pytest has variant-gated edges, so it doesn't.
installs=$(bazel aquery "$@" 'mnemonic("PycrossWheelInstall", deps(//:test_cpu_only + //:test_runtime_cpu + //:test_gpu_only_pytest + //:test_gpu_dev_pytest))' \
  --@runtime//_variants:extra_cpu=True --output=text 2>/dev/null | grep "^  Outputs:")
for pkg in iniconfig@1.1.1 iniconfig@2.0.0 packaging@26.3 pluggy@1.7.0; do
  count=$(grep -c "_lock/\(_reset_\)\?${pkg} (TreeArtifact)" <<<"$installs" || true)
  if [[ "$count" != 1 ]]; then
    echo "Expected 1 install of ${pkg}, got ${count}:"
    echo "$installs"
    exit 1
  fi
done

echo "Overlapping conflict tests passed."
