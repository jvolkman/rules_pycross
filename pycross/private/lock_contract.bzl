"""Cross-repository naming conventions and target/key contracts between lock repos.

Owns the shared naming conventions connecting `lock_repo_creation`, `state_repo`,
`spoke_repo`, `lock_render/*`, `thin_package_repo`, `thin_repo/*`, and
`variant_resolver`.
"""

load(":util.bzl", "parse_package_key", "underscore_name")

# ---- Repository naming -------------------------------------------------------

def state_repo_name(workspace):
    """Return the workspace control/state repository name (`<workspace>__state`)."""
    return "{}__state".format(workspace)

def spoke_repo_name(workspace, pkg_name):
    """Return the per-package spoke repository name (`<workspace>__pkg_<underscore_name>`)."""
    return "{}__pkg_{}".format(workspace, underscore_name(pkg_name))

def build_repo_name(workspace):
    """Return the default build-tools thin repository name (`<workspace>__build`)."""
    return "{}__build".format(workspace)

def is_reserved_internal_repo_name(workspace, repo_name):
    """Return True if `repo_name` collides with an internal repo prefix owned by `workspace`."""
    return (
        repo_name == state_repo_name(workspace) or
        repo_name.startswith("{}__pkg_".format(workspace)) or
        repo_name.startswith("{}__whl_".format(workspace)) or
        repo_name.startswith("{}__sdist".format(workspace))
    )

# ---- Package & flag constants ------------------------------------------------

VARIANTS_PACKAGE = "_variants"
MARKERS_PACKAGE = "_markers"

VARIANT_STATE_TARGET = "_state"
VARIANTS_STRING_FLAG_TARGET = "_variants"

# Key prefixes inside the canonical `@<ws>__state//:_state` JSON payload.
VARIANT_STATE_PIN_PREFIX = "p:"
VARIANT_STATE_DEFAULT_PREFIX = "d:"
VARIANT_STATE_USABLE_PREFIX = "u:"

def variant_state_key(prefix, set_suffix):
    """Return a canonical `@<ws>__state//:_state` JSON key (`p:<set>`, `d:<set>`, or `u:<set>`)."""
    return prefix + set_suffix

def _require_repo(repo, helper_name):
    if not repo:
        fail("{} requires a non-empty repository name".format(helper_name))
    return repo

def marker_match_target_name(eval_name):
    """Return the matching config_setting name `<eval_name>_match`."""
    return "{}_match".format(eval_name)

def constraint_setting_name(constraint):
    """Return the constraint config_setting name `is_<constraint>`."""
    return "is_{}".format(constraint)

def unselected_target_name(set_suffix):
    """Return the unselected conflict-set config_setting name `_unselected_<set_suffix>`."""
    return "_unselected_{}".format(set_suffix)

def variants_flag_label(repo_name, flag = VARIANTS_STRING_FLAG_TARGET):
    """Return `@<repo_name>//_variants:<flag>`."""
    return "@{}//{}:{}".format(_require_repo(repo_name, "variants_flag_label"), VARIANTS_PACKAGE, flag)

# ---- State repository labels (`@<ws>__state`) --------------------------------

def state_target_label(state_repo, target):
    """Return cross-repo `@<state_repo>//:<target>`."""
    return "@{}//:{}".format(_require_repo(state_repo, "state_target_label"), target)

def state_flag_label(state_repo):
    """Return cross-repo `@<state_repo>//:_state`."""
    return state_target_label(state_repo, VARIANT_STATE_TARGET)

def state_variant_state_label(state_repo):
    """Return cross-repo `@<state_repo>//:_variant_state`."""
    return state_target_label(state_repo, "_variant_state")

def state_constraint_label(state_repo, constraint):
    """Return cross-repo `@<state_repo>//:is_<constraint>`."""
    return state_target_label(state_repo, constraint_setting_name(constraint))

def state_unselected_label(state_repo, set_suffix):
    """Return cross-repo `@<state_repo>//:_unselected_<set_suffix>`."""
    return state_target_label(state_repo, unselected_target_name(set_suffix))

def state_reset_bzl_label(state_repo):
    """Return cross-repo `@<state_repo>//:reset.bzl`."""
    return state_target_label(state_repo, "reset.bzl")

# ---- Thin member local marker/constraint labels (`//_markers:...`) -----------

