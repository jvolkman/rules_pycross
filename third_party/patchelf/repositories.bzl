"""A module defining the third party dependency patchelf"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def repositories():
    maybe(
        http_archive,
        name = "rules_pycross_third_party_patchelf",
        build_file = Label("@jvolkman_rules_pycross//third_party/patchelf:patchelf.BUILD"),
        # Note: update the PACKAGE_STRING define in patchelf.BUILD if changing versions.
        sha256 = "cfdd0591bfe17f50775695fbddf94d49ef03d5a603888667747ad105f2e9853a",
        strip_prefix = "patchelf-0.17.0",
        urls = [
            "https://github.com/NixOS/patchelf/archive/refs/tags/0.17.0.tar.gz",
        ],
    )
