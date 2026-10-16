"""PEP 508 marker expression evaluator rule.

Evaluates a PEP 508 marker expression at Bazel analysis time
and returns a config_common.FeatureFlagInfo with value "true" or "false".

The expression is supplied as a raw PEP 508 marker string, e.g.:
    sys_platform == 'linux' and python_version >= '3.10'

Parsing and evaluation are handled by the pypackaging markers library.
"""

load(":pep508_marker_values.bzl", "PYTHON_TOOLCHAIN_TYPE", "collect_markers", "evaluate_marker", "marker_value_attrs")
load(":providers.bzl", "PycrossConflictStateInfo")

# ---- rule implementation ----------------------------------------------------

def _pycross_pep508_evaluator_impl(ctx):
    markers_env = collect_markers(ctx)
    active_tokens = None
    if ctx.attr.conflict_state != None:
        active_tokens = ctx.attr.conflict_state[PycrossConflictStateInfo].active_tokens
    result = evaluate_marker(ctx.attr.expr, markers_env, active_tokens = active_tokens)

    return [config_common.FeatureFlagInfo(value = "true" if result else "false")]

_pycross_pep508_evaluator = rule(
    implementation = _pycross_pep508_evaluator_impl,
    attrs = dict(
        expr = attr.string(
            mandatory = True,
            doc = "A PEP 508 marker expression string.",
        ),
        conflict_state = attr.label(
            providers = [PycrossConflictStateInfo],
            doc = "Optional conflict_state target providing active uv conflict tokens.",
        ),
        **marker_value_attrs()
    ),
    toolchains = [PYTHON_TOOLCHAIN_TYPE],
)

def pycross_pep508_evaluator(name, **kwargs):
    """Evaluate a PEP 508 marker expression at analysis time.

    This macro wraps the underlying rule and returns
    config_common.FeatureFlagInfo with value "true" or "false".

    Args:
        name: The target name.
        **kwargs: Forwarded to the underlying rule.  Must include ``expr``
            and may include any PEP 508 marker dimension overrides.
    """
    _pycross_pep508_evaluator(
        name = name,
        **kwargs
    )
