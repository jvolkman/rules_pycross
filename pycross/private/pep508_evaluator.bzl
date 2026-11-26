"""PEP 508 marker expression evaluator rule.

Evaluates a PEP 508 marker expression at Bazel analysis time
and returns a config_common.FeatureFlagInfo with value "true" or "false".

The expression is supplied as a raw PEP 508 marker string, e.g.:
    sys_platform == 'linux' and python_version >= '3.10'

Parsing and evaluation are handled by the pypackaging markers library.
"""

load("@pypackaging.bzl", "pypackaging")
load(":pep508_marker_values.bzl", "collect_markers", "marker_value_attrs")

# ---- rule implementation ----------------------------------------------------

def _pycross_pep508_evaluator_impl(ctx):
    markers_env = collect_markers(ctx)
    parsed_marker = pypackaging.markers.parse(ctx.attr.expr)
    result = pypackaging.markers.evaluate(parsed_marker, markers_env)

    return [config_common.FeatureFlagInfo(value = "true" if result else "false")]

pycross_pep508_evaluator = rule(
    implementation = _pycross_pep508_evaluator_impl,
    doc = "Evaluate a PEP 508 marker expression at analysis time, returning FeatureFlagInfo with value \"true\" or \"false\".",
    attrs = dict(
        expr = attr.string(
            mandatory = True,
            doc = "A PEP 508 marker expression string.",
        ),
        **marker_value_attrs()
    ),
)
