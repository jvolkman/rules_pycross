"""A module defining the third party dependency openblas"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def repositories():
    maybe(
        http_archive,
        name = "openblas",
        urls = ["https://github.com/xianyi/OpenBLAS/releases/download/v0.3.23/OpenBLAS-0.3.23.tar.gz"],
        sha256 = "5d9491d07168a5d00116cdc068a40022c3455bf9293c7cb86a65b1054d7e5114",
        strip_prefix = "OpenBLAS-0.3.23",
        build_file = "//third_party:all_files.BUILD",
    )
