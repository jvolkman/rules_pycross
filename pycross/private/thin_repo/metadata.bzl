"""Metadata, requirements, backend forwarding, and hook-subdir files for thin package repos."""

load("//pycross/private:build_text.bzl", "alias")
load("//pycross/private:override_helpers.bzl", "merge_backend_overrides")
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
        pins: Normalized pin dict mapping pin name -> `{constraint: pkg_key}`.
        packages: Lock packages dict.
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
            for pkg_key in pin_target_dict.values():
                if is_key_platform_specific(packages, pkg_key):
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

def emit_backend_files(rctx, backend_names, workspace_repo):
    """Generate `_backend/BUILD.bazel` and forwarding macro `.bzl` files.

    Args:
        rctx: Repository context.
        backend_names: List of registered backend rule names.
        workspace_repo: Name of the workspace (backing) repo.
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
            'load("@{}//_backend:{}.bzl", _{} = "{}")'.format(workspace_repo, macro_name, macro_name, macro_name),
            "",
            "{} = _{}".format(macro_name, macro_name),
            "",
        ]
        rctx.file("_backend/{}.bzl".format(macro_name), "\n".join(lines))

def hook_subdir_build(grouped_pins, packages, override_configs, workspace_repo, no_variant_fallbacks = None, hook_backends = None, subdir = "_cargo"):
    """Render `<subdir>/BUILD.bazel` aliases for packages with hook-backed overrides, or None.

    Args:
        grouped_pins: Dict of base pin name -> `{"base_target", "extras"}`.
        packages: Lock packages dict.
        override_configs: Decoded backend override configs dict.
        workspace_repo: Name of the workspace (backing) repo.
        no_variant_fallbacks: Result of `variant_fallbacks`, or None.
        hook_backends: List of backend names that contribute to `subdir`, or None for legacy cargo fallback.
        subdir: Subdirectory name under the repo (default `"_cargo"`).

    Returns:
        `struct(build, unselected_groups)` with generated `<subdir>/BUILD.bazel` content
        and any required `_unselected_all_*` groups, or None if no packages match.
    """
    effective_backends = LEGACY_CARGO_HOOK_BACKENDS if hook_backends == None else hook_backends
    if not effective_backends:
        return None

    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    has_targets = False
    unselected_groups = {}
    for base_pin_name in sorted(grouped_pins.keys()):
        us_name = underscore_name(base_pin_name)
        target_dict = effective_base_target_dict(grouped_pins[base_pin_name])
        if not target_dict:
            continue

        matched_target_dict = {}
        for constraint, pkg_key in target_dict.items():
            parts = parse_package_key(pkg_key)
            base_key = base_package_key(pkg_key)
            if not packages.get(base_key, {}).get("sdist_file"):
                continue
            merged = merge_backend_overrides(override_configs, parts.name, parts.version)
            if not any([b in merged for b in effective_backends]):
                continue
            matched_target_dict[constraint] = base_key
        if not matched_target_dict:
            continue

        sel = target_select(
            matched_target_dict,
            "@{}//{}:".format(workspace_repo, subdir),
            workspace_repo,
            no_variant_fallbacks = no_variant_fallbacks,
            all_target_dict = target_dict,
            fallback_target = NO_MATCH_ERROR_TARGET,
        )
        unselected_groups.update(sel.unselected_groups)
        lines.extend(alias(us_name, sel.expr, actual_is_expr = True))
        has_targets = True

    if not has_targets:
        return None
    return struct(build = "\n".join(lines), unselected_groups = unselected_groups)
