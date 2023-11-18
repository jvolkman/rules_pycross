"""A module defining the third party dependency boringssl"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

# boringssl ships with Bazel support.
# https://github.com/google/boringssl/tree/master-with-bazel
def repositories():
    maybe(
        http_archive,
        name = "boringssl",
        url = "https://github.com/google/boringssl/archive/8f90ba425bdcd6a90b88baabfe58b1997f1893f3.tar.gz",
        sha256 = "03dd3080cb977989f76fde45b84f08ee7b5dfcf1c4d2c43b4560c6839ace19dc",
        strip_prefix = "boringssl-8f90ba425bdcd6a90b88baabfe58b1997f1893f3",
    )
