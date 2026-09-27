#!/bin/bash
set -euo pipefail
shopt -s nullglob

# pycross_wheel_file repos are marked reproducible, so Bazel's repo contents
# cache may share them across output bases and machines. It reuses an entry
# only when every input the repo recorded matches, and reusing it is only
# correct if the repo's contents match too. Fetch the same repos into two
# output bases and check that every repo that runs an internal tool records
# the same inputs and has the same contents in both.
#
# The repo contents cache is disabled so that each output base extracts its own
# Python interpreter, as another machine would. With it enabled, both output
# bases would resolve the interpreter into the same cache entry, which hides
# any input that embeds the interpreter's path.

cd "$(dirname "$0")"

output_bases="$(mktemp -d)"
cleanup() {
  for name in first second; do
    if [ -d "$output_bases/$name" ]; then
      bazel --output_base="$output_bases/$name" clean --expunge >/dev/null 2>&1 || true
    fi
  done
  rm -rf "$output_bases" || true
}
trap cleanup EXIT

# Loading the targets' dependencies fetches every repo they need, without the
# C++ toolchain that analyzing them requires. Arguments are not forwarded:
# query rejects CI's --config=remote, which only defines build options.
for name in first second; do
  bazel --output_base="$output_bases/$name" query --repo_contents_cache= 'deps(//...)' >/dev/null
done

first="$output_bases/first/external"
second="$output_bases/second/external"

checked=0
failed=0
for marker in "$first"/@*.marker; do
  # A repo that runs an internal tool records a file from the internal repo.
  grep -q 'rules_pycross_internal//' "$marker" || continue

  repo="$(basename "$marker" .marker)"
  repo="${repo#@}"
  echo "Comparing $repo"
  if ! diff -u "$marker" "$second/@$repo.marker"; then
    echo "ERROR: $repo recorded different inputs in each output base" >&2
    failed=1
  fi
  if ! diff -r "$first/$repo" "$second/$repo"; then
    echo "ERROR: $repo has different contents in each output base" >&2
    failed=1
  fi
  checked=$((checked + 1))
done

if [ "$checked" -eq 0 ]; then
  echo "ERROR: fetched no repo that runs an internal tool" >&2
  exit 1
fi
if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "All $checked repos that run an internal tool match across output bases."
