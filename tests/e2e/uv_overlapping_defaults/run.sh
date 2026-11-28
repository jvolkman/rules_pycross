#!/bin/bash
set -euo pipefail

# (a) With no flags, default-groups = ["g-a"] applies across sets 1 and 2.
bazel test "$@" //:test_default_a //:test_default_dup_a //:test_pinned_b //:test_only_a //:test_transitioned_y --test_output=errors

# (b) Selecting g-b via bool_flag or string_flag drops the g-a default in set 2
# instead of activating g-a and g-b simultaneously. Pinned/auto-pinned repos keep their pins.
bazel test "$@" //:test_flag_b //:test_only_a //:test_pinned_b \
  --@app_default//_variants:group_g-b=True --test_output=errors
bazel test "$@" //:test_flag_b //:test_only_a //:test_pinned_b \
  --@app_default//_variants=group_g-b --test_output=errors

# (b2) 3-set chain: selecting x suppresses default g-a in set 1 and selects x in sets 2 & 3.
# Transitioned repo `transitioned_y` ignores sibling extra_x and keeps g-a + y.
bazel test "$@" //:test_flag_x //:test_only_a //:test_transitioned_y \
  --@app_default//_variants:extra_x=True --test_output=errors
bazel test "$@" //:test_flag_x //:test_only_a //:test_transitioned_y \
  --@app_default//_variants=extra_x --test_output=errors

# (b3) Selecting non-conflicting chain endpoint y keeps default g-a in sets 1 & 2;
# selecting both endpoints g-b and y suppresses default g-a in set 2 and picks y in set 3.
bazel test "$@" //:test_default_a_with_y --@app_default//_variants:extra_y=True --test_output=errors
bazel test "$@" //:test_chain_b_and_y --@app_default//_variants=group_g-b,extra_y --test_output=errors

# (c) Pinned `pinned_b` ignores sibling flag selecting g-a.
bazel test "$@" //:test_pinned_b --@app_default//_variants:group_g-a=True --test_output=errors

# (d) Aquery dedup check: two thin repos with identical derived variant state
# (`app_default` and `app_default_dup`) produce one PycrossWheelInstall per shared package,
# including pytest (which carries variant-gated dependency edges).
installs=$(bazel aquery "$@" \
  'mnemonic("PycrossWheelInstall", deps(//:test_default_a + //:test_default_dup_a))' \
  --output=text 2>/dev/null | grep "^  Outputs:")
for pkg in "__pkg_iniconfig/\(_reset_\)\?pkg_s0" "__pkg_pytest/\(_reset_\)\?pkg\(_s[0-9]\+\)\?" "__pkg_packaging/\(_reset_\)\?pkg" "__pkg_pluggy/\(_reset_\)\?pkg"; do
  count=$(grep -c "${pkg} (TreeArtifact)" <<<"$installs" || true)
  if [[ "$count" != 1 ]]; then
    echo "Expected 1 install of ${pkg} across identical-state thin repos, got ${count}:"
    echo "$installs"
    exit 1
  fi
done

echo "Overlapping default-groups conflict tests passed."
