"""Proxy rules for forwarding Python package providers through optional platform transitions.

pycross_library_proxy: Forwards PyInfo and all pycross-specific providers from
    a primary target, optionally merging additional deps into the PyInfo graph.
    Replaces py_library wrappers in generated lock repos.

pycross_thin_library_proxy: Lean variant without `deps` or rules_python API
    attributes. Used for non-transitioned library targets in thin package repos.

pycross_file_proxy: Forwards DefaultInfo only. Used for raw file targets
    (wheels, sdists, dist_info) in thin package repos.

Both library and file proxy rules also have transitioning variants that analyze
the `actual` target under a platform or flag transition.
"""

load("@rules_python//python:py_info.bzl", "PyInfo")
load(":deferred_failure.bzl", "register_failure_action")
load(
    ":providers.bzl",
    "PycrossExtractedWheelInfo",
    "PycrossPackageInfo",
    "PycrossUnsupportedWheelInfo",
)
load(":py_providers.bzl", "PY_COMMON_ATTRS", "merge_py_providers")

def _register_unsupported_proxy_failure(ctx):
    pkg_id = str(ctx.label)
    out = ctx.actions.declare_file("_unsupported_%x.out" % (hash(ctx.label.name) & 0xffffffff))
    register_failure_action(
        ctx,
        outputs = [out],
        message = (
            "Target {} is not available for the selected target environment " +
            "(no matching platform marker, artifact, or variant branch)."
        ).format(pkg_id),
        mnemonic = "PycrossUnsupportedPackage",
        progress_message = "Rejecting unavailable target %s" % pkg_id,
    )
    return out, pkg_id

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
    actual = (ctx.attr.actual[0] if ctx.attr.actual else None) if type(ctx.attr.actual) == "list" else ctx.attr.actual
    deps = getattr(ctx.attr, "deps", [])

    if actual == None:
        if len(deps) == 1:
            return [
                DefaultInfo(runfiles = deps[0][DefaultInfo].default_runfiles),
                deps[0][PyInfo],
            ]
        merged = merge_py_providers(ctx, deps, uses_shared_libraries = False)
        return [
            DefaultInfo(runfiles = merged.runfiles),
            merged.py_info,
        ]

    # When actual is the generic no_match_error sentinel (empty `package`),
    # replace it with a failure action naming this proxy's package.
    if PycrossUnsupportedWheelInfo in actual and not actual[PycrossUnsupportedWheelInfo].package:
        out, pkg_id = _register_unsupported_proxy_failure(ctx)
        return [
            DefaultInfo(files = depset([out]), runfiles = ctx.runfiles(files = [out])),
            PyInfo(transitive_sources = depset()),
            PycrossUnsupportedWheelInfo(package = pkg_id),
        ]

    if deps:
        # Merge PyInfo from actual + deps using the standard pycross merge utility.
        merged = merge_py_providers(ctx, [actual] + deps)
        py_info = merged.py_info
        runfiles = merged.runfiles
    else:
        # Fast path for thin-repo and deps-free proxies: forward providers directly
        # without instantiating PyInfoBuilder or wrapping depsets.
        py_info = actual[PyInfo]
        runfiles = actual[DefaultInfo].default_runfiles

    providers = [
        DefaultInfo(
            files = actual[DefaultInfo].files,
            runfiles = runfiles,
        ),
        py_info,
    ]

    # Forward pycross-specific providers from the actual target.
    if PycrossExtractedWheelInfo in actual:
        providers.append(actual[PycrossExtractedWheelInfo])
    if PycrossPackageInfo in actual:
        providers.append(actual[PycrossPackageInfo])
    if PycrossUnsupportedWheelInfo in actual:
        providers.append(actual[PycrossUnsupportedWheelInfo])

    # Forward OutputGroupInfo (e.g., dist_info) if present.
    if OutputGroupInfo in actual:
        providers.append(actual[OutputGroupInfo])

    return providers

