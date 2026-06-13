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

def _underscore_name(name):
    return underscore_name(name)

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

def _pin_build(target_name, original_pin_name, pin_target, package, hub_repo, hub_lock_target = None, squash_extras = False):
    """Generates the BUILD file for a pin directory, pointing to the hub.

    Args:
        target_name: The underscore-normalized directory/target name.
        original_pin_name: The original pin name (e.g., "regex").
        pin_target: The package key in the hub's _lock/ (e.g., "regex@2026.5.9").
        package: The package data dict from the lock.
        hub_repo: The hub repo name.
        hub_lock_target: If set, use this as the _lock target instead of pin_target.
            Used for conflicting packages that have member-specific variants.
        squash_extras: If true, point base package aliases to the __squashed variant.
    """
    lock_target = hub_lock_target if hub_lock_target else pin_target
    lock_target_base = (lock_target + "__squashed") if squash_extras and package.get("extra_dependencies") else lock_target
    lock_ref = "@{}//_lock:".format(hub_repo)
    wheel_ref = "@{}//_wheel:".format(hub_repo)
    sdist_ref = "@{}//_sdist:".format(hub_repo)

    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
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
    ]

    sdist_file = package.get("sdist_file")
    if sdist_file:
        lines.extend([
            "alias(",
            '    name = "{}",'.format(_safe_name(target_name, "sdist")),
            '    actual = "{}{}",'.format(sdist_ref, original_pin_name),
            ")",
            "",
        ])

    for extra_name in sorted(package.get("extra_dependencies", {}).keys()):
        lines.extend([
            "alias(",
            '    name = "[{}]",'.format(extra_name),
            '    actual = "{}{}",'.format(lock_ref, lock_target_base if squash_extras else "{}[{}]".format(lock_target, extra_name)),
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
        root_build_lines.append('        "//%s:pkg",' % _underscore_name(pin_name))
    root_build_lines.extend([
        "    ],",
        ")",
        "",
    ])
    for pin_name in sorted(pins.keys()):
        us_name = _underscore_name(pin_name)
        package = packages[pins[pin_name]]

        root_build_lines.extend([
            "alias(",
            '    name = "{}",'.format(pin_name),
            '    actual = "//{}:pkg",'.format(us_name),
            ")",
            "",
        ])

        for extra_name in sorted(package.get("extra_dependencies", {}).keys()):
            root_build_lines.extend([
                "alias(",
                '    name = "{}[{}]",'.format(pin_name, extra_name),
                '    actual = "//{}:[{}]",'.format(us_name, extra_name),
                ")",
                "",
            ])
    rctx.file("BUILD.bazel", "\n".join(root_build_lines))

    # Pin directories: aliases pointing to @hub//_lock targets
    for pin_name, pin_target in sorted(pins.items()):
        package = packages[pin_target]
        us_name = _underscore_name(pin_name)

        # For conflicting packages, use the member-specific variant target.
        hub_lock_target = None
        if pin_target in conflicts:
            hub_lock_target = "{}__via_{}".format(pin_target, rctx.attr.member_name)

        rctx.file(
            "{}/BUILD.bazel".format(us_name),
            _pin_build(us_name, pin_name, pin_target, package, hub_repo, hub_lock_target, squash_extras),
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
