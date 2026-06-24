"""Macro for per-member cycle dependency resolution with PEP 508 markers.

Generates N targets per cycle member (one per other member in the cycle),
where each dep is gated by a pycross_cycle_dep_needed reachability check
+ config_setting.  This ensures Bazel only downloads/analyzes cycle members
that are actually reachable on the current platform.

Usage in generated lock.bzl:
    pycross_cycle_member_marker_deps(
        name = "pkg@1.0",
        raw_name = "_raw_pkg@1.0",
        member = "pkg@1.0",
        members = ["pkg@1.0", "other@2.0", ...],
        edges = '{...}',  # JSON edge map
        sys_platform = select(SYS_PLATFORM_VALUES),
        ...
    )

This expands to:
    _pycross_cycle_dep_needed(name = "_cycle_needed_<member>_<other>", ...)
    native.config_setting(name = "_cycle_needed_<member>_<other>_match", ...)
    py_library(
        name = "pkg@1.0",
        deps = [":_raw_pkg@1.0"]
            + select({":_cycle_needed_..._match": [":_raw_other@2.0"]})
            + ...,
    )
"""

load("@rules_python//python:defs.bzl", "py_library")
load("//pycross/private:cycle_dep_needed.bzl", "pycross_cycle_dep_needed")

def _sanitize(name):
    """Sanitize a package key for use in target names."""
    return name.replace("@", "_").replace(".", "_").replace("-", "_").replace("[", "_").replace("]", "_")

def pycross_cycle_member_marker_deps(
        name,
        raw_name,
        member,
        members,
        edges,
        **kwargs):
    """Creates select()-gated cycle member deps using N² reachability checks.

    For each other member in the cycle, creates a pycross_cycle_dep_needed
    rule (returns FeatureFlagInfo true/false) and a config_setting, then
    wraps everything in a py_library with select() per dep.

    Args:
        name: The final target name (e.g. "pkg@1.0").
        raw_name: The raw package target name (e.g. "_raw_pkg@1.0").
        member: The package key of this cycle member.
        members: List of all package keys in the cycle group.
        edges: JSON-encoded edge map: {node: [{dep, marker_ast?}, ...]}.
        **kwargs: Marker value attrs (sys_platform, os_name, etc.) passed
                  through to pycross_cycle_dep_needed.
    """
    other_members = [m for m in sorted(members) if m != member]

    if not other_members:
        # Single-member cycle (shouldn't happen, but handle gracefully).
        native.alias(
            name = name,
            actual = ":" + raw_name,
        )
        return

    deps = [":" + raw_name]

    for target in other_members:
        pair_name = "_cycle_needed_{}_{}".format(
            _sanitize(member),
            _sanitize(target),
        )

        # Reachability evaluator: returns FeatureFlagInfo("true"/"false")
        pycross_cycle_dep_needed(
            name = pair_name,
            source = member,
            target = target,
            edges = edges,
            **kwargs
        )

        # Config setting matching reachable == "true"
        native.config_setting(
            name = pair_name + "_match",
            flag_values = {
                ":" + pair_name: "true",
            },
        )

        # Gate this dep behind the reachability check
        deps = deps + select({
            ":" + pair_name + "_match": [":_raw_" + target],
            "//conditions:default": [],
        })

    py_library(
        name = name,
        deps = deps,
    )
