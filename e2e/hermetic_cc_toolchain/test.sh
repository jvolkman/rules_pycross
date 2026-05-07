#!/usr/bin/env bash

set -o errexit -o nounset

pattern="$PWD"
matched=0

while IFS= read -r -d '' file
do
  echo "checking for '$pattern' in $file"
  strings "$file" | grep "$pattern" && matched=1
done < <(find -L ./bazel-bin -iname "*.so" -print0)

if [[ "$matched" -eq 1 ]]; then
  echo "ERROR: some files contained '$pattern'"
  exit 1
fi
