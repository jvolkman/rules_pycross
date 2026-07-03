"""A thin package repo that delegates to a workspace for shared resources.

Each user-facing repo is "thin": it only contains pin aliases,
requirements.bzl, and modules_mapping.json. The actual
pycross_wheel_library targets live in the shared workspace repo.

The file structure is:
- BUILD.bazel              - Root aliases (//:package).
- requirements.bzl         - Provides requirement() and all_requirements.
- modules_mapping.json     - Import-to-package mapping for Gazelle.
- <package>/BUILD.bazel    - Pin proxies pointing to @workspace//_lock targets.
- _variants/BUILD.bazel    - Aliases for bool_flag and config_setting targets for variant selection.
"""

load(":util.bzl", "parse_package_key", "underscore_name")

_requirement_func = """\
load("@pypackaging.bzl", "pypackaging")

def requirement(pkg):
    extra = None
    if "[" in pkg:
        pkg, extra = pkg.split("[", 1)
        extra = extra.rstrip("]")

    pkg = pypackaging.utils.canonicalize_name(pkg)
    pkg_dir = pkg.replace("-", "_")

    if extra:
        return "@@{repo_name}//%s:[%s]" % (pkg_dir, extra)
    return "@@{repo_name}//%s" % (pkg_dir)
"""

def _is_platform_specific(pkg):
    """Check if a package is platform-specific (would be incompatible on some platforms)."""
    has_wheels = bool(pkg.get("wheel_candidates"))
    has_sdist = bool(pkg.get("sdist_file")) or bool(pkg.get("build_target"))
    return has_wheels and not has_sdist

def _requirements_bzl(rctx, pins, packages):
    lines = [
        _requirement_func.format(repo_name = rctx.name),
        "",
        "# All pinned requirements",
        "all_requirements = [",
    ]
    for pin in sorted(pins.keys()):
        pin_target_dict = pins[pin]

        # Check if ANY variant of this pin is platform-specific.
        is_conditional = False
        for pkg_key in pin_target_dict.values():
            pkg = packages.get(pkg_key, {})
            if _is_platform_specific(pkg):
                is_conditional = True
                break

        if is_conditional:
            us_pin = underscore_name(pin)
            lines.append('    "@@{repo_name}//{pin}:{maybe}",'.format(repo_name = rctx.name, pin = us_pin, maybe = _safe_name(us_pin, "maybe")))
        else:
            lines.append('    "@@{repo_name}//{pin}",'.format(repo_name = rctx.name, pin = underscore_name(pin)))
    lines.append("]")
    return "\n".join(lines) + "\n"

def _safe_name(pin_name, name):
    return name + "_" if pin_name == name else name

def _target_select(target_dict, prefix, suffix, workspace_repo, is_aggregated = False, default_variants = {}):
    if len(target_dict) == 1 and "" in target_dict:
        t = target_dict[""]
        if is_aggregated:
            parts = parse_package_key(t)
            t = "{}[_all_]@{}".format(parts.name, parts.version)
        return '"{}{}{}"'.format(prefix, t, suffix)

    lines = ["select({"]
    default_target = None
    for constraint, t in target_dict.items():
        t_base = t
        if is_aggregated:
            parts = parse_package_key(t)
            t_base = "{}[_all_]@{}".format(parts.name, parts.version)
        if constraint == "":
            lines.append('        "//conditions:default": "{}{}{}",'.format(prefix, t_base, suffix))
        else:
            lines.append('        "@{}//_lock:is_{}": "{}{}{}",'.format(workspace_repo, constraint, prefix, t_base, suffix))

            # If this constraint is a default variant, also map //conditions:default to it.
            if constraint in default_variants:
                default_target = t_base

    # Add //conditions:default for default variant (only if not already present via "").
    if default_target and "" not in target_dict:
        lines.append('        "//conditions:default": "{}{}{}",'.format(prefix, default_target, suffix))

    lines.append("    })")
    return "\n".join(lines)

