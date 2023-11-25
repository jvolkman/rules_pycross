"""Declare runtime dependencies"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//pycross/private:lock_repo.bzl", "pycross_lock_repo")
load("//pycross/private:pycross_deps_lock.bzl", pip_repositories = "repositories")

# The python_interpreter_target was previously used when pip_install was used for
# pycross' own dependencies. Leaving it here in case we need it in the future.
# buildifier: disable=unused-variable
def rules_pycross_dependencies(python_interpreter_target = None):
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

    maybe(
        http_file,
        name = "rules_pycross_installer",
        urls = [
            "https://files.pythonhosted.org/packages/e5/ca/1172b6638d52f2d6caa2dd262ec4c811ba59eee96d54a7701930726bce18/installer-0.7.0-py3-none-any.whl",
        ],
        sha256 = "05d1933f0a5ba7d8d6296bb6d5018e7c94fa473ceb10cf198a92ccea19c27b53",
        downloaded_file_path = "installer-0.7.0-py3-none-any.whl",
    )

    maybe(
        pycross_lock_repo,
        name = "rules_pycross_deps",
        lock_file = "@jvolkman_rules_pycross//pycross/private:pycross_deps_lock.bzl",
    )
    pip_repositories()
