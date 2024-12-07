"""Download zstd"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def _zstd_impl(_):
    http_archive(
        name = "zstd",
        build_file = "//third_party/zstd:zstd.BUILD",
        sha256 = "9c4396cc829cfae319a6e2615202e82aad41372073482fce286fac78646d3ee4",
        strip_prefix = "zstd-1.5.5",
        urls = ["https://github.com/facebook/zstd/releases/download/v1.5.5/zstd-1.5.5.tar.gz"],
    )

zstd = module_extension(
    implementation = _zstd_impl,
)