def make_library_proxy_rule(cfg = None, platform_mandatory = False, supports_deps = True, doc = None):
    """Create a library proxy rule forwarding PyInfo and pycross providers with an optional transition.

    Args:
        cfg: Optional transition to attach to the `actual` attribute.
        platform_mandatory: Whether the `platform` attribute is mandatory when `cfg` is set.
        supports_deps: Whether to expose `deps` and `PY_COMMON_ATTRS` for PyInfo merging.
            When False, `actual` is mandatory and providers are forwarded directly.
        doc: Optional rule documentation string.

    Returns:
        A `rule` value.
    """
    if cfg != None:
        actual_doc = "The primary target to forward providers from (analyzed under the transition)."
    elif supports_deps:
        actual_doc = "The primary target to forward providers from. When omitted, only merges `deps`."
    else:
        actual_doc = "The primary target to forward providers from."
    actual_kwargs = {
        "providers": [PyInfo],
        "doc": actual_doc,
    }
    if cfg != None or not supports_deps:
        actual_kwargs["mandatory"] = True
    if cfg != None:
        actual_kwargs["cfg"] = cfg
    attrs = {
        "actual": attr.label(**actual_kwargs),
    }
    if supports_deps:
        attrs["deps"] = attr.label_list(
            default = [],
            providers = [PyInfo],
            doc = "Additional dependencies to merge into the PyInfo provider.",
        )
        attrs.update(PY_COMMON_ATTRS)
    if cfg != None:
        attrs["platform"] = attr.label(
            mandatory = platform_mandatory,
            doc = "The target platform to transition to.",
        )
        attrs["_allowlist_function_transition"] = attr.label(
            default = Label("@bazel_tools//tools/allowlists/function_transition_allowlist"),
        )
    default_doc = (
        "Forwards PyInfo and pycross-specific providers from a target, optionally merging additional deps." if supports_deps else "Forwards PyInfo and pycross-specific providers from a target."
    )
    return rule(
        implementation = _pycross_library_proxy_impl,
        doc = doc or default_doc,
        attrs = attrs,
        provides = [DefaultInfo, PyInfo],
    )

# Non-transitioning variant with deps merging (used in lock repos).
pycross_library_proxy = make_library_proxy_rule(
    doc = """Forwards PyInfo and pycross-specific providers from a target, optionally merging additional deps.

Replaces py_library wrappers in generated lock repos, preserving PycrossExtractedWheelInfo,
PycrossPackageInfo, and OutputGroupInfo that py_library would drop.""",
)

# Lean non-transitioning variant without deps or rules_python API attrs (used in thin repos).
pycross_thin_library_proxy = make_library_proxy_rule(
    supports_deps = False,
    doc = """Lean variant of pycross_library_proxy without `deps` or rules_python API attributes.

Used for non-transitioned library targets in thin package repos, forwarding PyInfo
and pycross-specific providers directly from `actual`.""",
)

# Transitioning variant (used in thin repos with platform override).
pycross_transitioning_library_proxy = make_library_proxy_rule(
    cfg = _platform_transition,
    platform_mandatory = True,
    supports_deps = False,
    doc = """Like pycross_thin_library_proxy, but applies a platform transition to the actual target.

Used in thin package repos when a repo() tag specifies `platform` or `constraint_values`.""",
)

# ---- pycross_file_proxy ------------------------------------------------------

def _pycross_file_proxy_impl(ctx):
    actual = ctx.attr.actual[0] if type(ctx.attr.actual) == "list" else ctx.attr.actual

    if PycrossUnsupportedWheelInfo in actual and not actual[PycrossUnsupportedWheelInfo].package:
        out, pkg_id = _register_unsupported_proxy_failure(ctx)
        return [
            DefaultInfo(files = depset([out]), runfiles = ctx.runfiles(files = [out])),
            PycrossUnsupportedWheelInfo(package = pkg_id),
        ]

    # Return a new DefaultInfo to avoid carrying over executable status if not intended.
    providers = [DefaultInfo(
        files = actual[DefaultInfo].files,
        runfiles = actual[DefaultInfo].default_runfiles,
    )]
    if PycrossUnsupportedWheelInfo in actual:
        providers.append(actual[PycrossUnsupportedWheelInfo])
    return providers

def make_file_proxy_rule(cfg = None, platform_mandatory = False, doc = None):
    """Create a file proxy rule forwarding DefaultInfo with an optional transition.

    Args:
        cfg: Optional transition to attach to the `actual` attribute.
        platform_mandatory: Whether the `platform` attribute is mandatory when `cfg` is set.
        doc: Optional rule documentation string.

    Returns:
        A `rule` value.
    """
    actual_kwargs = {
        "mandatory": True,
        "allow_single_file": True,
        "doc": (
            "The target to forward DefaultInfo from." if cfg == None else "The target to forward DefaultInfo from (analyzed under the transition)."
        ),
    }
    if cfg != None:
        actual_kwargs["cfg"] = cfg
    attrs = {
        "actual": attr.label(**actual_kwargs),
    }
    if cfg != None:
        attrs["platform"] = attr.label(
            mandatory = platform_mandatory,
            doc = "The target platform to transition to.",
        )
        attrs["_allowlist_function_transition"] = attr.label(
            default = Label("@bazel_tools//tools/allowlists/function_transition_allowlist"),
        )
    return rule(
        implementation = _pycross_file_proxy_impl,
        doc = doc or "Forwards DefaultInfo from a target. Used for raw file targets (wheels, sdists, dist_info).",
        attrs = attrs,
        provides = [DefaultInfo],
    )

# Non-transitioning variant.
pycross_file_proxy = make_file_proxy_rule()

# Transitioning variant.
pycross_transitioning_file_proxy = make_file_proxy_rule(
    cfg = _platform_transition,
    platform_mandatory = True,
    doc = """Like pycross_file_proxy, but applies a platform transition to the actual target.""",
)
