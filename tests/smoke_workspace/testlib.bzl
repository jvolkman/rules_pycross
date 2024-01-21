"""Shared test code"""

load("@aspect_bazel_lib//lib:write_source_files.bzl", "write_source_files")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load(
    "@rules_pycross//pycross:defs.bzl",
    "pycross_lock_file",
    "pycross_wheel_build",
)
load("@rules_python//python:defs.bzl", "py_test")

def setup_test_targets(lock_name, lock_model):
    """Create common test targets.

    Args:
        lock_name: the name of the lock target to create
        lock_model: the target providing the lock model
    """

    pycross_wheel_build(
        name = "zstandard_build",
        sdist = "@{}_sdist_zstandard_0.22.0//file".format(lock_name),
        deps = [
            "@{}_repo//deps:setuptools".format(lock_name),
            "@{}_repo//deps:wheel".format(lock_name),
        ],
        native_deps = [
            "//third_party/zstd",
        ],
        post_build_hooks = [
            "@rules_pycross//pycross/hooks:repair_wheel",
        ],
        config_settings = {
            "--build-option": [
                "--no-cffi-backend",
                "--system-zstd",
            ],
        },
        tags = ["manual"],
        copts = ["-Wl,-s"],
    )

    pycross_lock_file(
        name = lock_name,
        lock_model_file = lock_model,
        target_environments = ["@smoke_environments//:environments"],
        default_alias_single_version = True,
        always_build_packages = [
            "regex",
            "zstandard",
        ],
        build_target_overrides = {
            "zstandard": "@@//{}:zstandard_build".format(native.package_name()),
        },
        package_build_dependencies = {
            "regex": [
                "setuptools",
                "wheel",
            ],
            "zstandard": [
                "setuptools",
                "wheel",
            ],
        },
        out = "updated_lock.bzl",
    )

    write_source_files(
        name = "update_lock",
        files = {
            "lock.bzl": ":updated_lock.bzl",
        },
    )

    write_file(
        name = "ipython_py",
        out = "ipython.py",
        content = [
            "import os",
            "import tempfile",
            "from IPython import start_ipython",
            "with tempfile.TemporaryDirectory() as d:",
            "  os.environ['IPYTHONDIR'] = str(d)",
            "  start_ipython()",
        ],
    )

    py_test(
        name = "test_library_usage_via_ipython",
        srcs = ["ipython.py", "//:test_zstandard.py"],
        args = ["$(location //:test_zstandard.py)"],
        main = "ipython.py",
        deps = [
            "@{}_repo//deps:ipython".format(lock_name),
            "@{}_repo//deps:zstandard".format(lock_name),
        ],
    )

    py_test(
        name = "test_regex",
        srcs = ["//:test_regex.py"],
        deps = ["@{}_repo//deps:regex".format(lock_name)],
    )
