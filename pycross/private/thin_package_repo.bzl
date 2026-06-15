"""A thin package repo that delegates to a hub for shared resources.

When multiple lock imports share a hub, each user-facing repo is "thin":
it only contains pin aliases, requirements.bzl, and modules_mapping.json.
The actual pycross_wheel_library targets live in the shared hub repo.

The file structure is:
- BUILD.bazel              - Root aliases (//:package).
- requirements.bzl         - Provides requirement() and all_requirements.
- modules_mapping.json     - Import-to-package mapping for Gazelle.
- <package>/BUILD.bazel    - Pin aliases pointing to @hub//_lock targets.
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

def _pin_build(target_name, original_pin_name, pin_target, package, hub_repo, hub_lock_target = None, has_squashed_variant = False, extras_dict = None):
    """Generates the BUILD file for a pin directory, pointing to the hub."""
    lock_target = hub_lock_target if hub_lock_target else pin_target
    lock_target_base = (lock_target + "__squashed") if has_squashed_variant else lock_target
    lock_ref = "@{}//_lock:".format(hub_repo)
    wheel_ref = "@{}//_wheel:".format(hub_repo)
    sdist_ref = "@{}//_sdist:".format(hub_repo)

    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    if lock_target:
        lines.extend([
            "alias(",
            '    name = "{}",'.format(target_name),
            '    actual = "{}{}",'.format(lock_ref, lock_target_base),
            ")",
            "",
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "pkg")),
            '    actual = "{}{}",'.format(lock_ref, lock_target_base),
            ")",
            "",
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "wheel")),
            '    actual = "{}{}",'.format(wheel_ref, original_pin_name),
            ")",
            "",
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "dist_info")),
            '    actual = "{}_dist_info_{}",'.format(lock_ref, lock_target),
            ")",
            "",
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "data")),
            '    actual = "{}{}",'.format(lock_ref, lock_target_base),
            ")",
            "",
        ])

        sdist_file = package.get("sdist_file")
        if sdist_file:
            lines.extend([
                "alias(",
                '    name = "{}",'.format(_safe_name(target_name, "sdist")),
                '    actual = "{}{}",'.format(sdist_ref, original_pin_name),
                ")",
                "",
            ])

    extras_dict = extras_dict or {}
    for extra_name, extra_target in sorted(extras_dict.items()):
        lines.extend([
            "alias(",
            '    name = "[{}]",'.format(extra_name),
            '    actual = "{}{}",'.format(lock_ref, lock_target_base if has_squashed_variant else extra_target),
            ")",
            "",
        ])

    return "\n".join(lines) + "\n"

def _thin_package_repo_impl(rctx):
    hub_repo = rctx.attr.hub_repo
    lock_json_path = rctx.path(rctx.attr.resolved_lock_file)
    lock = json.decode(rctx.read(lock_json_path))
    squash_extras = lock.get("squash_extras", False)
    packages = lock["packages"]
    pins = lock["pins"]

    # Conflicts dict: pkg_key -> [member_names...] for packages with
    # differing annotations across hub members.
    conflicts = rctx.attr.conflicts

    # modules_mapping.json is generated via pycross_modules_mapping in BUILD.bazel
    rctx.file("REPO.bazel", "")
    rctx.file("defs.bzl", "")
    rctx.file("requirements.bzl", _requirements_bzl(rctx, pins))

    # Root BUILD.bazel with //:package aliases
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
        pin_target = pins[pin_name]
        package = packages.get(pin_target, {})

        # Point directly at the pycross_wheel_library target in the hub's _lock.
        # For cycle group packages, the wheel_library is named _raw_<sanitized>.
        if package.get("cycle_group"):
            san = pin_target.lower().replace("-", "_").replace("@", "_").replace("+", "_").replace(".", "_")
            root_build_lines.append('        "@%s//_lock:_raw_%s",' % (hub_repo, san))
        else:
            root_build_lines.append('        "@%s//_lock:%s",' % (hub_repo, pin_target))
    root_build_lines.extend([
        "    ],",
        ")",
        "",
    ])
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

    # Pin directories: aliases pointing to @hub//_lock targets
    for base_pin_name, group in sorted(grouped_pins.items()):
        base_target = group["base_target"]
        package = packages.get(base_target) if base_target else {}
        us_name = underscore_name(base_pin_name)

        # For conflicting packages, use the member-specific variant target.
        hub_lock_target = None
        if base_target and base_target in conflicts:
            hub_lock_target = "{}__via_{}".format(base_target, rctx.attr.member_name)

        has_squashed_variant = squash_extras and base_target and base_target in base_packages_with_extras

        # Handle extras variants
        extras_dict = {}
        for extra_name, extra_target in group["extras"].items():
            if extra_target in conflicts:
                extras_dict[extra_name] = "{}__via_{}".format(extra_target, rctx.attr.member_name)
            else:
                extras_dict[extra_name] = extra_target

        rctx.file(
            "{}/BUILD.bazel".format(us_name),
            _pin_build(us_name, base_pin_name, base_target, package, hub_repo, hub_lock_target, has_squashed_variant, extras_dict),
        )

thin_package_repo = repository_rule(
    implementation = _thin_package_repo_impl,
    attrs = {
        "resolved_lock_file": attr.label(mandatory = True),
        "hub_repo": attr.string(
            mandatory = True,
            doc = "Name of the hub package_repo that contains the shared _lock/ targets.",
        ),
        "member_name": attr.string(
            mandatory = True,
            doc = "User-facing repo name for this member (used in variant target naming).",
        ),
        "conflicts": attr.string_list_dict(
            default = {},
            doc = "Map of pkg_key -> [member_names...] for packages with conflicting annotations.",
        ),
    },
)
