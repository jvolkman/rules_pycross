#!/bin/bash
# Builds a uv git source from file:// remotes that this script creates, so
# nothing needs network access for git. The source has a submodule and a Git
# LFS file. Checks that:
#  - the submodule's files are in the sdist and the built package;
#  - the archive bytes match across output bases, including one where git must
#    fall back to a full fetch (protocol v0 can't fetch unadvertised commits);
#  - without lfs = true, the LFS file stays a pointer;
#  - with lfs = true, a missing git-lfs fails clearly, and if the host has
#    git-lfs, the object is fetched.
set -euo pipefail

cd "$(dirname "$0")"

fixtures="$(mktemp -d)"
cleanup() {
  for ob in "$fixtures"/ob_*; do
    bazel --output_base="$ob" clean --expunge >/dev/null 2>&1 || true
  done
  rm -rf "$fixtures" uv.lock uv_lfs.lock || true
}
trap cleanup EXIT

git_() {
  # Hosts (e.g. GitHub runners) may configure the LFS filter globally; the
  # fixture writes LFS pointers by hand, so keep git-lfs out of it.
  git -c protocol.file.allow=always -c init.defaultBranch=main \
    -c user.name=e2e -c user.email=e2e@example.com -c commit.gpgsign=false \
    -c filter.lfs.clean= -c filter.lfs.smudge= -c filter.lfs.process= -c filter.lfs.required=false "$@"
}

# Submodule: lib/vendor. The pinned commit is not the branch tip.
git_ init -q "$fixtures/sub"
cat >"$fixtures/sub/data.py" <<'EOF'
DATA = "from submodule"
EOF
touch "$fixtures/sub/__init__.py"
git_ -C "$fixtures/sub" add -A
git_ -C "$fixtures/sub" commit -qm pinned
sub_sha="$(git -C "$fixtures/sub" rev-parse HEAD)"
echo unpinned >"$fixtures/sub/later.txt"
git_ -C "$fixtures/sub" add -A
git_ -C "$fixtures/sub" commit -qm later

# Superproject: a flit package whose lib/vendor is the submodule, plus an LFS
# file. The pointer and object are written by hand so that creating the
# fixture doesn't need git-lfs.
lib="$fixtures/lib"
git_ init -q "$lib"
cat >"$lib/pyproject.toml" <<'EOF'
[build-system]
requires = ["flit_core>=3.4"]
build-backend = "flit_core.buildapi"

[project]
name = "lib"
version = "0.1.0"
description = "git_sources e2e fixture"
EOF
mkdir -p "$lib/lib"
echo 'from lib.vendor.data import DATA' >"$lib/lib/__init__.py"
blob="real LFS content"
oid="$(printf '%s' "$blob" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1)"
printf 'version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize %s\n' "$oid" "${#blob}" >"$lib/lib/blob.txt"
mkdir -p "$lib/.git/lfs/objects/${oid:0:2}/${oid:2:2}"
printf '%s' "$blob" >"$lib/.git/lfs/objects/${oid:0:2}/${oid:2:2}/$oid"
echo 'lib/blob.txt filter=lfs diff=lfs merge=lfs -text' >"$lib/.gitattributes"
git_ -C "$lib" submodule add -q "file://$fixtures/sub" lib/vendor
git -C "$lib/lib/vendor" -c advice.detachedHead=false checkout -q "$sub_sha"
git_ -C "$lib" add -A
git_ -C "$lib" commit -qm pinned
lib_sha="$(git -C "$lib" rev-parse HEAD)"
echo later >"$lib/later.txt"
git_ -C "$lib" add -A
git_ -C "$lib" commit -qm later
lib_tip="$(git -C "$lib" rev-parse HEAD)"

# The LFS lock pins a different commit so that its sdist is a separate repo.
sed -e "s|@LIB_URL@|file://$lib|g" -e "s|@LIB_SHA@|$lib_sha|g" uv.lock.in >uv.lock
sed -e "s|@LIB_URL@|file://$lib?lfs=true|g" -e "s|@LIB_SHA@|$lib_tip|g" uv.lock.in >uv_lfs.lock

# GIT_ALLOW_PROTOCOL (see .bazelrc) lets git clone file:// submodules.
bazel test "$@" //...

# Prints the path of the archive behind `$2//lib:sdist` in output base `$1`,
# fetching it if needed. Extra arguments go to bazel query.
archive_in() {
  local ob="$1" hub="$2" label
  shift 2
  label="$(bazel --output_base="$ob" query --repo_contents_cache= "$@" \
    "kind('source file', deps($hub//lib:sdist))" 2>/dev/null | grep 'lib-0.1.0.tar.gz$')"
  label="${label#@@}"
  echo "$ob/external/${label%%//*}/file/lib-0.1.0.tar.gz"
}

first="$(archive_in "$(bazel info output_base 2>/dev/null)" @uv)"
echo "Checking $first"
listing="$(tar -tzf "$first")"
grep -qx 'repo/lib/vendor/data.py' <<<"$listing" || { echo "ERROR: submodule file missing" >&2; exit 1; }
if grep -E '(^|/)\.git(/|$)' <<<"$listing"; then
  echo "ERROR: archive contains .git entries" >&2
  exit 1
fi
if ! tar -xzOf "$first" repo/lib/blob.txt | grep -q '^oid sha256:'; then
  echo "ERROR: LFS file is not a pointer without lfs = true" >&2
  exit 1
fi

# A fresh output base, with the repo contents cache off, fetches again. Protocol
# v0 refuses the shallow fetch of a non-tip commit, so this takes the fallback.
second="$(archive_in "$fixtures/ob_second" @uv \
  --repo_env=GIT_CONFIG_COUNT=1 --repo_env=GIT_CONFIG_KEY_0=protocol.version --repo_env=GIT_CONFIG_VALUE_0=0)"
if ! cmp "$first" "$second"; then
  echo "ERROR: archives differ between fetches" >&2
  exit 1
fi
echo "Archives are byte-identical."

# lfs = true without git-lfs. Loading the sdist label fetches its archive.
nolfs="$fixtures/nolfs"
mkdir -p "$nolfs"
printf '#!/bin/sh\nexit 1\n' >"$nolfs/git-lfs"
chmod +x "$nolfs/git-lfs"
if out="$(bazel --output_base="$fixtures/ob_nolfs" query --repo_contents_cache= \
  --repo_env=PATH="$nolfs:$PATH" 'deps(@uv_lfs//lib:sdist)' 2>&1)"; then
  echo "ERROR: expected the lfs = true fetch to fail without git-lfs" >&2
  exit 1
fi
if ! grep -q 'sets lfs = true, but `git lfs` is not available' <<<"$out"; then
  echo "$out" >&2
  echo "ERROR: missing git-lfs error message" >&2
  exit 1
fi
echo "lfs = true fails clearly without git-lfs."

if git lfs version >/dev/null 2>&1; then
  lfs_archive="$(archive_in "$fixtures/ob_lfs" @uv_lfs)"
  if [ "$(tar -xzOf "$lfs_archive" repo/lib/blob.txt)" != "$blob" ]; then
    echo "ERROR: LFS object was not fetched with lfs = true" >&2
    exit 1
  fi
  echo "lfs = true fetched the LFS object."
else
  echo "git-lfs is not installed; skipping the LFS fetch check."
fi
