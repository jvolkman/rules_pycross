"""PEP 508 Marker parsing and evaluation.

Derived from pypa/packaging: packaging/markers.py (Apache 2.0 / BSD).
Baseline: pypa/packaging 26.2
"""

load("@re.bzl", "re")
load("//pycross/private/packaging/specifiers:specifiers.bzl", "parse_specifier", "specifier_contains")

_MARKER_RULES = {
    "LEFT_PARENTHESIS": re.compile(r"\("),
    "RIGHT_PARENTHESIS": re.compile(r"\)"),
    "QUOTED_STRING": re.compile(r"('[^']*'|\"[^\"]*\")"),
    "OP": re.compile(r"(===|==|~=|!=|<=|>=|<|>)"),
    "BOOLOP": re.compile(r"\b(or|and)\b"),
    "IN": re.compile(r"\bin\b"),
    "NOT": re.compile(r"\bnot\b"),
    "VARIABLE": re.compile(r"\b(python_version|python_full_version|os[._]name|sys[._]platform|platform_(release|system)|platform[._](version|machine|python_implementation)|python_implementation|implementation_(name|version)|extras?|dependency_groups)\b"),
    "WS": re.compile(r"[ \t]+"),
    "END": re.compile(r"$"),
}

def _make_tokenizer(source):
    # Use a dict to allow mutation in Starlark
    return {
        "source": source,
        "position": 0,
        "next_token": None,
    }

def _tokenizer_check(tokenizer, name, peek = False):
    if tokenizer["next_token"] != None:
        fail("Cannot check for {}, already have {}".format(name, tokenizer["next_token"]))

    pattern = _MARKER_RULES.get(name)
    if not pattern:
        fail("Unknown token name: {}".format(name))

    # Use slicing since we don't know if re.bzl supports offset
    m = pattern.match(tokenizer["source"][tokenizer["position"]:])
    if not m:
        return False

    if not peek:
        tokenizer["next_token"] = struct(
            name = name,
            text = m.group(0),
            position = tokenizer["position"],
        )
    return True

def _tokenizer_read(tokenizer):
    token = tokenizer["next_token"]
    if token == None:
        fail("No token to read")

    tokenizer["position"] += len(token.text)
    tokenizer["next_token"] = None

    return token

def _tokenizer_consume(tokenizer, name):
    if _tokenizer_check(tokenizer, name):
        _tokenizer_read(tokenizer)

def _tokenizer_expect(tokenizer, name, expected):
    if not _tokenizer_check(tokenizer, name):
        fail("Expected {}".format(expected))
    return _tokenizer_read(tokenizer)

def _parse_marker_var(tokenizer):
    if _tokenizer_check(tokenizer, "VARIABLE"):
        token = _tokenizer_read(tokenizer)
        return struct(type = "variable", value = token.text.replace(".", "_"))
    elif _tokenizer_check(tokenizer, "QUOTED_STRING"):
        token = _tokenizer_read(tokenizer)

        # Strip quotes
        val = token.text[1:-1]
        return struct(type = "string", value = val)
    else:
        fail("Expected a marker variable or quoted string")

def _parse_marker_op(tokenizer):
    if _tokenizer_check(tokenizer, "IN"):
        _tokenizer_read(tokenizer)
        return "in"
    elif _tokenizer_check(tokenizer, "NOT"):
        _tokenizer_read(tokenizer)
        _tokenizer_expect(tokenizer, "WS", "whitespace after 'not'")
        _tokenizer_expect(tokenizer, "IN", "'in' after 'not'")
        return "not in"
    elif _tokenizer_check(tokenizer, "OP"):
        token = _tokenizer_read(tokenizer)
        return token.text
    else:
        fail("Expected marker operator")

def _parse_marker_item(tokenizer):
    _tokenizer_consume(tokenizer, "WS")
    lhs = _parse_marker_var(tokenizer)
    _tokenizer_consume(tokenizer, "WS")
    op = _parse_marker_op(tokenizer)
    _tokenizer_consume(tokenizer, "WS")
    rhs = _parse_marker_var(tokenizer)
    _tokenizer_consume(tokenizer, "WS")
    return (lhs, op, rhs)

