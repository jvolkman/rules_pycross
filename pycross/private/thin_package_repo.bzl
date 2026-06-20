"""A thin package repo that delegates to a workspace for shared resources.

Each user-facing repo is "thin": it only contains pin aliases,
requirements.bzl, and modules_mapping.json. The actual
pycross_wheel_library targets live in the shared workspace repo.

The file structure is:
- BUILD.bazel              - Root aliases (//:package).
- requirements.bzl         - Provides requirement() and all_requirements.
- modules_mapping.json     - Import-to-package mapping for Gazelle.
- <package>/BUILD.bazel    - Pin aliases pointing to @workspace//_lock targets.
- _variants/BUILD.bazel    - Aliases for bool_flag and config_setting targets for variant selection.
"""

load(":util.bzl", "underscore_name")

_requirement_func = """\
def requirement(pkg):
    extra = None
    if "[" in pkg:
        pkg, extra = pkg.split("[", 1)
        extra = extra.rstrip("]")

    pkg = pkg.replace("_", "-").replace(".", "-").lower()
    for i in range(len(pkg)):
        if "--" in pkg:
            pkg = pkg.replace("--", "-")
        else:
            break

    if extra:
        return "@@{repo_name}//:%s[%s]" % (pkg, extra)
    return "@@{repo_name}//:%s" % pkg
"""

def _requirements_bzl(rctx, pins):
    lines = [
        _requirement_func.format(repo_name = rctx.name),
        "",
        "# All pinned requirements",
        "all_requirements = [",
    ]
    for pin in sorted(pins.keys()):
        lines.append('    "@@{repo_name}//:{pin}",'.format(repo_name = rctx.name, pin = pin))
    lines.append("]")
    return "\n".join(lines) + "\n"

def _safe_name(pin_name, name):
    return name + "_" if pin_name == name else name

def _target_select(target_dict, prefix, suffix, workspace_repo, is_aggregated = False, default_variants = {}):
    if len(target_dict) == 1 and "" in target_dict:
        t = target_dict[""]
        if is_aggregated:
            t = "{}[_all_]@{}".format(t.split("@", 1)[0], t.split("@", 1)[1])
        return '"{}{}{}"'.format(prefix, t, suffix)

    lines = ["select({"]
    default_target = None
    for constraint, t in target_dict.items():
        t_base = t
        if is_aggregated:
            t_base = "{}[_all_]@{}".format(t.split("@", 1)[0], t.split("@", 1)[1])
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

