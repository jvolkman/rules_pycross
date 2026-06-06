"""Module docstring for tests."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")

# buildifier: disable=bzl-visibility
# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossPackageInfo")

# buildifier: disable=bzl-visibility
# buildifier: disable=bzl-visibility
load("//pycross/private/build/rules:common_attrs.bzl", "group_tool_deps")

TestingInfo = provider(doc = "TestingInfo", fields = ["result"])

def _mock_pkg_impl(ctx):
    return [PycrossPackageInfo(package_name = ctx.attr.package_name)]

mock_pkg = rule(
    implementation = _mock_pkg_impl,
    attrs = {
        "package_name": attr.string(mandatory = True),
    },
)

# buildifier: disable=unused-variable
def _mock_other_impl(ctx):
    return []

mock_other = rule(
    implementation = _mock_other_impl,
)

def _test_rule_impl(ctx):
    dep1 = ctx.attr.dep1
    dep2 = ctx.attr.dep2
    dep3 = ctx.attr.dep3
    other = ctx.attr.other

    result = group_tool_deps([d for d in [dep1, dep2, dep3, other] if d != None])

    # Store result to be accessed by the test
    return [TestingInfo(result = result)]

group_tool_deps_subject = rule(
    implementation = _test_rule_impl,
    attrs = {
        "dep1": attr.label(),
        "dep2": attr.label(),
        "dep3": attr.label(),
        "other": attr.label(),
    },
)

# buildifier: disable=unused-variable
def _group_tool_deps_test_impl(env, target):
    result = target[TestingInfo].result

    env.expect.that_int(len(result)).equals(2)

    env.expect.that_int(len(result.get("pkg_a", []))).equals(2)
    env.expect.that_int(len(result.get("pkg_b", []))).equals(1)

def group_tool_deps_test(name):
    """Test group_tool_deps.

    Args:
        name: Name of the test
    """
    mock_pkg(name = name + "_dep1", package_name = "pkg_a")
    mock_pkg(name = name + "_dep2", package_name = "pkg_b")
    mock_pkg(name = name + "_dep3", package_name = "pkg_a")
    mock_other(name = name + "_other")

    group_tool_deps_subject(
        name = name + "_subject",
        dep1 = ":" + name + "_dep1",
        dep2 = ":" + name + "_dep2",
        dep3 = ":" + name + "_dep3",
        other = ":" + name + "_other",
    )

    analysis_test(
        name = name,
        target = ":" + name + "_subject",
        impl = _group_tool_deps_test_impl,
    )

# buildifier: disable=unused-variable
def _group_tool_deps_empty_impl(env, target):
    res = group_tool_deps([])
    env.expect.that_dict(res).contains_exactly({})

def _group_tool_deps_empty_test(name):
    group_tool_deps_subject(name = name + "_subject")
    analysis_test(name = name, target = ":" + name + "_subject", impl = _group_tool_deps_empty_impl)

# buildifier: disable=unused-variable
def _group_tool_deps_no_pkg_impl(env, target):
    res = target[TestingInfo].result
    env.expect.that_dict(res).contains_exactly({})

def _group_tool_deps_no_pkg_test(name):
    mock_other(name = name + "_other1")
    mock_other(name = name + "_other2")
    group_tool_deps_subject(
        name = name + "_subject",
        other = ":" + name + "_other1",
        dep1 = ":" + name + "_other2",
    )
    analysis_test(name = name, target = ":" + name + "_subject", impl = _group_tool_deps_no_pkg_impl)

# buildifier: disable=unused-variable
def _group_tool_deps_single_impl(env, target):
    res = target[TestingInfo].result
    env.expect.that_int(len(res)).equals(1)
    env.expect.that_int(len(res.get("pkg_a", []))).equals(1)

def _group_tool_deps_single_test(name):
    mock_pkg(name = name + "_dep1", package_name = "pkg_a")
    group_tool_deps_subject(
        name = name + "_subject",
        dep1 = ":" + name + "_dep1",
    )
    analysis_test(name = name, target = ":" + name + "_subject", impl = _group_tool_deps_single_impl)

# buildifier: disable=unused-variable
def _group_tool_deps_same_impl(env, target):
    res = target[TestingInfo].result
    env.expect.that_int(len(res)).equals(1)
    env.expect.that_int(len(res.get("pkg_a", []))).equals(3)

def _group_tool_deps_same_test(name):
    mock_pkg(name = name + "_dep1", package_name = "pkg_a")
    mock_pkg(name = name + "_dep2", package_name = "pkg_a")
    mock_pkg(name = name + "_dep3", package_name = "pkg_a")
    group_tool_deps_subject(
        name = name + "_subject",
        dep1 = ":" + name + "_dep1",
        dep2 = ":" + name + "_dep2",
        dep3 = ":" + name + "_dep3",
    )
    analysis_test(name = name, target = ":" + name + "_subject", impl = _group_tool_deps_same_impl)

def common_attrs_test_suite(name):
    test_suite(
        name = name,
        tests = [
            group_tool_deps_test,
            _group_tool_deps_empty_test,
            _group_tool_deps_no_pkg_test,
            _group_tool_deps_single_test,
            _group_tool_deps_same_test,
        ],
    )
