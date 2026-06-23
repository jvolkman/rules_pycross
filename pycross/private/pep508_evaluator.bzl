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

# ---- helpers ----------------------------------------------------------------

def _parse_int(s):
    """Parse a string as an integer, returning 0 for non-numeric strings."""
    if not s:
        return 0
    _DIGITS = {"0": 0, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9}
    result = 0
    for ch in s.elems():
        if ch not in _DIGITS:
            return 0
        result = result * 10 + _DIGITS[ch]
    return result

def _compare_versions(a, b):
    """Compare two version strings segment-by-segment.

    Returns negative if a < b, zero if a == b, positive if a > b.
    """
    parts_a = a.split(".")
    parts_b = b.split(".")

    max_len = max(len(parts_a), len(parts_b))
    for i in range(max_len):
        na = _parse_int(parts_a[i]) if i < len(parts_a) else 0
        nb = _parse_int(parts_b[i]) if i < len(parts_b) else 0
        if na != nb:
            return na - nb
    return 0

def _resolve_value(node, markers):
    """Resolve a leaf node to a string value.

    Args:
        node: dict with "type" and "value" keys.
        markers: dict mapping marker names to their string values.

    Returns:
        The resolved string value.
    """
    if node["type"] == "marker":
        name = node["value"]
        if name not in markers:
            fail("Unknown PEP 508 marker: " + name)
        return markers[name]
    if node["type"] == "string":
        return node["value"]
    fail("Unknown node type: " + node["type"])

def _eval_comparison(op, lhs, rhs):
    """Evaluate a comparison operation on two string values."""
    if op == "==":
        return lhs == rhs
    if op == "!=":
        return lhs != rhs
    if op == ">=":
        return _compare_versions(lhs, rhs) >= 0
    if op == "<=":
        return _compare_versions(lhs, rhs) <= 0
    if op == ">":
        return _compare_versions(lhs, rhs) > 0
    if op == "<":
        return _compare_versions(lhs, rhs) < 0
    if op == "in":
        return lhs in rhs
    if op == "not in":
        return lhs not in rhs
    fail("Unknown PEP 508 operator: " + op)

def evaluate_marker_expr(expr, markers):
    """Evaluate a parsed PEP 508 marker expression tree (iteratively).

    Uses a two-pass approach to avoid Starlark's prohibition on recursive
    function calls: first flattens the tree into reverse-polish notation,
    then evaluates with a value stack.

    Args:
        expr: A dict representing the pre-parsed expression tree (decoded
              from JSON).
        markers: A dict mapping PEP 508 marker names to string values.

    Returns:
        True if the expression matches, False otherwise.
    """

    # Phase 1: Flatten tree to reverse-polish notation (RPN).
    # Use two stacks: `work` for DFS traversal, `rpn` for output.
    rpn = []
    work = [expr]
    for _ in range(1000):  # depth guard
        if not work:
            break
        node = work.pop()
        op = node["op"]
        if op == "and" or op == "or":
            # Push operator to rpn; push children to work (lhs last = processed first).
            rpn.append(op)
            work.append(node["lhs"])
            work.append(node["rhs"])
        else:
            # Leaf: evaluate comparison immediately, push result.
            lhs = _resolve_value(node["lhs"], markers)
            rhs = _resolve_value(node["rhs"], markers)
            rpn.append(_eval_comparison(op, lhs, rhs))

    # Phase 2: Evaluate the RPN list in reverse.
    # rpn was built by DFS: [op, ..lhs subtree.., ..rhs subtree..]
    # Reversing gives us: [..rhs subtree.., ..lhs subtree.., op]
    # which is standard RPN (operands before operator).
    stack = []
    for i in range(len(rpn) - 1, -1, -1):
        token = rpn[i]
        if type(token) == "bool":
            stack.append(token)
        elif token == "and":
            a = stack.pop()
            b = stack.pop()
            stack.append(a and b)
        elif token == "or":
            a = stack.pop()
            b = stack.pop()
            stack.append(a or b)

    if len(stack) != 1:
        fail("PEP 508 expression evaluation error: stack has {} elements".format(len(stack)))
    return stack[0]

# ---- rule implementation ----------------------------------------------------

_MARKER_ATTRS = {
    "os_name": attr.string(default = "", doc = "PEP 508 os_name marker (e.g. posix, nt)."),
    "sys_platform": attr.string(default = "", doc = "PEP 508 sys_platform marker (e.g. linux, darwin, win32)."),
    "platform_machine": attr.string(default = "", doc = "PEP 508 platform_machine marker (e.g. x86_64, aarch64)."),
    "platform_system": attr.string(default = "", doc = "PEP 508 platform_system marker (e.g. Linux, Darwin, Windows)."),
    "platform_release": attr.string(default = "", doc = "PEP 508 platform_release marker."),
    "platform_version": attr.string(default = "", doc = "PEP 508 platform_version marker."),
    "python_version": attr.string(default = "", doc = "PEP 508 python_version marker (e.g. 3.11, 3.12)."),
    "python_full_version": attr.string(default = "", doc = "PEP 508 python_full_version marker (e.g. 3.11.0)."),
    "implementation_name": attr.string(default = "", doc = "PEP 508 implementation_name marker (e.g. cpython, pypy)."),
    "implementation_version": attr.string(default = "", doc = "PEP 508 implementation_version marker."),
    "platform_python_implementation": attr.string(default = "", doc = "PEP 508 platform.python_implementation marker (e.g. CPython, PyPy)."),
}

def _pycross_pep508_evaluator_impl(ctx):
    markers = {
        "os_name": ctx.attr.os_name,
        "sys_platform": ctx.attr.sys_platform,
        "platform_machine": ctx.attr.platform_machine,
        "platform_system": ctx.attr.platform_system,
        "platform_release": ctx.attr.platform_release,
        "platform_version": ctx.attr.platform_version,
        "python_version": ctx.attr.python_version,
        "python_full_version": ctx.attr.python_full_version,
        "implementation_name": ctx.attr.implementation_name,
        "implementation_version": ctx.attr.implementation_version,
        "platform_python_implementation": ctx.attr.platform_python_implementation,
    }

    expr = json.decode(ctx.attr.expr)
    result = evaluate_marker_expr(expr, markers)

    return [config_common.FeatureFlagInfo(value = "true" if result else "false")]

_pycross_pep508_evaluator = rule(
    implementation = _pycross_pep508_evaluator_impl,
    attrs = dict(
        expr = attr.string(
            mandatory = True,
            doc = "A JSON-encoded pre-parsed PEP 508 marker expression tree.",
        ),
        **_MARKER_ATTRS
    ),
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