def _pin_build(target_name, pin_target_dict, package, workspace_repo, workspace_lock_target_dict = None, has_aggregated_variant = False, extras_dict = None, default_variants = {}):
    """Generates the BUILD file for a pin directory, pointing to the workspace."""
    lock_target_dict = workspace_lock_target_dict if workspace_lock_target_dict else pin_target_dict
    lock_ref = "@{}//_lock:".format(workspace_repo)
    wheel_ref = "@{}//_wheel:".format(workspace_repo)
    sdist_ref = "@{}//_sdist:".format(workspace_repo)

    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    if lock_target_dict:
        lines.extend([
            "alias(",
            '    name = "{}",'.format(target_name),
            "    actual = {},".format(_target_select(lock_target_dict, lock_ref, "", workspace_repo, is_aggregated = has_aggregated_variant, default_variants = default_variants)),
            ")",
            "",
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "pkg")),
            "    actual = {},".format(_target_select(lock_target_dict, lock_ref, "", workspace_repo, is_aggregated = has_aggregated_variant, default_variants = default_variants)),
            ")",
            "",
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "wheel")),
            "    actual = {},".format(_target_select(pin_target_dict, wheel_ref, "", workspace_repo, default_variants = default_variants)),
            ")",
            "",
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "dist_info")),
            "    actual = {},".format(_target_select(lock_target_dict, lock_ref + "_dist_info_", "", workspace_repo, default_variants = default_variants)),
            ")",
            "",
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "data")),
            "    actual = {},".format(_target_select(lock_target_dict, lock_ref, "", workspace_repo, is_aggregated = has_aggregated_variant, default_variants = default_variants)),
            ")",
        ])

        if extras_dict:
            lines.extend([
                "alias(",
                '    name = "[]",',
                "    actual = {},".format(_target_select(lock_target_dict, lock_ref, "", workspace_repo, default_variants = default_variants)),
                ")",
                "",
            ])

        sdist_file = package.get("sdist_file")
        if sdist_file:
            lines.extend([
                "alias(",
                '    name = "{}",'.format(_safe_name(target_name, "sdist")),
                "    actual = {},".format(_target_select(pin_target_dict, sdist_ref, "", workspace_repo, default_variants = default_variants)),
                ")",
                "",
            ])

    extras_dict = extras_dict or {}
    for extra_name, extra_target_dict in sorted(extras_dict.items()):
        lines.extend([
            "alias(",
            '    name = "[{}]",'.format(extra_name),
            "    actual = {},".format(_target_select(extra_target_dict, lock_ref, "", workspace_repo, default_variants = default_variants)),
            ")",
            "",
        ])

    return "\n".join(lines) + "\n"

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
    rctx.file("requirements.bzl", _requirements_bzl(rctx, pins))

    # Root BUILD.bazel with //:package aliases

    # Group pins by base package name to identify extras.
    grouped_pins = {}
    for pin_name, pin_target in pins.items():
        if "[" in pin_name:
            base, extra = pin_name.split("[", 1)
            extra = extra[:-1]
            if base not in grouped_pins:
                grouped_pins[base] = {"base_target": None, "extras": {}}
            grouped_pins[base]["extras"][extra] = pin_target
        else:
            if pin_name not in grouped_pins:
                grouped_pins[pin_name] = {"base_target": None, "extras": {}}
            grouped_pins[pin_name]["base_target"] = pin_target

    root_build_lines = [
        'load("@rules_pycross//pycross/private:modules_mapping.bzl", "pycross_modules_mapping")',
        'package(default_visibility = ["//visibility:public"])',
        "",
        'exports_files(["defs.bzl", "requirements.bzl"])',
        "",
        "pycross_modules_mapping(",
        '    name = "modules_mapping",',
        "    deps = [",
    ]
    for pin_name in sorted(pins.keys()):
        pin_target_dict = pins[pin_name]
        for pin_target in sorted(pin_target_dict.values()):
            package = packages.get(pin_target, {})

            # Point directly at the pycross_wheel_library target in the workspace's _lock.
            # For cycle group packages, the wheel_library is named _raw_<pkg_key>.
            if package.get("cycle_group"):
                root_build_lines.append('        "@%s//_lock:_raw_%s",' % (workspace_repo, pin_target))
            else:
                root_build_lines.append('        "@%s//_lock:%s",' % (workspace_repo, pin_target))
    root_build_lines.extend([
        "    ],",
    ])

    # Tell Gazelle to map imports from packages
    # that are only pinned via a single extra to the extra-qualified name.
    # Note: If a package is pinned via multiple different extras but has no base
    # pin (e.g. `foo[a]` and `foo[b]`), we don't pick a winner for Gazelle mapping.
    extras_mapping = {}
    for base_name, group in grouped_pins.items():
        if not group["base_target"] and len(group["extras"]) == 1:
            extra_name = list(group["extras"].keys())[0]
            us_base = base_name.replace("-", "_")
            extras_mapping[us_base] = "{}[{}]".format(us_base, extra_name)
    if extras_mapping:
        root_build_lines.append("    extras_mapping = {")
        for base, qualified in sorted(extras_mapping.items()):
            root_build_lines.append('        "{}": "{}",'.format(base, qualified))
        root_build_lines.append("    },")

    root_build_lines.extend([
        ")",
        "",
    ])

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
        if "[" in pkg_key:
            base_name, extra_and_version = pkg_key.split("[", 1)
            extra_name, version = extra_and_version.split("]@", 1)
            base_pkg_key = "{}@{}".format(base_name, version)
            base_packages_with_extras[base_pkg_key] = True

    # Pin directories: aliases pointing to @workspace//_lock targets
    for base_pin_name, group in sorted(grouped_pins.items()):
        base_target_dict = group["base_target"]
        if not base_target_dict and group["extras"]:
            # If the user only pinned extras, derive the base target from an extra's lock key.
            first_extra_target_dict = list(group["extras"].values())[0]
            base_target_dict = {}
            for constraint, extra_target in first_extra_target_dict.items():
                if "[" in extra_target:
                    base_name, extra_and_version = extra_target.split("[", 1)
                    _, version = extra_and_version.split("]@", 1)
                    base_target_dict[constraint] = "{}@{}".format(base_name, version)

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

        rctx.file(
            "{}/BUILD.bazel".format(us_name),
            _pin_build(us_name, base_target_dict, package, workspace_repo, workspace_lock_target_dict, has_aggregated_variant, extras_dict, default_variants = default_variants),
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

thin_package_repo = repository_rule(
    implementation = _thin_package_repo_impl,
    attrs = {
        "resolved_lock_file": attr.label(mandatory = True),
        "workspace_repo": attr.string(
            mandatory = True,
            doc = "Name of the workspace package_repo that contains the shared _lock/ targets.",
        ),
        "workspace_build_repo": attr.string(
            doc = "Name of the workspace to pull sdist build dependencies from (e.g. pycross_ws_build_deps).",
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
    },
)
