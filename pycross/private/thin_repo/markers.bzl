"""Member-local `_markers/BUILD.bazel` generation for thin package repos.

Renders PEP 508 evaluators and `config_setting` targets for this member's own
`availability_markers` and member-referenced `resolution_marker_exprs`,
referencing `@<ws>__state//:_variant_state` and `@<ws>__state//:is_<variant>`
when conflict variants are active. Keeping these evaluators local to each thin
repo ensures `@<ws>__state` stays invariant when a member changes its root
markers or forks.
"""

load("//pycross/private:build_text.bzl", "config_setting_group", "flag_setting")
load(
    "//pycross/private:lock_contract.bzl",
    "constraint_setting_name",
    "marker_match_target_name",
    "state_constraint_label",
    "state_variant_state_label",
)
load("//pycross/private:util.bzl", "marker_evaluator_name")

def _render_evaluator(lines, eval_name, expr, setting_name, variant_state_lbl):
    lines.extend([
        "pycross_pep508_evaluator(",
        "    name = {},".format(json.encode(eval_name)),
        "    expr = {},".format(json.encode(expr)),
    ])
    if variant_state_lbl and expr and "__variant_" in expr:
        lines.append("    variants = [{}],".format(json.encode(variant_state_lbl)))
    lines.extend([")", ""])
    lines.extend(flag_setting(setting_name, ":" + eval_name, "true"))

def render_member_markers_build(packages, resolution_marker_exprs, state_repo, has_variants = False):
    """Render `_markers/BUILD.bazel` for a thin package repo, or None if unused.

    Args:
        packages: Slimmed member packages dict (may carry `availability_markers`).
        resolution_marker_exprs: Member-filtered `resolution_marker_exprs` dict.
        state_repo: Apparent name of the workspace's `@<ws>__state` repo.
        has_variants: Whether the workspace defines variant sets in `@<ws>__state`.

    Returns:
        Generated `_markers/BUILD.bazel` string, or None if no evaluators are needed.
    """
    unique_avail = {}
    for pkg in (packages or {}).values():
        for m in pkg.get("availability_markers", []):
            if m:
                unique_avail[m] = True

    res_exprs = resolution_marker_exprs or {}
    if not unique_avail and not res_exprs:
        return None

    variant_state_lbl = state_variant_state_label(state_repo) if has_variants else ""
    needs_evaluator = False
    needs_selects = False
    body = []

    for marker_str in sorted(unique_avail.keys()):
        needs_evaluator = True
        eval_name = marker_evaluator_name(marker_str, "")
        _render_evaluator(
            body,
            eval_name,
            marker_str,
            marker_match_target_name(eval_name),
            variant_state_lbl,
        )

    for cname, entry in sorted(res_exprs.items()):
        if type(entry) == "dict":
            needs_selects = True
            body.extend(config_setting_group(
                constraint_setting_name(cname),
                "match_all",
                [
                    state_constraint_label(state_repo, entry["variant"]),
                    ":" + constraint_setting_name(entry["marker"]),
                ],
            ))
        else:
            needs_evaluator = True
            _render_evaluator(
                body,
                "_res_eval_{}".format(cname),
                entry,
                constraint_setting_name(cname),
                variant_state_lbl,
            )

    header = []
    if needs_selects:
        header.append('load("@bazel_skylib//lib:selects.bzl", "selects")')
    if needs_evaluator:
        header.append('load("@rules_pycross//pycross/private:pep508_evaluator.bzl", "pycross_pep508_evaluator")')
    if header:
        header.append("")
    header.extend([
        'package(default_visibility = ["//:__subpackages__"])',
        "",
    ])
    return "\n".join(header + body) + "\n"
