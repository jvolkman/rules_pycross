"""A module defining the third party dependency postgresql"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def repositories():
    maybe(
        http_archive,
        name = "postgresql",
        urls = ["https://ftp.postgresql.org/pub/source/v15.1/postgresql-15.1.tar.bz2"],
        sha256 = "64fdf23d734afad0dfe4077daca96ac51dcd697e68ae2d3d4ca6c45cb14e21ae",
        strip_prefix = "postgresql-15.1",
        build_file = "//third_party:all_files.BUILD",
    )
