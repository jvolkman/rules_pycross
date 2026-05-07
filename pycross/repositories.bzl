"""Declare runtime dependencies"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//pycross/private:internal_repo.bzl", "create_internal_repo")
load("//pycross/private:pycross_deps.lock.bzl", pypi_all_repositories = "repositories")
load("//pycross/private:pycross_deps_core.lock.bzl", core_files = "FILES")

def rules_pycross_dependencies(python_interpreter_target = None, python_interpreter = None):
    """Runtime dependencies that users must install.

    This function should be loaded and called in the user's `WORKSPACE`.
    With `bzlmod` enabled, this function is not needed since `MODULE.bazel` handles transitive deps.

    Args:
        python_interpreter_target: Label, the python interpreter to use in label.
        python_interpreter: str, the python interpreter to use.
    """

    # The minimal version of bazel_skylib we require
    maybe(
        http_archive,
        name = "bazel_skylib",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.2.1/bazel-skylib-1.2.1.tar.gz",
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.2.1/bazel-skylib-1.2.1.tar.gz",
        ],
        sha256 = "f7be3474d42aae265405a592bb7da8e171919d74c16f082a5457840f06054728",
    )

    pypi_all_repositories()
    create_internal_repo(
        python_interpreter_target = python_interpreter_target,
        python_interpreter = python_interpreter,
        wheels = core_files,
    )

    # TODO: patch-ng doesn't upload built wheels, only sdists, so we can't pull it
    # normally through our rules (would create a bootstrapping problem).
    # The library is a single file with no dependencies, we can just pull manually for now.
    # See https://github.com/conan-io/python-patch-ng/issues/51
    maybe(
        http_archive,
        name = "patch-ng",
        url = "https://github.com/conan-io/python-patch-ng/archive/refs/tags/1.19.0.tar.gz",
        strip_prefix = "python-patch-ng-1.19.0",
        build_file_content = """
load("@rules_python//python:defs.bzl", "py_library")
py_library(
    name = "patch-ng",
    srcs = [":patch_ng.py"],
    imports = ["."],
    visibility = ["//visibility:public"],
)
    """,
        integrity = "sha256-Gb4jkHC5YiT/XZXeW+PAEGEDYc3JKvhjRYj4yYaG7wg=",
    )
