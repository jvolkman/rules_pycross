"""Tests for override_helpers"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:override_helpers.bzl", "encode_build_system_attrs")

# buildifier: disable=unused-variable
def _test_encode_build_system_attrs_impl(env, target):
    mock_tag = struct(
        copts = ["-O3"],
        linkopts = ["-lfoo"],
        native_deps = ["@bar//lib:lib"],
        config_settings = {"//:my_setting": "1"},
        tool_deps = ["pkg1", "pkg2"],
        build_env = {"MY_VAR": "val"},
        data = ["//pkg:data"],
        pre_build_hooks = ["//pkg:pre_hook"],
        post_build_hooks = ["//pkg:post_hook"],
        path_tools = ["//pkg:path_tool"],
    )
    res = encode_build_system_attrs(mock_tag)

    # We check string equality with the expected JSON encoding because we want to ensure
    # we produced exactly the correct JSON serialized strings.
    env.expect.that_dict(res).contains_exactly({
        "copts": json.encode(["-O3"]),
        "linkopts": json.encode(["-lfoo"]),
        "native_deps": json.encode(["@bar//lib:lib"]),
        "config_settings": json.encode({"//:my_setting": "1"}),
        "tool_deps": json.encode(["pkg1", "pkg2"]),
        "build_env": json.encode({"MY_VAR": "val"}),
        "data": json.encode(["//pkg:data"]),
        "pre_build_hooks": json.encode(["//pkg:pre_hook"]),
        "post_build_hooks": json.encode(["//pkg:post_hook"]),
        "path_tools": json.encode(["//pkg:path_tool"]),
    })

def _test_encode_build_system_attrs(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_encode_build_system_attrs_impl)

def override_helpers_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_encode_build_system_attrs,
        ],
    )