def _proxy_actual(actual_lines, target_dict, prefix, suffix, workspace_repo, alias_name, actual_pkg_ref, transition_bzl, is_aggregated = False, default_variants = {}):
    """Emit an intermediate select alias if needed, return the actual expression for the proxy.

    When transition_bzl is set and target_dict has variants (would generate a select()),
    we emit an intermediate alias in the __actual/<pkg> package so the select() is
    evaluated in the transitioned configuration rather than before the transition applies.
    """
    actual = _target_select(target_dict, prefix, suffix, workspace_repo, is_aggregated = is_aggregated, default_variants = default_variants)
    if transition_bzl and not (len(target_dict) == 1 and "" in target_dict):
        actual_lines.extend([
            "alias(",
            '    name = "{}",'.format(alias_name),
            "    actual = {},".format(actual),
            ")",
            "",
        ])
        return '"{}:{}",'.format(actual_pkg_ref, alias_name)
    return "{},".format(actual)

def _pin_build(target_name, pin_target_dict, package, workspace_repo, workspace_lock_target_dict = None, has_aggregated_variant = False, extras_dict = None, default_variants = {}, target_platform = None, transition_bzl = None, maybe_available_key = None):
    """Generates the BUILD file for a pin directory, pointing to the workspace."""
    lock_target_dict = workspace_lock_target_dict if workspace_lock_target_dict else pin_target_dict
    lock_ref = "@{}//_lock:".format(workspace_repo)
    wheel_ref = "@{}//_wheel:".format(workspace_repo)
    sdist_ref = "@{}//_sdist:".format(workspace_repo)

    actual_lines = []
    actual_pkg_ref = "//__actual/{}".format(target_name)

    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    if transition_bzl:
        # Flags-based transition: use generated transitioning rules.
        lines.append('load("{}", "pycross_transitioning_file_proxy", "pycross_transitioning_library_proxy")'.format(transition_bzl))
        lib_rule = "pycross_transitioning_library_proxy"
        file_rule = "pycross_transitioning_file_proxy"
    elif target_platform:
        # Platform-only transition: use built-in transitioning rules.
        lines.append('load("@rules_pycross//pycross:defs.bzl", "pycross_transitioning_file_proxy", "pycross_transitioning_library_proxy")')
        lib_rule = "pycross_transitioning_library_proxy"
        file_rule = "pycross_transitioning_file_proxy"
    else:
        # No transition.
        lines.append('load("@rules_pycross//pycross:defs.bzl", "pycross_file_proxy", "pycross_library_proxy")')
        lib_rule = "pycross_library_proxy"
        file_rule = "pycross_file_proxy"
    lines.append("")

    # Emit the platform attr whenever using transitioning rules.
    emit_platform = bool(target_platform)

    if lock_target_dict:
        lines.extend([
            "alias(",
            '    name = "{}",'.format(target_name),
            '    actual = ":{}",'.format(_safe_name(target_name, "pkg")),
            ")",
            "",
        ])
        actual_pkg = _proxy_actual(actual_lines, lock_target_dict, lock_ref, "", workspace_repo, "pkg", actual_pkg_ref, transition_bzl, is_aggregated = has_aggregated_variant, default_variants = default_variants)
        lines.extend([
            lib_rule + "(",
            '    name = "{}",'.format(_safe_name(target_name, "pkg")),
            "    actual = {}".format(actual_pkg),
        ])
        if emit_platform:
            lines.append('    platform = "{}",'.format(target_platform))
        lines.extend([
            ")",
            "",
        ])
        actual_wheel = _proxy_actual(actual_lines, pin_target_dict, wheel_ref, "", workspace_repo, "wheel", actual_pkg_ref, transition_bzl, default_variants = default_variants)
        lines.extend([
            file_rule + "(",
            '    name = "{}",'.format(_safe_name(target_name, "wheel")),
            "    actual = {}".format(actual_wheel),
        ])
        if emit_platform:
            lines.append('    platform = "{}",'.format(target_platform))
        lines.extend([
            ")",
            "",
        ])
        actual_dist_info = _proxy_actual(actual_lines, lock_target_dict, lock_ref + "_dist_info_", "", workspace_repo, "dist_info", actual_pkg_ref, transition_bzl, default_variants = default_variants)
        lines.extend([
            file_rule + "(",
            '    name = "{}",'.format(_safe_name(target_name, "dist_info")),
            "    actual = {}".format(actual_dist_info),
        ])
        if emit_platform:
            lines.append('    platform = "{}",'.format(target_platform))
        lines.extend([
            ")",
            "",
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "data")),
            '    actual = ":{}",'.format(_safe_name(target_name, "pkg")),
            ")",
        ])

        if extras_dict:
            if not has_aggregated_variant:
                lines.extend([
                    "alias(",
                    '    name = "[]",',
                    '    actual = ":{}",'.format(_safe_name(target_name, "pkg")),
                    ")",
                    "",
                ])
            else:
                actual_all = _proxy_actual(actual_lines, lock_target_dict, lock_ref, "", workspace_repo, "all", actual_pkg_ref, transition_bzl, default_variants = default_variants)
                lines.extend([
                    lib_rule + "(",
                    '    name = "[]",',
                    "    actual = {}".format(actual_all),
                ])
                if emit_platform:
                    lines.append('    platform = "{}",'.format(target_platform))
                lines.extend([
                    ")",
                    "",
                ])

        sdist_file = package.get("sdist_file")
        if sdist_file:
            actual_sdist = _proxy_actual(actual_lines, pin_target_dict, sdist_ref, "", workspace_repo, "sdist", actual_pkg_ref, transition_bzl, default_variants = default_variants)
            lines.extend([
                file_rule + "(",
                '    name = "{}",'.format(_safe_name(target_name, "sdist")),
                "    actual = {}".format(actual_sdist),
            ])
            if emit_platform:
                lines.append('    platform = "{}",'.format(target_platform))
            lines.extend([
                ")",
                "",
            ])

    extras_dict = extras_dict or {}
    for extra_name, extra_target_dict in sorted(extras_dict.items()):
        actual_extra = _proxy_actual(actual_lines, extra_target_dict, lock_ref, "", workspace_repo, "extra_{}".format(extra_name), actual_pkg_ref, transition_bzl, default_variants = default_variants)
        lines.extend([
            lib_rule + "(",
            '    name = "[{}]",'.format(extra_name),
            "    actual = {}".format(actual_extra),
        ])
        if emit_platform:
            lines.append('    platform = "{}",'.format(target_platform))
        lines.extend([
            ")",
            "",
        ])

    if maybe_available_key:
        lines.extend([
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "maybe")),
            "    actual = select({",
            '        "@{}//_lock:_available_{}": ":{}",'.format(workspace_repo, maybe_available_key, _safe_name(target_name, "pkg")),
            '        "//conditions:default": "//:_empty_library",',
            "    }),",
            ")",
            "",
        ])

    actual_build = None
    if actual_lines:
        actual_header = [
            'package(default_visibility = ["//{}:__pkg__"])'.format(target_name),
            "",
        ]
        actual_build = "\n".join(actual_header + actual_lines) + "\n"

    return struct(
        build = "\n".join(lines) + "\n",
        actual_build = actual_build,
    )

