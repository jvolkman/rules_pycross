"""Dev test extension exposing a synthetic sdist with a misleading root layout."""

# buildifier: disable=bzl-visibility
load("@rules_pycross//pycross/private:sdist_repo.bzl", "pycross_sdist_repo")

# buildifier: disable=unused-variable
def _misleading_sdist_ext_impl(mctx):
    pycross_sdist_repo(
        name = "misleading_sdist",
        sdist = "//:misleading_pkg-0.1.0.tar.gz",
        pin_versions_json = "@uv//:pin_versions.json",
        thin_repo = "uv",
        lock_repo = "uv",
        known_packages = ["hatchling"],
        backend_to_rule = {"hatchling.build": "pep517_build"},
        default_backend = "pep517_build",
    )

misleading_sdist_ext = module_extension(
    implementation = _misleading_sdist_ext_impl,
)
