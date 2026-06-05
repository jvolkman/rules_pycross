load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//rules:generate_cargo_lock.bzl", "pycross_generate_cargo_lock")

def _test_generate_cargo_lock_basic(name):
    util.helper_target(
        native.filegroup,
        name = name + "_sdist",
        srcs = ["test-sdist.tar.gz"],
    )

    util.helper_target(
        pycross_generate_cargo_lock,
        name = name + "_subject",
        sdist = name + "_sdist",
        output = "test-Cargo.lock",
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_generate_cargo_lock_basic_impl,
    )

def _test_generate_cargo_lock_basic_impl(env, target):
    # Check that it returns an executable default info
    env.expect.that_target(target).has_provider(DefaultInfo)
    env.expect.that_target(target).default_outputs().contains_exactly([
        "{}/{}_runner.sh".format(target.label.package, target.label.name)
    ])

def generate_cargo_lock_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_generate_cargo_lock_basic,
        ],
    )
