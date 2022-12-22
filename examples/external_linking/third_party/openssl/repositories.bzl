"""A module defining the third party dependency OpenSSL"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def repositories():
    maybe(
        http_archive,
        name = "openssl",
        build_file = Label("//third_party/openssl:openssl.BUILD"),
        sha256 = "83049d042a260e696f62406ac5c08bf706fd84383f945cf21bd61e9ed95c396e",
        strip_prefix = "openssl-3.0.7",
        urls = [
            "https://mirror.bazel.build/www.openssl.org/source/openssl-3.0.7.tar.gz",
            "https://www.openssl.org/source/openssl-3.0.7.tar.gz",
        ],
        patches = [
            "//patches:openssl-mkbuildinf.patch",
        ],
        patch_args = ["-p1"],
    )

    maybe(
        http_archive,
        name = "rules_perl",
        sha256 = "391edb08802860ba733d402c6376cfe1002b598b90d2240d9d302ecce2289a64",
        strip_prefix = "rules_perl-7f10dada09fcba1dc79a6a91da2facc25e72bd7d",
        urls = [
            "https://github.com/bazelbuild/rules_perl/archive/7f10dada09fcba1dc79a6a91da2facc25e72bd7d.tar.gz",
        ],
    )
