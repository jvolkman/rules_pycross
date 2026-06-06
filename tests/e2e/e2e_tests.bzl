"""Module docstring for tests."""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

def define_e2e_tests():
    for ws in [
        "always_build",
        "build_cmake",
        "build_maturin",
        "build_meson",
        "build_pure_python",
        "build_setuptools",
        "generate_lock",
        "local_wheel",
        "patches_and_hooks",
        "requirements",
        "sdist_repo",
        "bzlmod_flags",
    ]:
        sh_test(
            name = "test_" + ws,
            size = "enormous",
            srcs = ["run_integration_test.sh"],
            args = ["tests/e2e/" + ws],
            env_inherit = ["PATH"],
            tags = [
                "integration",
                "local",
                "no-remote-exec",
            ],
        )
