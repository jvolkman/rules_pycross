"""Tests for markers.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private/packaging/markers:markers.bzl", "evaluate_markers", "parse_marker")

def _test_marker_parser_impl(env, _target):
    # Simple
    m = parse_marker("python_version >= '3.6'")
    env.expect.that_int(len(m)).equals(1)
    item = m[0]
    env.expect.that_str(item[0].type).equals("variable")
    env.expect.that_str(item[0].value).equals("python_version")
    env.expect.that_str(item[1]).equals(">=")
    env.expect.that_str(item[2].type).equals("string")
    env.expect.that_str(item[2].value).equals("3.6")

    # With parens
    m = parse_marker("(python_version >= '3.6')")
    env.expect.that_int(len(m)).equals(1)
    sub = m[0]
    env.expect.that_int(len(sub)).equals(1)
    item = sub[0]
    env.expect.that_str(item[0].value).equals("python_version")

    # Complex
    m = parse_marker("python_version >= '3.6' and os_name == 'posix'")
    env.expect.that_int(len(m)).equals(3)
    env.expect.that_str(m[1]).equals("and")

    # In
    m = parse_marker("python_version in '3.6 3.7'")
    env.expect.that_int(len(m)).equals(1)
    item = m[0]
    env.expect.that_str(item[1]).equals("in")

    # Not In
    m = parse_marker("python_version not in '3.6 3.7'")
    env.expect.that_int(len(m)).equals(1)
    item = m[0]
    env.expect.that_str(item[1]).equals("not in")

def _test_marker_parser(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_parser_impl)

def _test_marker_evaluation_impl(env, _target):
    env_vars = {
        "python_version": "3.7",
        "os_name": "posix",
        "sys_platform": "linux",
        "platform_python_implementation": "CPython",
    }

    # Simple True
    m = parse_marker("python_version >= '3.6'")
    env.expect.that_bool(evaluate_markers(m, env_vars)).equals(True)

    # Simple False
    m = parse_marker("python_version < '3.6'")
    env.expect.that_bool(evaluate_markers(m, env_vars)).equals(False)

    # AND True
    m = parse_marker("python_version >= '3.6' and os_name == 'posix'")
    env.expect.that_bool(evaluate_markers(m, env_vars)).equals(True)

    # AND False
    m = parse_marker("python_version >= '3.6' and os_name == 'nt'")
    env.expect.that_bool(evaluate_markers(m, env_vars)).equals(False)

    # OR True
    m = parse_marker("python_version < '3.6' or os_name == 'posix'")
    env.expect.that_bool(evaluate_markers(m, env_vars)).equals(True)

    # Nested
    m = parse_marker("python_version < '3.6' or (os_name == 'posix' and sys_platform == 'linux')")
    env.expect.that_bool(evaluate_markers(m, env_vars)).equals(True)

    # In
    m = parse_marker("python_version in '3.6 3.7'")
    env.expect.that_bool(evaluate_markers(m, env_vars)).equals(True)

    # Not In
    m = parse_marker("python_version not in '3.6 3.7'")
    env.expect.that_bool(evaluate_markers(m, env_vars)).equals(False)

    # Version marker with 'in' (should be treated as string containment)
    m = parse_marker("python_version in '3.7.1 3.7.2'")
    env.expect.that_bool(evaluate_markers(m, env_vars)).equals(True)

    # Precedence test vars
    env_vars_prec = {
        "python_version": "3.5",  # python_version < '3.6' is True
        "os_name": "nt",  # os_name == 'posix' is False
        "sys_platform": "win32",  # sys_platform == 'linux' is False
    }

    # Standard precedence: A or B and C -> True or (False and False) -> True
    m = parse_marker("python_version < '3.6' or os_name == 'posix' and sys_platform == 'linux'")
    env.expect.that_bool(evaluate_markers(m, env_vars_prec)).equals(True)

    # Explicit precedence: (A or B) and C -> (True or False) and False -> False
    m = parse_marker("(python_version < '3.6' or os_name == 'posix') and sys_platform == 'linux'")
    env.expect.that_bool(evaluate_markers(m, env_vars_prec)).equals(False)

def _test_marker_evaluation(name):
    util.helper_target(native.filegroup, name = name + "_subject")
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_evaluation_impl)

def markers_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_marker_parser,
            _test_marker_evaluation,
        ],
    )
