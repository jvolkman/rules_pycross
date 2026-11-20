#!/bin/bash
set -euo pipefail

# Build all aliases (this verifies the lock repo works without testing the python scripts directly)
# This uses the variant-a flag to satisfy typing-extensions select().
# group-a is the default (via default-groups), so idna doesn't need explicit flags.
bazel build "$@" //... --@project//_variants:extra_variant-a=True

# Test variant A
echo "Testing Variant A..."
bazel test "$@" //:test_variant_a --@project//_variants:extra_variant-a=True --test_output=errors

# Test variant B
echo "Testing Variant B..."
bazel test "$@" //:test_variant_b --@project//_variants:extra_variant-b=True --test_output=errors

# Test that default-groups makes group-a the default for idna.
# This exercises the default_variants code path in thin_package_repo.bzl:
# the select() should have a //conditions:default entry pointing to idna 3.7.
echo "Testing default group (idna should be 3.7 without flags)..."
bazel test "$@" //:test_default_group --@project//_variants:extra_variant-a=True --test_output=errors

# Verify error without flags for extras (which have no default)
echo "Testing without flags (should fail for extras)..."
if out=$(bazel build "$@" //:test_variant_a 2>&1); then
  echo "Expected //:test_variant_a build to fail without flags!"
  exit 1
fi
if [[ "$out" != *"Set one of"* ]]; then
  echo "Expected error message to contain 'Set one of', got:"
  echo "$out"
  exit 1
fi
if out=$(bazel build "$@" //... 2>&1); then
  echo "Expected //... build to fail without flags!"
  exit 1
fi
if [[ "$out" != *"Set one of"* ]]; then
  echo "Expected //... error message to contain 'Set one of', got:"
  echo "$out"
  exit 1
fi
echo "Failed as expected."

# Verify that under unavailable_package_mode=fail_at_execution without variant flags:
# 1. Analysis (cquery) succeeds for both :pkg and :maybe.
# 2. Execution (build) fails with the same "Set one of" message.
echo "Testing without flags under unavailable_package_mode=fail_at_execution..."
bazel cquery "$@" "@project//typing_extensions:pkg + @project//typing_extensions:maybe" \
  --@rules_pycross//pycross/settings:unavailable_package_mode=fail_at_execution >/dev/null
if out=$(bazel build "$@" @project//typing_extensions:pkg --@rules_pycross//pycross/settings:unavailable_package_mode=fail_at_execution 2>&1); then
  echo "Expected @project//typing_extensions:pkg build to fail at execution without flags!"
  exit 1
fi
if [[ "$out" != *"Set one of"* ]]; then
  echo "Expected fail_at_execution error message to contain 'Set one of', got:"
  echo "$out"
  exit 1
fi
echo "Deferred execution failure without flags passed."

# Verify that when a variant IS selected, a platform where the package's fork
# does not match (Windows for typing-extensions, which has sys_platform != 'win32')
# falls through to //conditions:default (no_match_error for :pkg, _empty_library for :maybe)
# rather than failing with the unselected-variant error.
echo "Testing selected variant on non-matching platform (Windows)..."
bazel cquery "$@" "@project//typing_extensions:pkg + @project//typing_extensions:maybe" \
  --platforms=//:plat_windows_x86_64 --@project//_variants:extra_variant-a=True >/dev/null
echo "Selected variant on non-matching platform passed."

# Test platform transition: @project_pinned has variant-a pinned via flags on the member import.
# This should resolve typing-extensions 4.11.0 without any --flag arguments,
# both via direct @project_pinned//typing_extensions and via :maybe in all_requirements.
echo "Testing platform transition (variant-a pinned via flags)..."
bazel test "$@" //:test_transition_pinned //:test_transition_pinned_maybe --test_output=errors
echo "Platform transition test passed."

# Test flags-only and settings-only transitions (no constraint_values) and transitioned modules_mapping targets.
echo "Testing flags-only transition and modules_mapping..."
bazel test "$@" //:test_transition_flags_only //:test_transition_settings //:test_auto_pin --test_output=errors
bazel build "$@" //:transition_modules_mappings
echo "Flags-only transition test passed."

# Verify path mapping shares PycrossWheelDir and PycrossWheelInstall outputs
# across compilation modes while keeping incompatible precompile modes separate.
echo "Testing path mapping across compilation modes..."
pm_cache="$(mktemp -d)"
trap 'rm -rf "$pm_cache"' EXIT
pm_flags=(
  --experimental_output_paths=strip
  --disk_cache="$pm_cache"
  --remote_cache=
  --nouse_action_cache
  --@project//_variants:extra_variant-a=True
)
pm_targets=(@project//typing_extensions:wheel @project//typing_extensions:pkg)

check_pm_log() {
  local log="$1"
  local want_dir="$2"
  local want_install="$3"
  python3 - "$log" "$want_dir" "$want_install" <<'PY'
import json, sys

log_path, want_dir, want_install = sys.argv[1], sys.argv[2] == "hit", sys.argv[3] == "hit"
dec = json.JSONDecoder()
text = open(log_path).read()
seen = {}
idx = 0
while idx < len(text):
    while idx < len(text) and text[idx].isspace():
        idx += 1
    if idx >= len(text):
        break
    obj, idx = dec.raw_decode(text, idx)
    mnemonic = obj.get("mnemonic", "")
    label = obj.get("targetLabel", "")
    if mnemonic in ("PycrossWheelDir", "PycrossWheelInstall") and "typing-extensions" in label:
        seen[mnemonic] = bool(obj.get("cacheHit", False))

expected = {"PycrossWheelDir": want_dir, "PycrossWheelInstall": want_install}
if seen != expected:
    raise SystemExit(f"Path-mapping cache mismatch: expected {expected}, got {seen}")
PY
}

# 1. fastbuild -> opt with precompile disabled: both actions hit the disk cache.
bazel build "${pm_flags[@]}" -c fastbuild \
  --@rules_python//python/config_settings:precompile=force_disabled \
  "${pm_targets[@]}" >/dev/null
bazel build "${pm_flags[@]}" -c opt \
  --@rules_python//python/config_settings:precompile=force_disabled \
  --execution_log_json_file="$pm_cache/opt_noprecompile.json" \
  "${pm_targets[@]}" >/dev/null
check_pm_log "$pm_cache/opt_noprecompile.json" hit hit

# 2. Precompile enabled: opt (unchecked_hash) misses fastbuild (checked_hash)
#    for PycrossWheelInstall, while dbg (checked_hash) hits fastbuild.
bazel build "${pm_flags[@]}" -c fastbuild \
  --@rules_python//python/config_settings:precompile=force_enabled \
  "${pm_targets[@]}" >/dev/null
bazel build "${pm_flags[@]}" -c opt \
  --@rules_python//python/config_settings:precompile=force_enabled \
  --execution_log_json_file="$pm_cache/opt_precompile.json" \
  "${pm_targets[@]}" >/dev/null
check_pm_log "$pm_cache/opt_precompile.json" hit miss

bazel build "${pm_flags[@]}" -c dbg \
  --@rules_python//python/config_settings:precompile=force_enabled \
  --execution_log_json_file="$pm_cache/dbg_precompile.json" \
  "${pm_targets[@]}" >/dev/null
check_pm_log "$pm_cache/dbg_precompile.json" hit hit
echo "Path mapping test passed."
