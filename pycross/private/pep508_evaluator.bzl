"""PEP 508 marker expression evaluator rule.

Evaluates a pre-parsed PEP 508 marker expression at Bazel analysis time
and returns a config_common.FeatureFlagInfo with value "true" or "false".

The expression is supplied as a JSON-encoded tree.  Each node is one of:

  Comparison:
    {"op": "==", "lhs": {"type": "marker", "value": "sys_platform"},
                 "rhs": {"type": "string", "value": "linux"}}

  Boolean AND / OR:
    {"op": "and", "lhs": <expr>, "rhs": <expr>}
    {"op": "or",  "lhs": <expr>, "rhs": <expr>}

Supported comparison operators: ==, !=, >=, <=, >, <, in, not in.
Version operators (>=, <=, >, <) split on '.' and compare numerically.
"""

load("//pycross/private/pypackaging/markers:markers.bzl", "markers")
load(":pep508_marker_values.bzl", "PYTHON_TOOLCHAIN_TYPE", "collect_markers", "marker_value_attrs")

# ---- rule implementation ----------------------------------------------------

def _pycross_pep508_evaluator_impl(ctx):
    markers_env = collect_markers(ctx)
    parsed_marker = markers.parse(ctx.attr.expr)
    result = markers.evaluate(parsed_marker, markers_env)

    return [config_common.FeatureFlagInfo(value = "true" if result else "false")]

_pycross_pep508_evaluator = rule(
    implementation = _pycross_pep508_evaluator_impl,
    attrs = dict(
        expr = attr.string(
            mandatory = True,
            doc = "A PEP 508 marker expression string.",
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
