"""Metadata, requirements, backend forwarding, and hook-subdir files for thin package repos."""

load("//pycross/private:build_text.bzl", "alias")
load("//pycross/private:lock_contract.bzl", "spoke_slot_label", "state_repo_name")
load("//pycross/private:util.bzl", "base_package_key", "parse_package_key", "underscore_name")
load(":common.bzl", "NO_MATCH_ERROR_TARGET", "effective_base_target_dict", "is_key_platform_specific", "safe_name")
load(":selects.bzl", "target_select")

_requirement_func = """\
load("@pypackaging.bzl", "pypackaging")

def requirement(pkg):
    extra = None
    if "[" in pkg:
        pkg, extra = pkg.split("[", 1)
        extra = pypackaging.utils.canonicalize_name(extra.rstrip("]"))

    pkg = pypackaging.utils.canonicalize_name(pkg)
    pkg_dir = pkg.replace("-", "_")

    if extra:
        return "@@{repo_name}//%s:[%s]" % (pkg_dir, extra)
    return "@@{repo_name}//%s" % (pkg_dir)
"""

# Backwards-compat fallback for older backend_maturin releases registered before
# `package_repo_hook_subdir` existed on `backends.register`.
LEGACY_CARGO_HOOK_BACKENDS = ("maturin_build", "setuptools_rust_build")

def requirements_bzl(rctx, pins, packages, testonly_pins = {}):
    """Render `requirements.bzl` exporting `requirement()`, `all_requirements`, and `all_testonly_requirements`.

    Args:
        rctx: Repository context (uses `rctx.name`).
        pins: Normalized pin dict mapping pin name -> `{constraint: slot_key}`.
        packages: Slimmed member packages dict.
        testonly_pins: Set/dict of pin names marked testonly.

    Returns:
        Generated `requirements.bzl` file content.
    """
    entries = {False: [], True: []}  # testonly -> requirement labels
    for pin in sorted(pins.keys()):
        pin_target_dict = pins[pin]
        pin_parts = parse_package_key(pin)

        # Route through :maybe when any variant of this pin is platform-specific
        # OR when the pin has no unconditional branch (variant-only / partial fork),
        # so inactive variants/forks become _empty_library instead of no_match_error.
        is_conditional = "" not in pin_target_dict
        if not is_conditional:
            for slot_key in pin_target_dict.values():
                if is_key_platform_specific(packages, slot_key):
                    is_conditional = True
                    break

        us_pin = underscore_name(pin_parts.name)
        if pin_parts.extra:
            if is_conditional:
                label = "@@{repo_name}//{pin}:[{extra}]_maybe".format(repo_name = rctx.name, pin = us_pin, extra = pin_parts.extra)
            else:
                label = "@@{repo_name}//{pin}:[{extra}]".format(repo_name = rctx.name, pin = us_pin, extra = pin_parts.extra)
        elif is_conditional:
            label = "@@{repo_name}//{pin}:{maybe}".format(repo_name = rctx.name, pin = us_pin, maybe = safe_name(us_pin, "maybe"))
        else:
            label = "@@{repo_name}//{pin}".format(repo_name = rctx.name, pin = us_pin)
        entries[pin in testonly_pins or pin_parts.name in testonly_pins].append(label)

    lines = [
        _requirement_func.format(repo_name = rctx.name),
        "",
        "# All pinned requirements, excluding testonly ones",
        "all_requirements = [",
    ]
    lines.extend(['    "{}",'.format(label) for label in entries[False]])
    lines.extend([
        "]",
        "",
        "# All testonly pinned requirements",
        "all_testonly_requirements = [",
    ])
    lines.extend(['    "{}",'.format(label) for label in entries[True]])
    lines.append("]")
    return "\n".join(lines) + "\n"

def emit_backend_files(rctx, backend_names, state_repo):
    """Generate `_backend/BUILD.bazel` and forwarding macro `.bzl` files.

    Args:
        rctx: Repository context.
        backend_names: List of registered backend rule names.
        state_repo: Apparent name of the workspace's `@<ws>__state` repo.
    """
    if not backend_names:
        return
    rctx.file(
        "_backend/BUILD.bazel",
        "exports_files(glob(['*.bzl']))\n",
    )
    for macro_name in sorted(backend_names):
        lines = [
            '"""Backend macro alias for this thin repo."""',
            "",
            'load("@{}//_backend:{}.bzl", _{} = "{}")'.format(state_repo, macro_name, macro_name, macro_name),
            "",
            "{} = _{}".format(macro_name, macro_name),
            "",
        ]
        rctx.file("_backend/{}.bzl".format(macro_name), "\n".join(lines))

def hook_subdir_build(
        grouped_pins,
        packages,
        workspace_name,
        state_repo = None,
        no_variant_fallbacks = None,
        subdir = "_cargo",
        resolution_marker_exprs = None):
    """Render `<subdir>/BUILD.bazel` aliases for packages with matching spoke hook subdirs, or None.

    Uses precomputed version-free `hook_subdirs` metadata from `slim_member_lock`
    and points directly at `@<ws>__pkg_<name>//<subdir>:pkg[_<slot>]`.

    Args:
        grouped_pins: Dict of base pin name -> `{"base_target", "extras"}`.
        packages: Slimmed member packages dict keyed by version-free slot key.
        workspace_name: Workspace name.
        state_repo: Optional apparent name of `@<ws>__state` (defaults to `state_repo_name(workspace_name)`).
        no_variant_fallbacks: Result of `variant_fallbacks`, or None.
        subdir: Subdirectory name under the repo (default `"_cargo"`).
        resolution_marker_exprs: Optional member `resolution_marker_exprs` dict.

    Returns:
        `struct(build, unselected_groups)` with generated `<subdir>/BUILD.bazel` content
        and any required `_unselected_all_*` groups, or None if no packages match.
    """
    state_repo = state_repo or state_repo_name(workspace_name)
    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    variant_constraints = no_variant_fallbacks.sets if no_variant_fallbacks else None
    has_targets = False
    unselected_groups = {}
    hook_label_fn = lambda skey: spoke_slot_label(workspace_name, skey, "hook", subdir = subdir)
    for base_pin_name in sorted(grouped_pins.keys()):
        us_name = underscore_name(base_pin_name)
        target_dict = effective_base_target_dict(
            grouped_pins[base_pin_name],
            resolution_marker_exprs = resolution_marker_exprs,
            variant_constraints = variant_constraints,
        )
        if not target_dict:
            continue

        matched_target_dict = {}
        for constraint, slot_key in target_dict.items():
            base_key = base_package_key(slot_key)
            if subdir not in packages.get(base_key, {}).get("hook_subdirs", []):
                continue
            matched_target_dict[constraint] = base_key
        if not matched_target_dict:
            continue

        sel = target_select(
            matched_target_dict,
            hook_label_fn,
            state_repo,
            no_variant_fallbacks = no_variant_fallbacks,
            all_target_dict = target_dict,
            fallback_target = NO_MATCH_ERROR_TARGET,
            resolution_marker_exprs = resolution_marker_exprs,
        )
        unselected_groups.update(sel.unselected_groups)
        lines.extend(alias(us_name, sel.expr, actual_is_expr = True))
        has_targets = True

    if not has_targets:
        return None
    return struct(build = "\n".join(lines), unselected_groups = unselected_groups)
