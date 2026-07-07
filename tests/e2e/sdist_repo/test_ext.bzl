"""Test extension."""

# buildifier: disable=bzl-visibility
load("@rules_pycross//pycross/private:sdist_repo.bzl", "pycross_sdist_repo")

def _dummy_lock_repo_impl(rctx):
    rctx.file("BUILD.bazel", "")
    rctx.file("_backend/BUILD.bazel", "")
    rctx.file("_backend/setuptools_build.bzl", "def setuptools_build(**kwargs): pass")
    rctx.file("_backend/pep517_build.bzl", "def pep517_build(**kwargs): pass")

dummy_lock_repo = repository_rule(implementation = _dummy_lock_repo_impl)

# buildifier: disable=unused-variable
def _test_ext_impl(mctx):
    dummy_lock_repo(name = "dummy_lock_repo")

    pycross_sdist_repo(
        name = "repo_basic",
        sdist = "//sdists:basic.tar.gz",
        pin_versions_json = "//:pin_versions.json",
        thin_repo = "dummy_lock_repo",
        lock_repo = "dummy_lock_repo",
        known_packages = ["setuptools", "hatchling"],
        backend_to_rule = {"setuptools.build_meta": "setuptools_build", "hatchling.build": "pep517_build"},
        default_backend = "setuptools_build",
    )

    pycross_sdist_repo(
        name = "repo_with_pyproject",
        sdist = "//sdists:with_pyproject.tar.gz",
        pin_versions_json = "//:pin_versions.json",
        thin_repo = "dummy_lock_repo",
        lock_repo = "dummy_lock_repo",
        known_packages = ["setuptools", "hatchling"],
        backend_to_rule = {"setuptools.build_meta": "setuptools_build", "hatchling.build": "pep517_build"},
        default_backend = "setuptools_build",
    )

    pycross_sdist_repo(
        name = "repo_with_setuptools",
        sdist = "//sdists:with_setuptools.tar.gz",
        pin_versions_json = "//:pin_versions.json",
        thin_repo = "dummy_lock_repo",
        lock_repo = "dummy_lock_repo",
        known_packages = ["setuptools", "hatchling"],
        backend_to_rule = {"setuptools.build_meta": "setuptools_build", "hatchling.build": "pep517_build"},
        default_backend = "setuptools_build",
    )

    pycross_sdist_repo(
        name = "repo_legacy",
        sdist = "//sdists:legacy.tar.gz",
        pin_versions_json = "//:pin_versions.json",
        thin_repo = "dummy_lock_repo",
        lock_repo = "dummy_lock_repo",
        known_packages = ["setuptools", "hatchling"],
        backend_to_rule = {"setuptools.build_meta": "setuptools_build", "hatchling.build": "pep517_build"},
        default_backend = "setuptools_build",
    )

test_ext = module_extension(implementation = _test_ext_impl)
