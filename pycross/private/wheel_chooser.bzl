"""Wheel chooser rule for selecting the best-matching wheel at analysis time.

Given a list of wheel filenames and a target platform providing compatible
PEP 425 tags (ordered by preference), this rule picks the best compatible
wheel and returns its filename through config_common.FeatureFlagInfo.

The selection algorithm:
  1. Iterate through the target platform's supported tags in order of preference.
  2. For each tag, check if any candidate matches.
  3. Return the first matching candidate's filename, or
     "__no_matching_wheel__" if nothing matches.
"""

load("@pypackaging.bzl", "pypackaging")
load(":target_platform.bzl", "PycrossTargetPlatformInfo")

# ---------------------------------------------------------------------------
# Pure-function helpers
# ---------------------------------------------------------------------------

def select_best_wheel(filenames, supported_tags):
    """Select the best-matching wheel from a list of filenames.

    Args:
        filenames: List of candidate wheel filenames.
        supported_tags: List of compatible tag strings, ordered by preference.

    Returns:
        The best matching filename, or None if no candidate is compatible.
    """

    # Pre-process candidates to parse tags
    processed = []
    for f in filenames:
        parsed = pypackaging.utils.parse_wheel_filename(f)
        processed.append({
            "filename": f,
            "tags": parsed.tags,
        })

    for tag_str in supported_tags:
        for pt in pypackaging.tags.parse_tag(tag_str):
            for c in processed:
                if pt in c["tags"]:
                    return c["filename"]

    return None

# ---------------------------------------------------------------------------
# Rule implementation
# ---------------------------------------------------------------------------

def _pycross_wheel_chooser_impl(ctx):
    candidates = ctx.attr.candidates
    supported_tags = ctx.attr.supported_tags[PycrossTargetPlatformInfo].compatibility_tags

    best = select_best_wheel(candidates, supported_tags)

    if best:
        value = best
    else:
        value = "__no_matching_wheel__"

    return [config_common.FeatureFlagInfo(value = value)]

_pycross_wheel_chooser = rule(
    implementation = _pycross_wheel_chooser_impl,
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

def pycross_wheel_chooser(name, **kwargs):
    """Select the best-matching wheel from a list of candidates.

    This macro wraps the private _pycross_wheel_chooser rule. It takes a
    list of candidate wheel filenames and a target platform (which provides
    ordered compatibility tags), and produces a config_common.FeatureFlagInfo
    whose value is the filename of the best matching wheel.

    Args:
        name: The target name.
        **kwargs: Forwarded to _pycross_wheel_chooser.
    """
    _pycross_wheel_chooser(name = name, **kwargs)
