load("@aspect_bazel_lib//lib:write_source_files.bzl", "write_source_files")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load(
    "@jvolkman_rules_pycross//pycross:defs.bzl",
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

    # zlib-state is just some library I found that builds against a small shared library,
    # zlib. We can use it to test the build process as well as the optional repair step.
    pycross_wheel_build(
        name = "zlib_state_build",
        sdist = "@{}_sdist_zlib_state_0.1.6//file".format(lock_name),
        deps = [
            "@{}_repo//deps:setuptools".format(lock_name),
            "@{}_repo//deps:wheel".format(lock_name),
        ],
        native_deps = [
            "//third_party/zlib",
        ],
        post_build_hooks = [
            "@jvolkman_rules_pycross//pycross/hooks:repair_wheel",
        ],
        tags = ["manual"],
        copts = ["-Wl,-s"],
    )

    pycross_lock_file(
        name = lock_name,
        lock_model_file = lock_model,
        target_environments = [
            "//:python_darwin_x86_64",
            "//:python_darwin_arm64",
            "//:python_linux_x86_64",
            "//:python_linux_arm64",
        ],
        default_alias_single_version = True,
        always_build_packages = [
            "zlib-state",
        ],
        build_target_overrides = {
            "zlib-state": "@//{}:zlib_state_build".format(native.package_name()),
        },
        package_build_dependencies = {
            "zlib-state": [
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
            "from IPython import start_ipython",
            "start_ipython()",
        ],
    )

    py_test(
        name = "ipython",
        srcs = ["ipython.py", "//:test_script.py"],
        args = ["$(location //:test_script.py)"],
        deps = [
            "@{}_repo//deps:ipython".format(lock_name),
            "@{}_repo//deps:zlib_state".format(lock_name),
        ]
    )