def _thin_package_repo_impl(rctx):
    workspace_repo = rctx.attr.workspace_repo
    lock_json_path = rctx.path(rctx.attr.resolved_lock_file)
    lock = json.decode(rctx.read(lock_json_path))
    packages = lock["packages"]
    pins = lock["pins"]

    # Normalize pin values: bare strings (unconditional) become {"": value}
    for pin_name in pins.keys():
        if type(pins[pin_name]) == "string":
            pins[pin_name] = {"": pins[pin_name]}

    # Build a set of default variant item qualified names.
    # When a VariantItem has default=True, its target becomes //conditions:default
    # in the select(), so builds without explicit flags use the default variant.
    default_variants = {}  # qualified_name -> True
    for variant_set in lock.get("variants", []):
        for item in variant_set["items"]:
            if item.get("default", False):
                if item["kind"] == "project":
                    qname = "package_{}".format(item["package"])
                else:
                    qname = "{}_{}".format(item["kind"], item["name"])
                default_variants[qname] = True

    # Conflicts dict: pkg_key -> [member_names...] for packages with
    # differing annotations across workspace members.
    conflicts = rctx.attr.conflicts

    rctx.file("REPO.bazel", "")
    rctx.file("defs.bzl", "")
    rctx.file("requirements.bzl", _requirements_bzl(rctx, pins, packages))

    # Root BUILD.bazel with //:package aliases

    # Group pins by base package name to identify extras.
    grouped_pins = {}
    for pin_name, pin_target in pins.items():
        parts = parse_package_key(pin_name)
        if parts.extra:
            if parts.name not in grouped_pins:
                grouped_pins[parts.name] = {"base_target": None, "extras": {}}
            grouped_pins[parts.name]["extras"][parts.extra] = pin_target
        else:
            if parts.name not in grouped_pins:
                grouped_pins[parts.name] = {"base_target": None, "extras": {}}
            grouped_pins[parts.name]["base_target"] = pin_target

    root_build_lines = [
        'load("@rules_pycross//pycross/private:modules_mapping.bzl", "pycross_modules_mapping")',
        'load("@rules_python//python:defs.bzl", "py_library")',
        'package(default_visibility = ["//visibility:public"])',
        "",
        "# Empty library for _maybe_ targets on incompatible platforms.",
        'py_library(name = "_empty_library")',
        "",
    ]

    # Generate internal platform + transition if needed
    target_platform = rctx.attr.platform
    has_flags = bool(rctx.attr.flags)
    has_constraints = bool(rctx.attr.constraint_values)

    if not target_platform and (has_flags or has_constraints):
        target_platform = "//:_internal_platform"

        # Generate the platform target (for constraint_values / toolchain resolution).
        root_build_lines.extend([
            "platform(",
            '    name = "_internal_platform",',
        ])
        if has_constraints:
            root_build_lines.append("    constraint_values = [")
            for cv in rctx.attr.constraint_values:
                root_build_lines.append('        "{}",'.format(cv))
            root_build_lines.append("    ],")
        root_build_lines.extend([
            ")",
            "",
        ])

    if has_flags and target_platform:
        # Bazel's platform(flags=[...]) only applies during top-level platform
        # mapping, NOT when --platforms is set via a Starlark transition.
        # So we generate a _transition.bzl with custom proxy rules whose
        # transition sets both --platforms and the individual flag values.

        # Parse flags: extract label and value from "--label=value" strings.
        flag_settings = {}  # label -> value
        for f in rctx.attr.flags:
            stripped = f.lstrip("-")
            if "=" in stripped:
                label_part, value = stripped.split("=", 1)
            else:
                label_part, value = stripped, "True"
            flag_settings[label_part] = value

        # Build the transition outputs list and return dict
        outputs_lines = []
        return_lines = []
        for label, value in sorted(flag_settings.items()):
            outputs_lines.append('    "{}",'.format(label))

            # bool_flag expects actual booleans, not strings.
            if value in ("True", "true", "1"):
                py_value = "True"
            elif value in ("False", "false", "0"):
                py_value = "False"
            else:
                py_value = repr(value)
            return_lines.append('        "{}": {},'.format(label, py_value))

        transition_bzl = """\
\"\"\"Generated transition rules for {repo} with pinned flag values.\"\"\"

load("@rules_python//python:py_info.bzl", "PyInfo")
load("@rules_pycross//pycross/private:proxy.bzl",
    _file_proxy_impl = "pycross_file_proxy_impl",
    _library_proxy_impl = "pycross_library_proxy_impl",
)
load("@rules_pycross//pycross/private:util.bzl", "PY_COMMON_ATTRS")

def _transition_impl(settings, attr):
    return {{
        "//command_line_option:platforms": [str(attr.platform)],
{return_dict}
    }}

_repo_transition = transition(
    implementation = _transition_impl,
    inputs = ["//command_line_option:platforms"],
    outputs = [
        "//command_line_option:platforms",
{outputs}
    ],
)

pycross_transitioning_library_proxy = rule(
    implementation = _library_proxy_impl,
    attrs = dict({{
        "actual": attr.label(
            mandatory = True,
            providers = [PyInfo],
            cfg = _repo_transition,
        ),
        "deps": attr.label_list(
            default = [],
            providers = [PyInfo],
        ),
        "platform": attr.label(mandatory = True),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    }}, **PY_COMMON_ATTRS),
    provides = [DefaultInfo, PyInfo],
)

pycross_transitioning_file_proxy = rule(
    implementation = _file_proxy_impl,
    attrs = dict({{
        "actual": attr.label(
            mandatory = True,
            cfg = _repo_transition,
        ),
        "platform": attr.label(mandatory = True),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    }}),
    provides = [DefaultInfo],
)
""".format(
            repo = rctx.attr.member_name,
            return_dict = "\n".join(return_lines),
            outputs = "\n".join(outputs_lines),
        )
        rctx.file("_transition.bzl", transition_bzl)

    # Collect platform-specific packages for _maybe_ aliases.
    maybe_mapping_targets = {}  # maybe_name -> (pkg_key, lock_label)

    root_build_lines.extend([
        'exports_files(["defs.bzl", "requirements.bzl", "_packages.bzl"])',
        "",
        "pycross_modules_mapping(",
        '    name = "modules_mapping",',
        "    deps = [",
    ])
    for pin_name in sorted(pins.keys()):
        pin_target_dict = pins[pin_name]
        for pin_target in sorted(pin_target_dict.values()):
            package = packages.get(pin_target, {})

            # Determine the lock-level label for this package.
            if package.get("cycle_group"):
                lock_label = "@%s//_lock:_raw_%s" % (workspace_repo, pin_target)
            else:
                lock_label = "@%s//_lock:%s" % (workspace_repo, pin_target)

            if _is_platform_specific(package):
                maybe_name = pin_target.replace("@", "_").replace("[", "_").replace("]", "_")
                maybe_mapping_targets[maybe_name] = (pin_target, lock_label)
                root_build_lines.append('        "//__maybe:%s",' % maybe_name)
            else:
                root_build_lines.append('        "%s",' % lock_label)

    root_build_lines.extend([
        "    ],",
        ")",
        "",
    ])

    # Generate __maybe/ subdirectory with platform-specific conditional aliases.
    if maybe_mapping_targets:
        maybe_build_lines = [
            'load("@rules_python//python:defs.bzl", "py_library")',
            "",
            "package(default_visibility = [\"//visibility:public\"])",
            "",
            "# Empty library for incompatible platforms.",
            'py_library(name = "_empty_library")',
            "",
        ]
        for maybe_name, (pkg_key, lock_label) in sorted(maybe_mapping_targets.items()):
            maybe_build_lines.extend([
                "alias(",
                '    name = "%s",' % maybe_name,
                "    actual = select({",
                '        "@%s//_lock:_available_%s": "%s",' % (workspace_repo, pkg_key, lock_label),
                '        "//conditions:default": ":_empty_library",',
                "    }),",
                ")",
                "",
            ])
        rctx.file("__maybe/BUILD.bazel", "\n".join(maybe_build_lines))

    if rctx.attr.generate_root_aliases:
        for base_pin_name in sorted(grouped_pins.keys()):
            group = grouped_pins[base_pin_name]
            us_name = underscore_name(base_pin_name)
            base_target = group["base_target"]

            if base_target:
                root_build_lines.extend([
                    "alias(",
                    '    name = "{}",'.format(base_pin_name),
                    '    actual = "//{}:pkg",'.format(us_name),
                    ")",
                ])
                if group["extras"]:
                    root_build_lines.extend([
                        "alias(",
                        '    name = "{}[]",'.format(base_pin_name),
                        '    actual = "//{}:[]",'.format(us_name),
                        ")",
                        "",
                    ])
            elif group["extras"]:
                # If no base target was pinned, but extras were, point the base name at the extras union.
                root_build_lines.extend([
                    "alias(",
                    '    name = "{}",'.format(base_pin_name),
                    '    actual = "//{}:pkg",'.format(us_name),
                    ")",
                    "",
                ])

            for extra_name, extra_target in sorted(group["extras"].items()):
                root_build_lines.extend([
                    "alias(",
                    '    name = "{}[{}]",'.format(base_pin_name, extra_name),
                    '    actual = "//{}:[{}]",'.format(us_name, extra_name),
                    ")",
                    "",
                ])
    rctx.file("BUILD.bazel", "\n".join(root_build_lines))

    base_packages_with_extras = {}
    for pkg_key in packages.keys():
        parts = parse_package_key(pkg_key)
        if parts.extra:
            base_pkg_key = "{}@{}".format(parts.name, parts.version)
            base_packages_with_extras[base_pkg_key] = True

    # Pin directories: proxies pointing to @workspace//_lock targets
    for base_pin_name, group in sorted(grouped_pins.items()):
        base_target_dict = group["base_target"]
        if not base_target_dict and group["extras"]:
            # If the user only pinned extras, derive the base target from an extra's lock key.
            first_extra_target_dict = list(group["extras"].values())[0]
            base_target_dict = {}
            for constraint, extra_target in first_extra_target_dict.items():
                parts = parse_package_key(extra_target)
                if parts.extra:
                    base_target_dict[constraint] = "{}@{}".format(parts.name, parts.version)

        package = {}
        if base_target_dict:
            first_target = list(base_target_dict.values())[0]
            package = packages.get(first_target, {})
        us_name = underscore_name(base_pin_name)

        # For conflicting packages, use the member-specific variant target.
        workspace_lock_target_dict = None
        if base_target_dict:
            workspace_lock_target_dict = {}
            for constraint, base_target in base_target_dict.items():
                if base_target in conflicts:
                    workspace_lock_target_dict[constraint] = "{}__via_{}".format(base_target, rctx.attr.member_name)
                else:
                    workspace_lock_target_dict[constraint] = base_target

        has_aggregated_variant = False
        if base_target_dict:
            for constraint, base_target in base_target_dict.items():
                if base_target in base_packages_with_extras:
                    has_aggregated_variant = True

        # Handle extras variants
        extras_dict = {}
        for extra_name, extra_target_dict in group["extras"].items():
            new_target_dict = {}
            for constraint, extra_target in extra_target_dict.items():
                if extra_target in conflicts:
                    new_target_dict[constraint] = "{}__via_{}".format(extra_target, rctx.attr.member_name)
                else:
                    new_target_dict[constraint] = extra_target
            extras_dict[extra_name] = new_target_dict

        # Determine if this pin is platform-specific for the 'maybe' alias.
        maybe_available_key = None
        if base_target_dict:
            for pkg_key in base_target_dict.values():
                pkg = packages.get(pkg_key, {})
                if _is_platform_specific(pkg):
                    maybe_available_key = pkg_key
                    break

        result = _pin_build(us_name, base_target_dict, package, workspace_repo, workspace_lock_target_dict, has_aggregated_variant, extras_dict, default_variants = default_variants, target_platform = target_platform, transition_bzl = "//:_transition.bzl" if has_flags else None, maybe_available_key = maybe_available_key)
        rctx.file(
            "{}/BUILD.bazel".format(us_name),
            result.build,
        )
        if result.actual_build:
            rctx.file(
                "__actual/{}/BUILD.bazel".format(us_name),
                result.actual_build,
            )

    # _variants/ BUILD: alias bool_flag and config_setting targets
    # from the workspace repo so users can reference @<thin_repo>//_variants:<name>
    # in platform(flags=[...]) and transitions without needing the workspace repo directly.
    raw_variants = lock.get("variants", [])
    if raw_variants:
        # Collect unique variant items across all variant sets.
        variant_items = {}  # qualified_name -> True
        for variant_set in raw_variants:
            for item in variant_set["items"]:
                if item["kind"] == "project":
                    qname = "package_{}".format(item["package"])
                else:
                    qname = "{}_{}".format(item["kind"], item["name"])
                variant_items[qname] = True

        variant_lines = [
            'package(default_visibility = ["//visibility:public"])',
            "",
        ]
        for qname in sorted(variant_items.keys()):
            # Alias the bool_flag itself (for --@repo//_variants:extra_cpu)
            variant_lines.extend([
                "alias(",
                '    name = "{}",'.format(qname),
                '    actual = "@{}//_lock:{}",'.format(workspace_repo, qname),
                ")",
                "",
            ])

            # Alias the config_setting (for select() references)
            variant_lines.extend([
                "alias(",
                '    name = "is_{}",'.format(qname),
                '    actual = "@{}//_lock:is_{}",'.format(workspace_repo, qname),
                ")",
                "",
            ])
        rctx.file("_variants/BUILD.bazel", "\n".join(variant_lines))

    # _backend/ directory
    if rctx.attr.backend_configs:
        rctx.file(
            "_backend/BUILD.bazel",
            "exports_files(glob(['*.bzl']))\n",
        )

        for macro_name in rctx.attr.backend_configs.keys():
            lines = [
                '"""Backend macro alias for this thin repo."""',
                "",
                'load("@{}//_backend:{}.bzl", _{} = "{}")'.format(workspace_repo, macro_name, macro_name, macro_name),
                "",
                "{} = _{}".format(macro_name, macro_name),
                "",
            ]

            rctx.file("_backend/{}.bzl".format(macro_name), "\n".join(lines))

    # _packages.bzl: metadata about all packages in this thin repo.
    packages_lines = [
        '"""Generated package metadata. Do not edit."""',
        "",
        "PACKAGES = {",
    ]
    for base_pin_name in sorted(grouped_pins.keys()):
        group = grouped_pins[base_pin_name]
        us_name = underscore_name(base_pin_name)

        base_target_dict = group["base_target"]
        has_sdist = False
        if base_target_dict:
            first_target = list(base_target_dict.values())[0]
            pkg = packages.get(first_target, {})
            has_sdist = bool(pkg.get("sdist_file"))

        packages_lines.extend([
            '    "{}": struct('.format(us_name),
            "        has_sdist = {},".format(has_sdist),
            "    ),",
        ])
    packages_lines.extend([
        "}",
        "",
    ])
    rctx.file("_packages.bzl", "\n".join(packages_lines))

    # _cargo/ aliases: if any packages have cargo lock overrides, create
    # aliases from unversioned names to versioned targets in the package repo.
    if rctx.attr.override_configs:
        override_configs = json.decode(rctx.attr.override_configs)

        cargo_lines = [
            'package(default_visibility = ["//visibility:public"])',
            "",
        ]

        has_cargo_targets = False
        for base_pin_name in sorted(grouped_pins.keys()):
            us_name = underscore_name(base_pin_name)
            if base_pin_name not in override_configs:
                continue

            group = grouped_pins[base_pin_name]
            base_target_dict = group["base_target"]
            if not base_target_dict:
                continue

            # Get the versioned package key from the pin.
            first_target = list(base_target_dict.values())[0]
            parts = parse_package_key(first_target)
            versioned_name = "{}@{}".format(parts.name, parts.version)

            cargo_lines.extend([
                "alias(",
                '    name = "{}",'.format(us_name),
                '    actual = "@{}//_cargo:{}",'.format(workspace_repo, versioned_name),
                ")",
                "",
            ])
            has_cargo_targets = True

        if has_cargo_targets:
            rctx.file("_cargo/BUILD.bazel", "\n".join(cargo_lines))

