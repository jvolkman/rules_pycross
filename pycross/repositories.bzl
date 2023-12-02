"""Declare runtime dependencies"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//pycross/private:internal.bzl", "create_internal_repo")
load("//pycross/private:pycross_deps.lock.bzl", pypi_all_repositories = "repositories")
load("//pycross/private:pycross_deps_core.lock.bzl", core_files = "FILES")

# The python_interpreter_target was previously used when pip_install was used for
# pycross' own dependencies. Leaving it here in case we need it in the future.
# buildifier: disable=unused-variable
def rules_pycross_dependencies(python_interpreter_target = None, python_interpreter = None):
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