def parse_marker(marker_str):
    """Parses a PEP 508 marker string into an AST-like structure.

    Args:
        marker_str: The marker string to parse.

    Returns:
        A list representing the parsed marker tree.
    """
    if not marker_str.strip():
        return []

    tokenizer = _make_tokenizer(marker_str)
    current_expr = []
    expr_stack = []
    expecting_atom = True

    for _ in range(1000):
        _tokenizer_consume(tokenizer, "WS")

        if _tokenizer_check(tokenizer, "END", peek = True):
            break

        if expecting_atom:
            if _tokenizer_check(tokenizer, "LEFT_PARENTHESIS"):
                _tokenizer_read(tokenizer)  # consume '('
                expr_stack.append(current_expr)
                current_expr = []
            else:
                item = _parse_marker_item(tokenizer)
                current_expr.append(item)
                expecting_atom = False
        elif _tokenizer_check(tokenizer, "BOOLOP"):
            token = _tokenizer_read(tokenizer)
            current_expr.append(token.text)
            expecting_atom = True
        elif _tokenizer_check(tokenizer, "RIGHT_PARENTHESIS"):
            _tokenizer_read(tokenizer)  # consume ')'
            if not expr_stack:
                fail("Unexpected ')'")
            subexpr = current_expr
            current_expr = expr_stack.pop()
            current_expr.append(subexpr)
        else:
            fail("Expected BOOLOP or ')'")

    if expr_stack:
        fail("Missing ')'")

    return current_expr

_MARKERS_REQUIRING_VERSION = {
    "implementation_version": True,
    "platform_release": True,
    "python_full_version": True,
    "python_version": True,
}

def _canonicalize_name(name):
    name = name.lower().replace("_", "-").replace(".", "-")

    # Collapse runs of hyphens
    for _i in range(1000):
        if "--" in name:
            name = name.replace("--", "-")
        else:
            break
    return name

def _eval_item(item, environment):
    lhs, op, rhs = item

    if lhs.type == "variable":
        key = lhs.value
        lhs_val = environment.get(key)
        if lhs_val == None:
            if key == "extra":
                lhs_val = ""
            else:
                fail("Undefined environment variable: {}".format(key))
        rhs_val = rhs.value
    else:
        key = rhs.value
        lhs_val = lhs.value
        rhs_val = environment.get(key)
        if rhs_val == None:
            if key == "extra":
                rhs_val = ""
            else:
                fail("Undefined environment variable: {}".format(key))

    # Apply canonicalization for PEP 685 / PEP 735
    if key in ("extra", "extras", "dependency_groups"):
        if type(lhs_val) == "list":
            # buildifier: disable=string-iteration
            lhs_val = [_canonicalize_name(v) for v in lhs_val]
        elif type(lhs_val) == "string":
            lhs_val = _canonicalize_name(lhs_val)

        if type(rhs_val) == "list":
            # buildifier: disable=string-iteration
            rhs_val = [_canonicalize_name(v) for v in rhs_val]
        elif type(rhs_val) == "string":
            rhs_val = _canonicalize_name(rhs_val)

    if key in _MARKERS_REQUIRING_VERSION and op not in ("in", "not in"):
        # Use specifier_contains
        spec = parse_specifier("{}{}".format(op, rhs_val))
        return specifier_contains(spec, lhs_val)

    # Standard operators
    if op == "==":
        return lhs_val == rhs_val
    if op == "!=":
        return lhs_val != rhs_val
    if op == "<=":
        return lhs_val <= rhs_val
    if op == "<":
        return lhs_val < rhs_val
    if op == ">=":
        return lhs_val >= rhs_val
    if op == ">":
        return lhs_val > rhs_val
    if op == "~=":
        return lhs_val >= rhs_val
    if op == "===":
        return lhs_val == rhs_val
    if op == "in":
        return lhs_val in rhs_val
    if op == "not in":
        return lhs_val not in rhs_val

    fail("Unsupported operator: {}".format(op))

def _all(iterable):
    for item in iterable:
        if not item:
            return False
    return True

def _any(iterable):
    for item in iterable:
        if item:
            return True
    return False

def evaluate_markers(markers, environment):
    """Evaluates a parsed marker expression against an environment.

    Args:
        markers: The parsed marker tree (list).
        environment: A dict mapping environment variables to values.

    Returns:
        True if the markers evaluate to true, False otherwise.
    """
    if not markers:
        return True

    # Stack holds tuples: (markers_list, index, groups)
    stack = [(markers, 0, [[]])]

    for _ in range(1000):
        if not stack:
            break

        current_markers, i, groups = stack[-1]

        if i >= len(current_markers):
            # Level finished
            result = _any([_all(g) for g in groups])
            stack.pop()
            if stack:
                stack[-1][2][-1].append(result)
            else:
                return result
            continue

        marker = current_markers[i]

        if type(marker) == type([]):
            # Sub-expression
            # Advance parent index BEFORE pushing
            stack[-1] = (current_markers, i + 1, groups)
            stack.append((marker, 0, [[]]))
        elif type(marker) == type(()):
            # Comparison item
            val = _eval_item(marker, environment)
            groups[-1].append(val)
            stack[-1] = (current_markers, i + 1, groups)
        elif marker == "or":
            groups.append([])
            stack[-1] = (current_markers, i + 1, groups)
        elif marker == "and":
            stack[-1] = (current_markers, i + 1, groups)
        else:
            fail("Unexpected marker: {}".format(marker))

    fail("Evaluation exceeded iteration limit")

markers = struct(
    parse = parse_marker,
    evaluate = evaluate_markers,
)
