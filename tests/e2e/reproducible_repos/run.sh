#!/bin/bash
set -euo pipefail
shopt -s nullglob

# pycross_wheel_file and pycross_sdist_repo repos are marked reproducible, so
# Bazel's repo contents cache may share them across output bases and machines. It reuses an entry
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
checked_sdist=0
checked_wheel=0
checked_pure=0
failed=0
for marker in "$first"/@*.marker; do
  repo="$(basename "$marker" .marker)"
  repo="${repo#@}"

  if grep -q 'rules_pycross_internal//' "$marker"; then
    echo "Comparing tool repo $repo"
    if ! diff -u "$marker" "$second/@$repo.marker"; then
      echo "ERROR: $repo recorded different inputs in each output base" >&2
      failed=1
    fi
    if ! diff -r "$first/$repo" "$second/$repo"; then
      echo "ERROR: $repo has different contents in each output base" >&2
      failed=1
    fi
    if [[ "$repo" == *"__sdist_iniconfig"* ]]; then
      if ! grep -q 'iniconfig.patch' "$marker"; then
        echo "ERROR: $repo did not record pre_build_patches file in $marker" >&2
        failed=1
      fi
      if ! grep -q 'pycross_patch.py' "$marker"; then
        echo "ERROR: $repo did not record pycross_patch.py in $marker" >&2
        failed=1
      fi
      if grep -q 'iniconfig-2.0.0.tar.gz' "$marker"; then
        echo "ERROR: $repo recorded verified remote sdist in $marker" >&2
        failed=1
      fi
      checked_sdist=$((checked_sdist + 1))
    else
      if grep -q 'pycross_patch.py' "$marker"; then
        echo "ERROR: unpatched repo $repo should not watch pycross_patch.py" >&2
        failed=1
      fi
      checked_wheel=$((checked_wheel + 1))
    fi
    checked=$((checked + 1))
  elif [[ "$repo" == rules_pycross++* && "$repo" != *rules_pycross_internal ]]; then
    echo "Comparing reproducible pycross repo $repo"
    if ! diff -u "$marker" "$second/@$repo.marker"; then
      echo "ERROR: $repo recorded different inputs in each output base" >&2
      failed=1
    fi
    if ! diff -r "$first/$repo" "$second/$repo"; then
      echo "ERROR: $repo has different contents in each output base" >&2
      failed=1
    fi
    checked_pure=$((checked_pure + 1))
  fi
done

if [ "$checked_sdist" -eq 0 ]; then
  echo "ERROR: fetched no sdist repo" >&2
  exit 1
fi
if [ "$checked_wheel" -eq 0 ]; then
  echo "ERROR: fetched no unpatched wheel repo" >&2
  exit 1
fi
if [ "$checked_pure" -eq 0 ]; then
  echo "ERROR: fetched no pure pycross repo" >&2
  exit 1
fi
if [ "$checked" -eq 0 ]; then
  echo "ERROR: fetched no repo that runs an internal tool" >&2
  exit 1
fi
if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "All $checked tool repos and $checked_pure pure pycross repos match across output bases."