def member_marker_match_label(eval_name):
    """Return repo-local `//_markers:<eval_name>_match`."""
    return "//{}:{}".format(MARKERS_PACKAGE, marker_match_target_name(eval_name))

def member_constraint_label(state_repo, constraint, resolution_marker_exprs = None):
    """Return the config_setting label for a pin constraint in a thin repo.

    Resolution-marker constraints (and compound `{variant, marker}` constraints)
    live in the member's local `//_markers` package; bare conflict variant
    constraints live in `@<state_repo>`.

    Args:
        state_repo: Apparent name of the workspace's `@<ws>__state` repo.
        constraint: Constraint key from a pin dict.
        resolution_marker_exprs: Optional member `resolution_marker_exprs` dict.

    Returns:
        Config setting label string.
    """
    if resolution_marker_exprs and constraint in resolution_marker_exprs:
        return "//{}:{}".format(MARKERS_PACKAGE, constraint_setting_name(constraint))
    return state_constraint_label(state_repo, constraint)

# ---- Spoke repository target names & labels (`@<ws>__pkg_<name>`) ------------

def _slot_sfx(slot):
    return "_" + slot if slot else ""

def spoke_pkg_target(slot = "", extra = ""):
    """Return version-free public library target name (`pkg[_<slot>]` or `[<extra>][_<slot>]`)."""
    base = "[{}]".format(extra) if extra else "pkg"
    return base + _slot_sfx(slot)

def spoke_raw_target(slot = "", extra = ""):
    """Return version-free raw library target name (`_raw[_<slot>]` or `_raw_[<extra>][_<slot>]`)."""
    base = "_raw_[{}]".format(extra) if extra else "_raw"
    return base + _slot_sfx(slot)

def spoke_wheel_target(slot = "", extra = ""):
    """Return version-free `pycross_wheel_dir` target name (`wheel[_<slot>]`)."""
    base = "wheel_[{}]".format(extra) if extra else "wheel"
    return base + _slot_sfx(slot)

def spoke_wheel_sel_target(slot = "", extra = ""):
    """Return internal wheel-selector alias target name (`_wheel_sel[_<slot>]`)."""
    base = "_wheel_sel_[{}]".format(extra) if extra else "_wheel_sel"
    return base + _slot_sfx(slot)

def spoke_sdist_target(slot = "", extra = ""):
    """Return version-free sdist alias target name (`sdist[_<slot>]`)."""
    base = "sdist_[{}]".format(extra) if extra else "sdist"
    return base + _slot_sfx(slot)

def spoke_dist_info_target(slot = "", extra = ""):
    """Return version-free dist_info target name (`dist_info[_<slot>]`)."""
    base = "dist_info_[{}]".format(extra) if extra else "dist_info"
    return base + _slot_sfx(slot)

def spoke_wheel_available_target(slot = "", extra = ""):
    """Return version-free wheel availability config_setting name (`_wheel_available[_<slot>]`)."""
    base = "_wheel_available_[{}]".format(extra) if extra else "_wheel_available"
    return base + _slot_sfx(slot)

def spoke_sdist_deps_target(slot = "", extra = ""):
    """Return version-free sdist runtime deps proxy target name (`_sdist_deps[_<slot>]`)."""
    base = "_sdist_deps_[{}]".format(extra) if extra else "_sdist_deps"
    return base + _slot_sfx(slot)

def spoke_reset_gate_target(slot = "", extra = ""):
    """Return version-free caller-facing reset gate target name (`_reset_gate[_<slot>]`)."""
    base = "_reset_gate_[{}]".format(extra) if extra else "_reset_gate"
    return base + _slot_sfx(slot)

def spoke_raw_reset_gate_target(slot = "", extra = ""):
    """Return version-free cycle-member raw reset gate target name (`_raw_reset_gate[_<slot>]`)."""
    base = "_raw_reset_gate_[{}]".format(extra) if extra else "_raw_reset_gate"
    return base + _slot_sfx(slot)

def spoke_scc_reset_gate_target(slot = "", extra = ""):
    """Return version-free cycle-SCC aggregate reset gate target name (`_scc_reset_gate[_<slot>]`)."""
    base = "_scc_reset_gate_[{}]".format(extra) if extra else "_scc_reset_gate"
    return base + _slot_sfx(slot)

