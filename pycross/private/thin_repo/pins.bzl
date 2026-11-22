"""Per-pin BUILD.bazel, `__actual/`, and root alias generation for thin package repos."""

load("//pycross/private:util.bzl", "is_platform_specific", "underscore_name")
load(":availability.bzl", "emit_maybe_alias")
load(":common.bzl", "NO_MATCH_ERROR_TARGET", "effective_base_target_dict", "is_key_platform_specific", "safe_name")
load(":selects.bzl", "proxy_actual")

def pin_build(target_name, pin_target_dict, workspace_repo, has_aggregated_variant = False, extras_dict = None, no_variant_fallbacks = None, target_platform = None, transition_bzl = None, maybe_available_keys = None, extras_maybe_keys = None, testonly = False, sdist_target_dict = None, aggregated_keys = None, packages = None):
    """Generates the BUILD file for a pin directory, pointing to the workspace.

    Args:
        target_name: Underscore-normalized pin directory and default alias name.
        pin_target_dict: Constraint -> package key mapping for the base package.
        workspace_repo: Name of the workspace (backing) repo.
        has_aggregated_variant: Whether any variant of this pin has extras (`[_all_]`).
        extras_dict: Optional dict of extra name -> constraint mapping.
        no_variant_fallbacks: Result of variant_fallbacks, or None.
        target_platform: Optional platform label for transitioning proxies.
        transition_bzl: Optional repo-local transition `.bzl` label.
        maybe_available_keys: Package keys needing `:maybe` availability gating.
        extras_maybe_keys: Dict of extra name -> list of platform-specific keys.
        testonly: Whether library proxy targets are marked `testonly = True`.
        sdist_target_dict: Constraint -> package key mapping for branches with sdists.
        aggregated_keys: Set/dict of base keys that have extras, or None.
        packages: Lock packages dict, or None.

    Returns:
        `struct(build, actual_build)` with BUILD file contents for `<pkg>/` and `__actual/<pkg>/`.
    """
    lock_ref = "@{}//_lock:".format(workspace_repo)
    wheel_ref = "@{}//_wheel:".format(workspace_repo)
    sdist_ref = "@{}//_sdist:".format(workspace_repo)

    actual_lines = []
    actual_pkg_ref = "//__actual/{}".format(target_name)

    if transition_bzl:
        # Flags-based transition: use generated transitioning rules.
        proxy_load = 'load({}, "pycross_transitioning_file_proxy", "pycross_transitioning_library_proxy")'.format(json.encode(transition_bzl))
        lib_rule = "pycross_transitioning_library_proxy"
        file_rule = "pycross_transitioning_file_proxy"
    elif target_platform:
        # Platform-only transition: use built-in transitioning rules.
        proxy_load = 'load("@rules_pycross//pycross/private:proxy.bzl", "pycross_transitioning_file_proxy", "pycross_transitioning_library_proxy")'
        lib_rule = "pycross_transitioning_library_proxy"
        file_rule = "pycross_transitioning_file_proxy"
    else:
        # No transition.
        proxy_load = 'load("@rules_pycross//pycross/private:proxy.bzl", "pycross_file_proxy", "pycross_library_proxy")'
        lib_rule = "pycross_library_proxy"
        file_rule = "pycross_file_proxy"

    lines = []

    has_transition = bool(transition_bzl or target_platform)

    def _emit_proxy(rule_name, name, actual, is_testonly = False):
        lines.extend([
            rule_name + "(",
            "    name = {},".format(json.encode(name)),
            "    actual = {}".format(actual),
        ])
        if is_testonly:
            lines.append("    testonly = True,")
        if target_platform:
            lines.append("    platform = {},".format(json.encode(target_platform)))
        lines.extend([")", ""])

    actual_pkg = None
    if pin_target_dict:
        lines.extend([
            "alias(",
            "    name = {},".format(json.encode(target_name)),
            "    actual = {},".format(json.encode(":" + safe_name(target_name, "pkg"))),
            ")",
            "",
        ])
        actual_pkg = proxy_actual(actual_lines, pin_target_dict, lock_ref, workspace_repo, "pkg", actual_pkg_ref, has_transition = has_transition, is_aggregated = has_aggregated_variant, no_variant_fallbacks = no_variant_fallbacks, aggregated_keys = aggregated_keys)
        _emit_proxy(lib_rule, safe_name(target_name, "pkg"), actual_pkg, is_testonly = testonly)

        actual_wheel = proxy_actual(actual_lines, pin_target_dict, wheel_ref, workspace_repo, "wheel", actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
        _emit_proxy(file_rule, safe_name(target_name, "wheel"), actual_wheel)

        actual_dist_info = proxy_actual(actual_lines, pin_target_dict, lock_ref + "_dist_info_", workspace_repo, "dist_info", actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
        _emit_proxy(file_rule, safe_name(target_name, "dist_info"), actual_dist_info)
        lines.extend([
            "alias(",
            "    name = {},".format(json.encode(safe_name(target_name, "data"))),
            "    actual = {},".format(json.encode(":" + safe_name(target_name, "pkg"))),
            ")",
        ])

        if extras_dict or has_aggregated_variant:
            if not has_aggregated_variant:
                lines.extend([
                    "alias(",
                    '    name = "[]",',
                    "    actual = {},".format(json.encode(":" + safe_name(target_name, "pkg"))),
                    ")",
                    "",
                ])
            else:
                actual_all = proxy_actual(actual_lines, pin_target_dict, lock_ref, workspace_repo, "all", actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
                _emit_proxy(lib_rule, "[]", actual_all, is_testonly = testonly)

        if sdist_target_dict:
            actual_sdist = proxy_actual(
                actual_lines,
                sdist_target_dict,
                sdist_ref,
                workspace_repo,
                "sdist",
                actual_pkg_ref,
                has_transition = has_transition,
                no_variant_fallbacks = no_variant_fallbacks,
                all_target_dict = pin_target_dict,
                fallback_target = NO_MATCH_ERROR_TARGET,
            )
            _emit_proxy(file_rule, safe_name(target_name, "sdist"), actual_sdist)

    extras_dict = extras_dict or {}
    extras_maybe_keys = extras_maybe_keys or {}
    for extra_name, extra_target_dict in sorted(extras_dict.items()):
        actual_extra = proxy_actual(actual_lines, extra_target_dict, lock_ref, workspace_repo, "extra_{}".format(extra_name), actual_pkg_ref, has_transition = has_transition, no_variant_fallbacks = no_variant_fallbacks)
        _emit_proxy(lib_rule, "[{}]".format(extra_name), actual_extra, is_testonly = testonly)
        extra_maybe = extras_maybe_keys.get(extra_name)
        if extra_target_dict and (extra_maybe or "" not in extra_target_dict):
            if has_transition:
                actual_extra_maybe = "extra_{}_maybe".format(extra_name)
                emit_maybe_alias(
                    actual_lines,
                    actual_extra_maybe,
                    actual_extra.rstrip(",").strip('"'),
                    extra_target_dict,
                    extra_maybe,
                    workspace_repo,
                    no_variant_fallbacks = no_variant_fallbacks,
                    helper_prefix = "_maybe_extra_{}".format(extra_name),
                    packages = packages,
                )
                _emit_proxy(lib_rule, "[{}]_maybe".format(extra_name), "{},".format(json.encode("{}:{}".format(actual_pkg_ref, actual_extra_maybe))), is_testonly = testonly)
            else:
                emit_maybe_alias(
                    lines,
                    "[{}]_maybe".format(extra_name),
                    ":[{}]".format(extra_name),
                    extra_target_dict,
                    extra_maybe,
                    workspace_repo,
                    no_variant_fallbacks = no_variant_fallbacks,
                    helper_prefix = "_maybe_extra_{}".format(extra_name),
                    packages = packages,
                )

    if pin_target_dict and (maybe_available_keys or "" not in pin_target_dict):
        maybe_name = safe_name(target_name, "maybe")
        pkg_name = safe_name(target_name, "pkg")
        if has_transition:
            emit_maybe_alias(
                actual_lines,
                "maybe",
                actual_pkg.rstrip(",").strip('"'),
                pin_target_dict,
                maybe_available_keys,
                workspace_repo,
                no_variant_fallbacks = no_variant_fallbacks,
                helper_prefix = "_maybe",
                packages = packages,
            )
            _emit_proxy(lib_rule, maybe_name, "{},".format(json.encode("{}:maybe".format(actual_pkg_ref))), is_testonly = testonly)
        else:
            emit_maybe_alias(
                lines,
                maybe_name,
                ":{}".format(pkg_name),
                pin_target_dict,
                maybe_available_keys,
                workspace_repo,
                no_variant_fallbacks = no_variant_fallbacks,
                helper_prefix = "_maybe",
                packages = packages,
            )

    header_lines = [proxy_load]
    if any(["selects.config_setting_group(" in line for line in lines]):
        header_lines.append('load("@bazel_skylib//lib:selects.bzl", "selects")')
    header_lines.extend([
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
    ])

    actual_build = None
    if actual_lines:
        actual_header = []
        if any(["selects.config_setting_group(" in line for line in actual_lines]):
            actual_header.extend(['load("@bazel_skylib//lib:selects.bzl", "selects")', ""])
        actual_header.extend([
            'package(default_visibility = ["//{}:__pkg__"])'.format(target_name),
            "",
        ])
        actual_build = "\n".join(actual_header + actual_lines) + "\n"

    return struct(
        build = "\n".join(header_lines + lines) + "\n",
        actual_build = actual_build,
    )

def append_root_aliases(root_build_lines, grouped_pins, base_packages_with_extras):
    """Append top-level `//:pkg`, `//:pkg[]`, and `//:pkg[extra]` aliases to root BUILD lines.

    Args:
        root_build_lines: Output list of root `BUILD.bazel` lines.
        grouped_pins: Dict of base pin name -> `{"base_target", "extras"}`.
        base_packages_with_extras: Set/dict of base package keys that have extras.
    """
    for base_pin_name in sorted(grouped_pins.keys()):
        group = grouped_pins[base_pin_name]
        us_name = underscore_name(base_pin_name)
        base_target = group["base_target"]

        if base_target:
            root_build_lines.extend([
                "alias(",
                "    name = {},".format(json.encode(base_pin_name)),
                "    actual = {},".format(json.encode("//{}:pkg".format(us_name))),
                ")",
            ])
            has_aggregated_variant = any([
                t in base_packages_with_extras
                for t in base_target.values()
            ])
            if group["extras"] or has_aggregated_variant:
                root_build_lines.extend([
                    "alias(",
                    "    name = {},".format(json.encode("{}[]".format(base_pin_name))),
                    "    actual = {},".format(json.encode("//{}:[]".format(us_name))),
                    ")",
                    "",
                ])
        elif group["extras"]:
            # If no base target was pinned, but extras were, point the base name at the extras union.
            root_build_lines.extend([
                "alias(",
                "    name = {},".format(json.encode(base_pin_name)),
                "    actual = {},".format(json.encode("//{}:pkg".format(us_name))),
                ")",
                "",
            ])

        for extra_name, _extra_target in sorted(group["extras"].items()):
            root_build_lines.extend([
                "alias(",
                "    name = {},".format(json.encode("{}[{}]".format(base_pin_name, extra_name))),
                "    actual = {},".format(json.encode("//{}:[{}]".format(us_name, extra_name))),
                ")",
                "",
            ])

def emit_pin_directories(rctx, grouped_pins, packages, base_packages_with_extras, workspace_repo, no_variant_fallbacks, target_platform, has_flags, testonly_pins_set):
    """Generate `<pkg>/BUILD.bazel` (and `__actual/<pkg>/BUILD.bazel`) for each pinned package.

    Args:
        rctx: Repository context.
        grouped_pins: Dict of base pin name -> `{"base_target", "extras"}`.
        packages: Lock packages dict.
        base_packages_with_extras: Set/dict of base package keys that have extras.
        workspace_repo: Name of the workspace (backing) repo.
        no_variant_fallbacks: Result of variant_fallbacks.
        target_platform: Optional platform label for transitioning proxies.
        has_flags: Whether `_transition.bzl` was generated for this repo.
        testonly_pins_set: Set/dict of pin names marked testonly.
    """
    for base_pin_name, group in sorted(grouped_pins.items()):
        base_target_dict = effective_base_target_dict(group)
        us_name = underscore_name(base_pin_name)

        has_aggregated_variant = bool(base_target_dict) and any([
            t in base_packages_with_extras
            for t in base_target_dict.values()
        ])

        extras_dict = group["extras"]

        # Determine which branches of this pin are platform-specific or have sdists.
        maybe_available_keys = []
        sdist_target_dict = {}
        if base_target_dict:
            for constraint, pkg_key in base_target_dict.items():
                pkg = packages.get(pkg_key, {})
                if is_platform_specific(pkg):
                    maybe_available_keys.append(pkg_key)
                if pkg.get("sdist_file"):
                    sdist_target_dict[constraint] = pkg_key

        extras_maybe_keys = {}
        for extra_name, extra_target_dict in extras_dict.items():
            extra_avail = []
            for _constraint, pkg_key in extra_target_dict.items():
                if is_key_platform_specific(packages, pkg_key):
                    extra_avail.append(pkg_key)
            if extra_avail:
                extras_maybe_keys[extra_name] = extra_avail

        result = pin_build(
            us_name,
            base_target_dict,
            workspace_repo,
            has_aggregated_variant = has_aggregated_variant,
            extras_dict = extras_dict,
            no_variant_fallbacks = no_variant_fallbacks,
            target_platform = target_platform,
            transition_bzl = "//:_transition.bzl" if has_flags else None,
            maybe_available_keys = maybe_available_keys,
            extras_maybe_keys = extras_maybe_keys,
            testonly = (base_pin_name in testonly_pins_set),
            sdist_target_dict = sdist_target_dict,
            aggregated_keys = base_packages_with_extras,
            packages = packages,
        )
        rctx.file("{}/BUILD.bazel".format(us_name), result.build)
        if result.actual_build:
            rctx.file("__actual/{}/BUILD.bazel".format(us_name), result.actual_build)
