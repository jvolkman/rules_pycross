"""Analysis tests for MSVC action environment extraction."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")

def _config(target):
    for action in target.actions:
        for output in action.outputs.to_list():
            if output.basename.endswith("_cc_config.json"):
                return json.decode(action.content)
    fail("no cc_config.json action")

def _environment_test_impl(env, target, style):
    msvc_env = _config(target).get("msvc_env", {})
    if style in ["none", "not_found"]:
        env.expect.that_collection(msvc_env.keys()).contains_exactly([])
    elif style == "mixed_not_found":
        env.expect.that_collection(msvc_env.keys()).contains_exactly(["PATH", "INCLUDE"])
        env.expect.that_str(msvc_env["PATH"]).equals("external/review_msvc/bin")
        env.expect.that_str(msvc_env["INCLUDE"]).equals("external/msvc_not_found_sdk/include")
    elif style == "partial":
        env.expect.that_collection(msvc_env.keys()).contains_exactly(["PATH", "INCLUDE"])
        env.expect.that_str(msvc_env["PATH"]).equals("external/review_msvc/bin")
        env.expect.that_str(msvc_env["INCLUDE"]).equals("external/review_msvc/include")
    else:
        env.expect.that_collection(msvc_env.keys()).contains_exactly(["PATH", "INCLUDE", "LIB"])
        env.expect.that_str(msvc_env["PATH"]).equals("external/review_msvc/bin")
        env.expect.that_str(msvc_env["INCLUDE"]).equals("external/review_msvc/include")
        env.expect.that_str(msvc_env["LIB"]).equals("external/review_msvc/lib")

def _none_impl(env, target):
    _environment_test_impl(env, target, "none")

def _mixed_impl(env, target):
    _environment_test_impl(env, target, "mixed")

def _upper_impl(env, target):
    _environment_test_impl(env, target, "upper")

def _partial_impl(env, target):
    _environment_test_impl(env, target, "partial")

def _not_found_impl(env, target):
    _environment_test_impl(env, target, "not_found")

def _mixed_not_found_impl(env, target):
    _environment_test_impl(env, target, "mixed_not_found")

def _environment_test(name, impl):
    analysis_test(
        name = "test_" + name,
        target = ":subject",
        impl = impl,
        config_settings = {
            "//command_line_option:platforms": [str(Label(":win"))],
            "//command_line_option:extra_toolchains": [str(Label(":tc_" + name))],
        },
    )

def probe_test_suite(name):
    """Creates analysis tests for custom MSVC toolchain environments.

    Args:
      name: Name of the native test suite target.
    """
    _environment_test("none", _none_impl)
    _environment_test("mixed", _mixed_impl)
    _environment_test("upper", _upper_impl)
    _environment_test("partial", _partial_impl)
    _environment_test("not_found", _not_found_impl)
    _environment_test("mixed_not_found", _mixed_not_found_impl)
    native.test_suite(
        name = name,
        tests = [
            ":test_none",
            ":test_mixed",
            ":test_upper",
            ":test_partial",
            ":test_not_found",
            ":test_mixed_not_found",
        ],
    )
