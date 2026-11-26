"""Cross-repository naming conventions and target/key contracts between lock repos.

Owns the shared naming conventions connecting `lock_repo_creation`, `package_repo`,
`lock_render/*`, `thin_package_repo`, `thin_repo/*`, and `variant_resolver`.
"""

load(":util.bzl", "parse_package_key", "sanitize_name", "underscore_name")

# ---- Repository naming -------------------------------------------------------

def pkgs_repo_name(workspace):
    """Return the backing workspace package repository name (`<workspace>__pkgs`)."""
    return "{}__pkgs".format(workspace)

def build_repo_name(workspace):
    """Return the default build-tools thin repository name (`<workspace>__build`)."""
    return "{}__build".format(workspace)

def sdist_repo_name(pkgs_repo, pkg_key):
    """Return the sdist build repository name (`<pkgs_repo>_sdist_<sanitized_key>`).

    Args:
        pkgs_repo: Name (apparent or canonical) of the backing `<ws>__pkgs` repo.
        pkg_key: Package key in the lock.

    Returns:
        Sdist repository name string.
    """
    return "{}_sdist_{}".format(pkgs_repo, sanitize_name(pkg_key))

# ---- Backing package labels & target names -----------------------------------

LOCK_PACKAGE = "_lock"
WHEEL_PACKAGE = "_wheel"
SDIST_PACKAGE = "_sdist"
VARIANTS_PACKAGE = "_variants"

VARIANT_STATE_TARGET = "_state"
VARIANT_STATE_LOCAL_LABEL = "//_lock:_state"
VARIANTS_STRING_FLAG_TARGET = "_variants"

# Key prefixes inside the canonical `//_lock:_state` JSON payload.
VARIANT_STATE_PIN_PREFIX = "p:"
VARIANT_STATE_DEFAULT_PREFIX = "d:"
VARIANT_STATE_USABLE_PREFIX = "u:"

def _require_repo(repo, helper_name):
    if not repo:
        fail("{} requires a non-empty repository name".format(helper_name))
    return repo

def local_lock_target_label(target):
    """Return repo-local `//_lock:<target>`."""
    return "//{}:{}".format(LOCK_PACKAGE, target)

def lock_label_prefix(workspace_repo):
    """Return `@<workspace_repo>//_lock:`."""
    return "@{}//{}:".format(_require_repo(workspace_repo, "lock_label_prefix"), LOCK_PACKAGE)

def wheel_label_prefix(workspace_repo):
    """Return `@<workspace_repo>//_wheel:`."""
    return "@{}//{}:".format(_require_repo(workspace_repo, "wheel_label_prefix"), WHEEL_PACKAGE)

def sdist_label_prefix(workspace_repo):
    """Return `@<workspace_repo>//_sdist:`."""
    return "@{}//{}:".format(_require_repo(workspace_repo, "sdist_label_prefix"), SDIST_PACKAGE)

def lock_target_label(workspace_repo, target):
    """Return cross-repo `@<workspace_repo>//_lock:<target>`."""
    return "@{}//{}:{}".format(_require_repo(workspace_repo, "lock_target_label"), LOCK_PACKAGE, target)

def variant_state_label(workspace_repo):
    """Return cross-repo `@<workspace_repo>//_lock:_state`."""
    return lock_target_label(workspace_repo, VARIANT_STATE_TARGET)

def variant_state_key(prefix, set_suffix):
    """Return a canonical `//_lock:_state` dict key (`<prefix><set_suffix>`)."""
    return prefix + set_suffix

def raw_target_name(pkg_key):
    """Return the underlying raw library target name `_raw_<pkg_key>`."""
    return "_raw_{}".format(pkg_key)

def wheel_target_name(pkg_key):
    """Return the backing wheel alias target name `_wheel_<pkg_key>`."""
    return "_wheel_{}".format(pkg_key)

def sdist_target_name(pkg_key):
    """Return the backing sdist alias target name `_sdist_<pkg_key>`."""
    return "_sdist_{}".format(pkg_key)

def dist_info_target_name(pkg_key):
    """Return the dist_info target name `_dist_info_<pkg_key>`."""
    return "_dist_info_{}".format(pkg_key)

def sdist_deps_target_name(pkg_key):
    """Return the sdist runtime deps proxy target name `_sdist_deps_<pkg_key>`."""
    return "_sdist_deps_{}".format(pkg_key)

def wheel_available_target_name(pkg_key):
    """Return the wheel availability config_setting name `_wheel_available_<pkg_key>`."""
    return "_wheel_available_{}".format(pkg_key)

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

def lock_raw_label(workspace_repo, pkg_key):
    """Return `@<workspace_repo>//_lock:_raw_<pkg_key>`."""
    return lock_target_label(workspace_repo, raw_target_name(pkg_key))

def lock_dist_info_prefix(workspace_repo):
    """Return `@<workspace_repo>//_lock:_dist_info_`."""
    return lock_label_prefix(workspace_repo) + "_dist_info_"

def lock_sdist_deps_label(workspace_repo, pkg_key):
    """Return `@<workspace_repo>//_lock:_sdist_deps_<pkg_key>`."""
    return lock_target_label(workspace_repo, sdist_deps_target_name(pkg_key))

def lock_wheel_available_label(workspace_repo, pkg_key):
    """Return `@<workspace_repo>//_lock:_wheel_available_<pkg_key>`."""
    return lock_target_label(workspace_repo, wheel_available_target_name(pkg_key))

def lock_marker_match_label(workspace_repo, eval_name):
    """Return `@<workspace_repo>//_lock:<eval_name>_match`."""
    return lock_target_label(workspace_repo, marker_match_target_name(eval_name))

def lock_constraint_label(workspace_repo, constraint):
    """Return `@<workspace_repo>//_lock:is_<constraint>`."""
    return lock_target_label(workspace_repo, constraint_setting_name(constraint))

def lock_unselected_label(workspace_repo, set_suffix):
    """Return `@<workspace_repo>//_lock:_unselected_<set_suffix>`."""
    return lock_target_label(workspace_repo, unselected_target_name(set_suffix))

# ---- Package structure & wheel directory helpers -----------------------------

def is_extras_proxy(pkg_key, pkg):
    """Return True if `pkg_key` is an extras-only proxy (extra key with no own wheels).

    Args:
        pkg_key: Package key in the lock.
        pkg: Package dict from the lock.

    Returns:
        Bool indicating whether `pkg_key` is an extras proxy delegating to its base package.
    """
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