thin_package_repo = repository_rule(
    implementation = _thin_package_repo_impl,
    attrs = {
        "resolved_lock_file": attr.label(mandatory = True),
        "generate_root_aliases": attr.bool(
            doc = "Whether to generate aliases like @uv//:numpy.",
            default = False,
        ),
        "workspace_repo": attr.string(
            mandatory = True,
            doc = "Name of the workspace package_repo that contains the shared _lock/ targets.",
        ),
        "default_build_repo": attr.string(
            doc = "Name of the workspace to pull sdist build dependencies from (e.g. build_deps__pkgs).",
        ),
        "member_name": attr.string(
            mandatory = True,
            doc = "User-facing repo name for this member (used in variant target naming).",
        ),
        "conflicts": attr.string_list_dict(
            default = {},
            doc = "Map of pkg_key -> [member_names...] for packages with conflicting annotations.",
        ),
        "backend_configs": attr.string_dict(
            doc = "Map of rule names to JSON-encoded config dicts.",
        ),
        "flags": attr.string_list(
            doc = "List of flags to apply to the generated platform.",
            default = [],
        ),
        "constraint_values": attr.string_list(
            doc = "List of constraint values to apply to the generated platform.",
            default = [],
        ),
        "platform": attr.string(
            doc = "Existing platform target to use directly.",
        ),
        "override_configs": attr.string(
            doc = "JSON-encoded dict of pkg_name -> {backend_name -> backend_attrs} for package repo hooks.",
        ),
    },
)

# Visible for testing
pin_build_for_testing = _pin_build
is_platform_specific_for_testing = _is_platform_specific
requirements_bzl_for_testing = _requirements_bzl
