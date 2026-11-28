#!/bin/bash
set -euo pipefail

# Verifies O(1) incremental repo invalidation on a single-package version bump (#443):
# bumping six 1.16.0 -> 1.17.0 invalidates ONLY @uv__pkg_six and
# @uv__whl_six__t_py2_py3_none_any, leaving:
#   - @uv (thin member facade)
#   - @uv__state (workspace variant state, reset.bzl, _backend/)
#   - @uv__pkg_python_dateutil (upstream spoke depending directly on six)
#   - @uv__pkg_cowsay (sibling spoke)
#   - their wheel repos
# completely untouched.

cd "$(dirname "$0")"

tmp_dir="$(mktemp -d)"
cp uv.lock "$tmp_dir/uv.lock.orig"

cleanup() {
  cp "$tmp_dir/uv.lock.orig" uv.lock
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

# 1. Warm build with six 1.16.0 and active conflict variant extra_a (fetches @uv__state).
bazel test "$@" \
  --@uv//_variants=extra_a \
  --test_env=EXPECTED_SIX_VERSION=1.16.0 \
  //:test_all --test_output=errors

output_base="$(bazel info output_base)"
python3 - "$output_base/external" "$tmp_dir/before.json" <<'PY'
import json, os, sys

ext_dir, out_path = sys.argv[1], sys.argv[2]
snap = {}
for entry in sorted(os.listdir(ext_dir)):
    if not entry.startswith("rules_pycross") or "+uv+" not in entry or entry.endswith(".marker"):
        continue
    full = os.path.join(ext_dir, entry)
    marker = os.path.join(ext_dir, f"@{entry}.marker")
    if os.path.islink(full):
        snap[entry] = {"kind": "symlink", "value": os.readlink(full)}
    elif os.path.exists(marker):
        with open(marker, "rb") as fh:
            snap[entry] = {"kind": "marker", "value": fh.read().hex()}
    else:
        snap[entry] = {"kind": "dir", "value": str(os.stat(full).st_mtime_ns)}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(snap, fh, indent=2, sort_keys=True)
PY

# 2. Bump ONLY six (1.16.0 -> 1.17.0) and run an incremental build with a Bazel profile.
cp uv.lock.v2 uv.lock
bazel test "$@" \
  --@uv//_variants=extra_a \
  --test_env=EXPECTED_SIX_VERSION=1.17.0 \
  --profile="$tmp_dir/inc_profile.json.gz" \
  --noslim_profile \
  //:test_all --test_output=errors

# 3. Verify repo fingerprints and Skyframe package creation / Starlark fetch events.
python3 - "$tmp_dir/before.json" "$output_base/external" "$tmp_dir/inc_profile.json.gz" <<'PY'
import gzip, json, os, sys

before_path, ext_dir, profile_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(before_path, "r", encoding="utf-8") as fh:
    before = json.load(fh)

after = {}
for entry in sorted(os.listdir(ext_dir)):
    if not entry.startswith("rules_pycross") or "+uv+" not in entry or entry.endswith(".marker"):
        continue
    full = os.path.join(ext_dir, entry)
    marker = os.path.join(ext_dir, f"@{entry}.marker")
    if os.path.islink(full):
        after[entry] = {"kind": "symlink", "value": os.readlink(full)}
    elif os.path.exists(marker):
        with open(marker, "rb") as fh:
            after[entry] = {"kind": "marker", "value": fh.read().hex()}
    else:
        after[entry] = {"kind": "dir", "value": str(os.stat(full).st_mtime_ns)}

# Identify canonical prefix (e.g. "rules_pycross++uv+") across Bazel versions.
uv_entries = [k for k in before if k.endswith("+uv")]
assert len(uv_entries) == 1, f"Expected single +uv repo in {sorted(before)}"
prefix = uv_entries[0][:-len("uv")]

unchanged_short = [
    "uv",
    "uv__state",
    "uv__pkg_cowsay",
    "uv__pkg_python_dateutil",
    "uv__whl_cowsay__t_py3_none_any",
    "uv__whl_python_dateutil__t_py2_py3_none_any",
]
changed_short = [
    "uv__pkg_six",
    "uv__whl_six__t_py2_py3_none_any",
]

for short in unchanged_short:
    repo = prefix + short
    assert repo in before and repo in after, f"Missing repo {repo} (before={sorted(before)}, after={sorted(after)})"
    assert before[repo] == after[repo], f"Expected unchanged repo {repo}, but fingerprint changed: {before[repo]} != {after[repo]}"

for short in changed_short:
    repo = prefix + short
    assert repo in before and repo in after, f"Missing bumped repo {repo}"
    assert before[repo] != after[repo], f"Expected bumped repo {repo} fingerprint to change!"

# Ensure no unexpected +uv+* repos changed or were newly created.
expected_changed = {prefix + s for s in changed_short}
all_uv_repos = {k for k in set(before) | set(after) if k.startswith(prefix + "uv")}
actual_changed = {k for k in all_uv_repos if before.get(k) != after.get(k)}
assert actual_changed == expected_changed, (
    f"Unexpected repo invalidation set: actual={sorted(actual_changed)}, expected={sorted(expected_changed)}"
)

with gzip.open(profile_path, "rt", encoding="utf-8") as fh:
    profile = json.load(fh)

reloaded_repos = set()
starlark_fetched_repos = set()
for ev in profile.get("traceEvents", []):
    cat = ev.get("cat", "")
    name = ev.get("name", "")
    if cat == "package creation":
        # Format: "@@<canonical_repo>//<pkg>" or "@<canonical_repo>//<pkg>"
        repo_part = name.split("//", 1)[0].lstrip("@")
        if repo_part.startswith(prefix + "uv"):
            reloaded_repos.add(repo_part)
    elif cat == "Starlark repository function call":
        repo_part = name.lstrip("@")
        if repo_part.startswith(prefix + "uv"):
            starlark_fetched_repos.add(repo_part)

assert reloaded_repos == expected_changed, (
    f"Expected ONLY {sorted(expected_changed)} to reload packages on 1-pkg bump, got {sorted(reloaded_repos)}"
)
unexpected_fetches = sorted(r for r in starlark_fetched_repos if r not in expected_changed)
assert not unexpected_fetches, (
    f"Unexpected Starlark repository re-fetches on 1-pkg bump: {unexpected_fetches}"
)

print(
    f"Verified O(1) incremental invalidation: "
    f"reloaded={sorted(reloaded_repos)}, unchanged={len(unchanged_short)} repos (including @uv, @uv__state, upstream @uv__pkg_python_dateutil)"
)
PY
