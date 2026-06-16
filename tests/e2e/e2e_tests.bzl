"""Module docstring for tests."""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

def define_e2e_tests():
    _BUILD_WORKSPACES = [
        "build_cmake",
        "build_maturin",
        "build_meson",
        "build_pure_python",
        "build_setuptools",
    ]
    for ws in [
        "always_build",
    ] + _BUILD_WORKSPACES + [
        "generate_lock",
        "local_wheel",
        "patches_and_hooks",
        "requirements",
        "sdist_repo",
        "squash_extras",
        "bzlmod_flags",
        "namespace_pkgs",
        "gazelle_integration",
        "uv_workspace",
    ]:
        extra_tags = ["build"] if ws in _BUILD_WORKSPACES else []
        sh_test(
            name = "test_" + ws,
            size = "enormous",
            srcs = ["run_integration_test.sh"],
            args = ["tests/e2e/" + ws],
            env_inherit = ["PATH"],
            tags = [
                "e2e",
                "integration",
                "local",
                "no-remote-exec",
            ] + extra_tags,
        )
