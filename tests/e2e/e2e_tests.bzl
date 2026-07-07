"""Module docstring for tests."""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

def define_e2e_tests():
    """Create the e2e tests"""
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
        "bzlmod_flags",
        "namespace_pkgs",
        "gazelle_integration",
        "uv_workspace",
        "pdm_workspace",
        "uv_cycle",
        "uv_conflicts",
        "cross_repo_build_target",
    ]:
        extra_tags = ["build"] if ws in _BUILD_WORKSPACES else []
        sh_test(
            name = "test_" + ws,
            size = "enormous",
            srcs = ["run_integration_test.sh"],
            args = ["tests/e2e/" + ws],
            env_inherit = ["PATH", "RULES_PYCROSS_DEBUG"],
            tags = [
                "e2e",
                "integration",
                "local",
                "no-remote-exec",
            ] + extra_tags,
        )

    # This test lives under modules/ rather than tests/e2e/, but is
    # an integration test that should run with the e2e suite.
    sh_test(
        name = "test_backend_maturin_module",
        size = "enormous",
        srcs = ["run_integration_test.sh"],
        args = ["modules/backend_maturin"],
        env_inherit = ["PATH", "RULES_PYCROSS_DEBUG"],
        tags = [
            "build",
            "e2e",
            "integration",
            "local",
            "no-remote-exec",
        ],
    )
