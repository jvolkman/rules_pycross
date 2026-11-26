"""Wheel chooser rule for selecting the best-matching wheel at analysis time.

Given a list of wheel filenames and a target platform providing compatible
PEP 425 tags (ordered by preference), this rule picks the best compatible
wheel and returns its filename through config_common.FeatureFlagInfo.

The selection algorithm:
  1. Build (or reuse from PycrossTargetPlatformInfo.tag_priority) a
     `{tag: rank}` priority map where lower rank is more preferred.
  2. Score each candidate wheel's parsed PEP 425 tags against the map.
  3. Return the best-ranked matching candidate's filename (first candidate
     wins ties), or "__no_matching_wheel__" if nothing matches.
"""

load("@pypackaging.bzl", "pypackaging")
load(":target_platform.bzl", "PycrossTargetPlatformInfo")

# ---------------------------------------------------------------------------
# Pure-function helpers
# ---------------------------------------------------------------------------

def _normalize_supported_ranks(supported_tags):
    if type(supported_tags) == "dict":
        return supported_tags
    expanded = []
    for tag in supported_tags:
        if type(tag) == "string" and "." in tag:
            expanded.extend(pypackaging.tags.parse_tag(tag))
        else:
            expanded.append(tag)
    return pypackaging.tags.priority_map(expanded)

def select_best_wheel(filenames, supported_tags):
    """Select the best-matching wheel from a list of filenames.

    Args:
        filenames: List of candidate wheel filenames.
        supported_tags: Either a precomputed `{tag: rank}` priority map from
            `pypackaging.tags.priority_map()` or a list of compatible tag
            strings, ordered by preference.

    Returns:
        The best matching filename, or None if no candidate is compatible.
    """
    if not filenames or not supported_tags:
        return None

    ranks = _normalize_supported_ranks(supported_tags)
    tagged = [
        (f, pypackaging.utils.parse_wheel_filename(f).tags)
        for f in filenames
    ]
    matches = pypackaging.tags.select_compatible(ranks, tagged)
    return matches[0] if matches else None

# ---------------------------------------------------------------------------
# Rule implementation
# ---------------------------------------------------------------------------

def _pycross_wheel_chooser_impl(ctx):
    candidates = ctx.attr.candidates
    platform_info = ctx.attr.supported_tags[PycrossTargetPlatformInfo]
    supported_tags = getattr(platform_info, "tag_priority", None)
    if supported_tags == None:
        supported_tags = platform_info.compatibility_tags

    best = select_best_wheel(candidates, supported_tags)

    if best:
        value = best
    else:
        value = "__no_matching_wheel__"

    return [config_common.FeatureFlagInfo(value = value)]

pycross_wheel_chooser = rule(
    implementation = _pycross_wheel_chooser_impl,
    doc = (
        "Select the best-matching wheel from a list of candidates. Takes a list of " +
        "candidate wheel filenames and a target platform providing ordered compatibility " +
        "tags, and produces a FeatureFlagInfo whose value is the best matching filename."
    ),
    provides = [config_common.FeatureFlagInfo],
    attrs = {
        "candidates": attr.string_list(
            mandatory = True,
            doc = "List of candidate wheel filenames.",
        ),
        "supported_tags": attr.label(
            default = Label("@rules_pycross//pycross/private:default_target_platform"),
            providers = [PycrossTargetPlatformInfo],
            doc = "The supported tags for the current environment.",
        ),
    },
)

def _pycross_wheel_matched_impl(ctx):
    matched = ctx.attr.chooser[config_common.FeatureFlagInfo].value != "__no_matching_wheel__"
    return [config_common.FeatureFlagInfo(value = "true" if matched else "false")]

pycross_wheel_matched = rule(
    implementation = _pycross_wheel_matched_impl,
    doc = "Boolean FeatureFlagInfo (\"true\" or \"false\") reporting whether a wheel chooser matched.",
    provides = [config_common.FeatureFlagInfo],
    attrs = {
        "chooser": attr.label(
            mandatory = True,
            providers = [config_common.FeatureFlagInfo],
            doc = "A pycross_wheel_chooser target.",
        ),
    },
)
