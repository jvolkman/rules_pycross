"""Module docstring for tests."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//private:cargo_lock_package_repo_hook.bzl", "cargo_lock_package_repo_hook")
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
    out_file = "{}/{}_runner.sh".format(target.label.package, target.label.name)
    env.expect.that_target(target).default_outputs().contains_exactly([out_file])

    # Check action content (uses registered rust toolchain cargo when available).
    action = env.expect.that_target(target).action_generating(out_file)
    action.content().contains("TOOL_PATH")
    action.content().contains("SDIST_PATH")
    action.content().contains("CARGO_PATH=")
    action.content().contains('--cargo "$CARGO_PATH"')

# buildifier: disable=unused-variable
def _test_cargo_lock_hook_overrides_impl(env, target):
    packages_info = {
        "jiter": {
            "versions": [
                struct(version = "0.5.0", package_key = "jiter@0.5.0", has_sdist = True),
                struct(version = "0.6.0", package_key = "jiter@0.6.0", has_sdist = True),
            ],
        },
        "wheel-only": {
            "versions": [
                struct(version = "1.0.0", package_key = "wheel-only@1.0.0", has_sdist = False),
            ],
        },
    }

    # No matching sdist targets -> returns empty list (no empty _cargo/BUILD.bazel).
    env.expect.that_collection(
        cargo_lock_package_repo_hook(packages_info, {"wheel-only": {}}),
    ).contains_exactly([])

    # Precedence: name@version overrides name overrides "*".
    entries = cargo_lock_package_repo_hook(
        packages_info,
        {
            "*": {"cargo_lock": json.encode("//:default.Cargo.lock")},
            "jiter": {"cargo_lock": json.encode("//:jiter.Cargo.lock")},
            "jiter@0.6.0": {"cargo_lock": json.encode("//cargo:jiter_06.Cargo.lock")},
        },
    )
    env.expect.that_int(len(entries)).equals(1)
    env.expect.that_str(entries[0].dir).equals("_cargo")
    build = entries[0].files["BUILD.bazel"]
    env.expect.that_str(build).contains('name = "jiter@0.5.0",')
    env.expect.that_str(build).contains('output = "jiter.Cargo.lock",')
    env.expect.that_str(build).contains('name = "jiter@0.6.0",')
    env.expect.that_str(build).contains('output = "cargo/jiter_06.Cargo.lock",')
    env.expect.that_bool("wheel-only" in build).equals(False)

def _test_cargo_lock_hook_overrides(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cargo_lock_hook_overrides_impl)

def generate_cargo_lock_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_generate_cargo_lock_basic,
            _test_cargo_lock_hook_overrides,
        ],
    )
