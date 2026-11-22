#!/usr/bin/env bash
# Regenerates golden snapshots under tests/golden/ from @golden_snapshots.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
golden_dir="$repo_root/tests/golden"

cd "$repo_root"
bazel build @golden_snapshots//:all_goldens

output_base="$(bazel info output_base)"
manifest_rel="$(bazel cquery --output=files @golden_snapshots//:manifest.txt 2>/dev/null | head -n 1)"
if [[ -z "$manifest_rel" ]]; then
    echo "ERROR: could not query @golden_snapshots//:manifest.txt" >&2
    exit 1
fi
if [[ -f "$manifest_rel" ]]; then
    manifest_file="$manifest_rel"
else
    manifest_file="$output_base/$manifest_rel"
fi
if [[ ! -f "$manifest_file" ]]; then
    echo "ERROR: could not locate manifest file at '$manifest_file'" >&2
    exit 1
fi
snapshot_root="$(dirname "$manifest_file")"

# Remove stale generated snapshots while keeping fixtures/, scripts, BUILD.bazel, and repos.bzl.
find "$golden_dir" -type f -name '*.golden' -delete
find "$golden_dir" -mindepth 1 -type d -empty -delete

cp "$snapshot_root/manifest.txt" "$golden_dir/manifest.txt"
while IFS= read -r rel_path; do
    [[ -z "$rel_path" ]] && continue
    dest="$golden_dir/$rel_path"
    mkdir -p "$(dirname "$dest")"
    cp "$snapshot_root/$rel_path" "$dest"
done < "$snapshot_root/manifest.txt"

chmod 0644 "$golden_dir/manifest.txt"
find "$golden_dir" -type f -name '*.golden' -exec chmod 0644 {} +

count="$(wc -l < "$golden_dir/manifest.txt")"
echo "Updated $count golden snapshot files under tests/golden/."