def spoke_hook_target(slot = ""):
    """Return version-free hook target alias name (`pkg[_<slot>]`) inside a spoke `<subdir>/`."""
    return "pkg" + _slot_sfx(slot)

def spoke_target_label(spoke_repo, target, current_spoke = ""):
    """Return `:<target>` if `spoke_repo == current_spoke`, else `@<spoke_repo>//:<target>`."""
    if current_spoke and spoke_repo == current_spoke:
        return ":" + target
    return "@{}//:{}".format(_require_repo(spoke_repo, "spoke_target_label"), target)

def cycle_node_key(pkg_key, slot = ""):
    """Return a version-free node/slot key preserving `.extra` for `parse_package_key`.

    Formats single-version keys as `name` / `name[extra]` and multi-version
    fork slots as `name@s0` / `name[extra]@s0`.

    Args:
        pkg_key: Package key in the lock.
        slot: Fork slot string (`""` or `"s0"`, `"s1"`, ...).

    Returns:
        Version-free node/slot key string.
    """
    parts = parse_package_key(pkg_key)
    base = "{}[{}]".format(parts.name, parts.extra) if parts.extra else parts.name
    return "{}@{}".format(base, slot) if slot else base

def spoke_slot_label(workspace_name, slot_key, kind = "pkg", subdir = ""):
    """Resolve a version-free `slot_key` (`name([extra])[@slot]`) to its spoke target label.

    Args:
        workspace_name: Workspace name.
        slot_key: Version-free slot key (`foo`, `foo@s0`, `foo[opt]`, `foo[opt]@s1`).
        kind: Target role (`"pkg"`, `"raw"`, `"wheel"`, `"sdist"`, `"dist_info"`,
            `"wheel_available"`, or `"hook"`).
        subdir: Spoke hook subdirectory when `kind == "hook"` (e.g. `"_cargo"`).

    Returns:
        Cross-repo label string `@<ws>__pkg_<name>//:<target>` (or `//<subdir>:<target>`).
    """
    _require_repo(workspace_name, "spoke_slot_label")
    parts = parse_package_key(slot_key)
    spoke = spoke_repo_name(workspace_name, parts.name)
    slot = parts.version
    extra = parts.extra
    if kind == "pkg":
        return "@{}//:{}".format(spoke, spoke_pkg_target(slot, extra))
    if kind == "raw":
        return "@{}//:{}".format(spoke, spoke_raw_target(slot, extra))
    if kind == "wheel":
        return "@{}//:{}".format(spoke, spoke_wheel_target(slot, extra))
    if kind == "sdist":
        return "@{}//:{}".format(spoke, spoke_sdist_target(slot, extra))
    if kind == "dist_info":
        return "@{}//:{}".format(spoke, spoke_dist_info_target(slot, extra))
    if kind == "wheel_available":
        return "@{}//:{}".format(spoke, spoke_wheel_available_target(slot, extra))
    if kind == "hook":
        return "@{}//{}:{}".format(spoke, subdir, spoke_hook_target(slot))
    fail("Unknown spoke label kind: {}".format(kind))

# ---- Package structure & wheel directory helpers -----------------------------

def is_extras_proxy(pkg_key, pkg):
    """Return True if `pkg_key` is an extras-only proxy (extra key with no own wheels).

    Args:
        pkg_key: Package key in the lock (or version-free slot key).
        pkg: Package dict from the lock (or slimmed thin-repo package dict).

    Returns:
        Bool indicating whether `pkg_key` is an extras proxy delegating to its base package.
    """
    if "extras_proxy" in pkg:
        return pkg["extras_proxy"]
    return not pkg.get("wheel_candidates") and bool(parse_package_key(pkg_key).extra)

def whldir_name(pkg_key):
    """Return the deterministic `<pkg>-<version>[~<tag>].whldir` TreeArtifact directory name.

    Args:
        pkg_key: Base package key in the lock.

    Returns:
        Directory name string (e.g. `typing_extensions-4.12.2.whldir`).
    """
    parts = parse_package_key(pkg_key)
    ver_with_tag = "{}~{}".format(parts.version, parts.tag) if parts.tag else parts.version
    return "{}-{}.whldir".format(underscore_name(parts.name), ver_with_tag)
