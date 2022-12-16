"""A module defining the third party dependency openblas"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def repositories():
    maybe(
        http_archive,
        name = "openblas",
        urls = ["https://github.com/xianyi/OpenBLAS/releases/download/v0.3.21/OpenBLAS-0.3.21.tar.gz"],
        sha256 = "f36ba3d7a60e7c8bcc54cd9aaa9b1223dd42eaf02c811791c37e8ca707c241ca",
        strip_prefix = "OpenBLAS-0.3.21",
        build_file = "//third_party:all_files.BUILD",
    )
