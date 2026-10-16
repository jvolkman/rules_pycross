"""Variant resolver rule for conflict set mutual exclusion enforcement.

Each variant resolver reads a set of bool_flags that represent the items in
a single conflict set. It validates that at most one flag is set, and returns
a config_common.FeatureFlagInfo whose value is the qualified name of the
active variant. This lets config_setting targets reference the resolver
rather than individual bool_flags, providing:

  1. Build-time enforcement of mutual exclusion (fail if >1 flag is set).
  2. Clean default handling (return default variant when no flag is set).
  3. A single point of indirection per conflict set.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@pypackaging.bzl", "pypackaging")
load(":providers.bzl", "PycrossConflictStateInfo")

def conflict_token(kind_or_item, package = "", name = ""):
    """Return the uv-encoded conflict marker token for a conflict item.

    Args:
        kind_or_item: Either kind string ("extra", "group", "project") or an
            item dict with "kind", "package", and optional "name".
        package: Package name (when kind_or_item is a string).
        name: Extra or group name (when kind_or_item is "extra" or "group").

    Returns:
        The uv-encoded token string.
    """
    if type(kind_or_item) == "dict":
        kind = kind_or_item["kind"]
        package = kind_or_item["package"]
        name = kind_or_item.get("name", "")
    else:
        kind = kind_or_item
    pkg = pypackaging.utils.canonicalize_name(package)
    if kind == "extra":
        return "extra-{}-{}-{}".format(len(pkg), pkg, pypackaging.utils.canonicalize_name(name))
    if kind == "group":
        return "group-{}-{}-{}".format(len(pkg), pkg, pypackaging.utils.canonicalize_name(name))
    if kind == "project":
        return "project-{}-{}".format(len(pkg), pkg)
    fail("Unknown conflict item kind: {}".format(kind))

def _variant_resolver_impl(ctx):
    active = []
    for i, flag in enumerate(ctx.attr.flags):
        if flag[BuildSettingInfo].value:
            active.append(ctx.attr.names[i])

    if len(active) > 1:
        fail(
            "Conflicting variants are active simultaneously: {}. ".format(
                " and ".join(["--" + name for name in active]),
            ) + "Only one variant from each conflict set may be enabled at a time.",
        )

    if active:
        value = active[0]
    elif ctx.attr.default:
        value = ctx.attr.default
    else:
        fail(
            "No variant selected and no default configured for conflict set. " +
            "Set one of: " + ", ".join(ctx.attr.names),
        )

    return [config_common.FeatureFlagInfo(value = value)]

variant_resolver = rule(
    implementation = _variant_resolver_impl,
    provides = [config_common.FeatureFlagInfo],
    attrs = {
        "flags": attr.label_list(
            providers = [BuildSettingInfo],
            doc = "The bool_flag targets for each item in the conflict set.",
        ),
        "names": attr.string_list(
            doc = "The qualified name for each flag, in the same order as flags.",
        ),
        "default": attr.string(
            default = "",
            doc = "The default variant qualified name when no flag is set.",
        ),
    },
)

def _conflict_state_impl(ctx):
    active_qnames = {}
    for i, flag in enumerate(ctx.attr.flags):
        if flag[BuildSettingInfo].value:
            active_qnames[ctx.attr.names[i]] = True

    parsed_sets = [json.decode(s) for s in ctx.attr.conflict_sets]

    # Pass 1: validate explicit flag mutual exclusion per conflict set, and
    # collect defaults for sets with 0 active flags.
    defaults_to_activate = {}
    for cset in parsed_sets:
        qnames = cset["qnames"]
        default = cset.get("default", "")
        active_in_set = [q for q in qnames if q in active_qnames]
        if len(active_in_set) > 1:
            fail(
                "Conflicting variants in conflict set [{}] are active simultaneously: {}. ".format(
                    ", ".join(qnames),
                    " and ".join(["--" + name for name in active_in_set]),
                ) + "Only one variant from each conflict set may be enabled at a time.",
            )
        if not active_in_set and default:
            defaults_to_activate[default] = True

    for default_qname in defaults_to_activate.keys():
        active_qnames[default_qname] = True

    # Pass 2: re-validate every conflict set after defaults are applied (in case
    # a qname participates in two sets whose defaults conflict).
    for cset in parsed_sets:
        qnames = cset["qnames"]
        active_in_set = [q for q in qnames if q in active_qnames]
        if len(active_in_set) > 1:
            fail(
                "Conflicting variants in conflict set [{}] are active simultaneously: {}. ".format(
                    ", ".join(qnames),
                    " and ".join(["--" + name for name in active_in_set]),
                ) + "Only one variant from each conflict set may be enabled at a time.",
            )

    active_tokens = {}
    for qname in active_qnames.keys():
        for token in ctx.attr.qname_tokens.get(qname, []):
            active_tokens[token] = True

    return [PycrossConflictStateInfo(active_tokens = active_tokens)]

conflict_state = rule(
    implementation = _conflict_state_impl,
    provides = [PycrossConflictStateInfo],
    attrs = {
        "flags": attr.label_list(
            providers = [BuildSettingInfo],
            doc = "All conflict bool_flag targets in the workspace.",
        ),
        "names": attr.string_list(
            doc = "The qualified name for each flag, in the same order as flags.",
        ),
        "conflict_sets": attr.string_list(
            doc = "JSON-encoded conflict set dicts with 'qnames' and 'default'.",
        ),
        "qname_tokens": attr.string_list_dict(
            doc = "Mapping from qualified variant name to its uv conflict tokens.",
        ),
    },
)
