"""Tests for markers.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private/packaging/markers:markers.bzl", "markers")

def _test_marker_parser_impl(env, _target):
    # Simple
    m = markers.parse("python_version >= '3.6'")
    env.expect.that_int(len(m)).equals(1)
    item = m[0]
    env.expect.that_str(item[0].type).equals("variable")
    env.expect.that_str(item[0].value).equals("python_version")
    env.expect.that_str(item[1]).equals(">=")
    env.expect.that_str(item[2].type).equals("string")
    env.expect.that_str(item[2].value).equals("3.6")

    # With parens
    m = markers.parse("(python_version >= '3.6')")
    env.expect.that_int(len(m)).equals(1)
    sub = m[0]
    env.expect.that_int(len(sub)).equals(1)
    item = sub[0]
    env.expect.that_str(item[0].value).equals("python_version")

    # Complex
    m = markers.parse("python_version >= '3.6' and os_name == 'posix'")
    env.expect.that_int(len(m)).equals(3)
    env.expect.that_str(m[1]).equals("and")

    # In
    m = markers.parse("python_version in '3.6 3.7'")
    env.expect.that_int(len(m)).equals(1)
    item = m[0]
    env.expect.that_str(item[1]).equals("in")

    # Not In
    m = markers.parse("python_version not in '3.6 3.7'")
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
        "dependency_groups": ["dev", "test"],
        "extras": ["foo", "Bar"],  # Mixed case to test normalization
    }

    # Dependency Groups
    m = markers.parse("'dev' in dependency_groups")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    m = markers.parse("'docs' in dependency_groups")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(False)

    # Extras plural
    m = markers.parse("'foo' in extras")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    m = markers.parse("'bar' in extras")  # Should match 'Bar' due to normalization
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    m = markers.parse("'baz' in extras")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(False)

    # Normalization tests
    m = markers.parse("'dev-group' in dependency_groups")
    env_vars_norm = dict(env_vars)
    env_vars_norm["dependency_groups"] = ["dev_group"]  # Underscore should match hyphen
    env.expect.that_bool(markers.evaluate(m, env_vars_norm)).equals(True)

    # Extra singular
    m = markers.parse("extra == 'dev'")
    env_vars_extra = dict(env_vars)
    env_vars_extra["extra"] = "dev"
    env.expect.that_bool(markers.evaluate(m, env_vars_extra)).equals(True)

    # Extra missing (treated as empty string)
    m = markers.parse("extra == ''")
    env_vars_no_extra = dict(env_vars)

    # Don't set "extra"
    env.expect.that_bool(markers.evaluate(m, env_vars_no_extra)).equals(True)

    # Extra normalization
    m = markers.parse("extra == 'dev-group'")
    env_vars_extra_norm = dict(env_vars)
    env_vars_extra_norm["extra"] = "dev_group"
    env.expect.that_bool(markers.evaluate(m, env_vars_extra_norm)).equals(True)

    # Simple True
    m = markers.parse("python_version >= '3.6'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # Simple False
    m = markers.parse("python_version < '3.6'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(False)

    # AND True
    m = markers.parse("python_version >= '3.6' and os_name == 'posix'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # AND False
    m = markers.parse("python_version >= '3.6' and os_name == 'nt'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(False)

    # OR True
    m = markers.parse("python_version < '3.6' or os_name == 'posix'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # Nested
    m = markers.parse("python_version < '3.6' or (os_name == 'posix' and sys_platform == 'linux')")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # In
    m = markers.parse("python_version in '3.6 3.7'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # Not In
    m = markers.parse("python_version not in '3.6 3.7'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(False)

    # Version marker with 'in' (should be treated as string containment)
    m = markers.parse("python_version in '3.7.1 3.7.2'")
    env.expect.that_bool(markers.evaluate(m, env_vars)).equals(True)

    # Precedence test vars
    env_vars_prec = {
        "python_version": "3.5",  # python_version < '3.6' is True
        "os_name": "nt",  # os_name == 'posix' is False
        "sys_platform": "win32",  # sys_platform == 'linux' is False
    }

    # Standard precedence: A or B and C -> True or (False and False) -> True
    m = markers.parse("python_version < '3.6' or os_name == 'posix' and sys_platform == 'linux'")
    env.expect.that_bool(markers.evaluate(m, env_vars_prec)).equals(True)

    # Explicit precedence: (A or B) and C -> (True or False) and False -> False
    m = markers.parse("(python_version < '3.6' or os_name == 'posix') and sys_platform == 'linux'")
    env.expect.that_bool(markers.evaluate(m, env_vars_prec)).equals(False)

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
