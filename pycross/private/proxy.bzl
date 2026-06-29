"""Proxy rules for forwarding Python package providers through optional platform transitions.

pycross_library_proxy: Forwards PyInfo and all pycross-specific providers from
    a primary target, optionally merging additional deps into the PyInfo graph.
    Replaces py_library wrappers in generated lock repos, and alias() for library
    targets in thin package repos.

pycross_file_proxy: Forwards DefaultInfo only. Used for raw file targets
    (wheels, sdists, dist_info) in thin package repos.

Both rules support an optional platform transition: if a `platform` label is
provided, the `actual` target is analyzed under that platform configuration.
"""

load("@rules_python//python:py_info.bzl", "PyInfo")
load(
    ":providers.bzl",
    "PycrossExtractedWheelInfo",
    "PycrossPackageInfo",
)
load(":util.bzl", "PY_COMMON_ATTRS", "merge_py_providers")

# ---- Platform transition -----------------------------------------------------

def _platform_transition_impl(settings, attr):
    if attr.platform:
        return {"//command_line_option:platforms": [str(attr.platform)]}
    return {"//command_line_option:platforms": settings["//command_line_option:platforms"]}

_platform_transition = transition(
    implementation = _platform_transition_impl,
    inputs = ["//command_line_option:platforms"],
    outputs = ["//command_line_option:platforms"],
)

# ---- pycross_library_proxy ---------------------------------------------------

def _pycross_library_proxy_impl(ctx):
    # The actual target is wrapped in a list due to the transition cfg.
    actual = ctx.attr.actual[0] if type(ctx.attr.actual) == "list" else ctx.attr.actual
    deps = ctx.attr.deps

    # Merge PyInfo from actual + deps using the standard pycross merge utility.
    all_deps = [actual] + deps
    merged = merge_py_providers(
        ctx,
        all_deps,
    )

    providers = [
        DefaultInfo(
            files = actual[DefaultInfo].files,
            runfiles = merged.runfiles,
        ),
        merged.py_info,
    ]

    # Forward pycross-specific providers from the actual target.
    if PycrossExtractedWheelInfo in actual:
        providers.append(actual[PycrossExtractedWheelInfo])
    if PycrossPackageInfo in actual:
        providers.append(actual[PycrossPackageInfo])

    # Forward OutputGroupInfo (e.g., dist_info) if present.
    if OutputGroupInfo in actual:
        providers.append(actual[OutputGroupInfo])

    return providers

# Non-transitioning variant (used in lock repos and thin repos without platform).
pycross_library_proxy = rule(
    implementation = _pycross_library_proxy_impl,
    doc = """Forwards PyInfo and pycross-specific providers from a target, optionally merging additional deps.

Replaces py_library wrappers in generated lock repos, preserving PycrossExtractedWheelInfo,
PycrossPackageInfo, and OutputGroupInfo that py_library would drop.""",
    attrs = dict({
        "actual": attr.label(
            mandatory = True,
            providers = [PyInfo],
            doc = "The primary target to forward providers from.",
        ),
        "deps": attr.label_list(
            default = [],
            providers = [PyInfo],
            doc = "Additional dependencies to merge into the PyInfo provider.",
        ),
        "platform": attr.label(
            default = None,
            doc = "Unused in the non-transitioning variant. Use pycross_transitioning_library_proxy for platform transitions.",
        ),
    }, **PY_COMMON_ATTRS),
    provides = [DefaultInfo, PyInfo],
)

# Transitioning variant (used in thin repos with platform override).
pycross_transitioning_library_proxy = rule(
    implementation = _pycross_library_proxy_impl,
    doc = """Like pycross_library_proxy, but applies a platform transition to the actual target.

Used in thin package repos when a uv_member specifies a target platform.""",
    attrs = dict({
        "actual": attr.label(
            mandatory = True,
            providers = [PyInfo],
            cfg = _platform_transition,
            doc = "The primary target to forward providers from (analyzed under the target platform).",
        ),
        "deps": attr.label_list(
            default = [],
            providers = [PyInfo],
            doc = "Additional dependencies to merge into the PyInfo provider.",
        ),
        "platform": attr.label(
            mandatory = True,
            doc = "The target platform to transition to.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    }, **PY_COMMON_ATTRS),
    provides = [DefaultInfo, PyInfo],
)

# ---- pycross_file_proxy ------------------------------------------------------

def _pycross_file_proxy_impl(ctx):
    actual = ctx.attr.actual[0] if type(ctx.attr.actual) == "list" else ctx.attr.actual
    return [actual[DefaultInfo]]

# Non-transitioning variant.
pycross_file_proxy = rule(
    implementation = _pycross_file_proxy_impl,
    doc = """Forwards DefaultInfo from a target. Used for raw file targets (wheels, sdists, dist_info).""",
    attrs = {
        "actual": attr.label(
            mandatory = True,
            doc = "The target to forward DefaultInfo from.",
        ),
        "platform": attr.label(
            default = None,
            doc = "Unused in the non-transitioning variant. Use pycross_transitioning_file_proxy for platform transitions.",
        ),
    },
)

# Transitioning variant.
pycross_transitioning_file_proxy = rule(
    implementation = _pycross_file_proxy_impl,
    doc = """Like pycross_file_proxy, but applies a platform transition to the actual target.""",
    attrs = {
        "actual": attr.label(
            mandatory = True,
            cfg = _platform_transition,
            doc = "The target to forward DefaultInfo from (analyzed under the target platform).",
        ),
        "platform": attr.label(
            mandatory = True,
            doc = "The target platform to transition to.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
