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

        # At configure time, postgres tries to compile, link, and run a simple program
        # using the rest of the built-up linker flags. This results in a program being
        # successfully linked to libssl.1.1.dylib, but failing to find it at runtime.
        # No amount of DYLD_LIBRARY_PATH manipulation has helped, presumably due to
        # System Integrity Protection sanitizing that var [1].
        #
        # So instead we exploit the fact that, when cross compiling, configure doesn't
        # try to execute the test program for obvious reasons. The patch commands below
        # force configure to think it's always in cross compile mode.
        #
        # 1: https://briandfoy.github.io/macos-s-system-integrity-protection-sanitizes-your-environment/
        patch_cmds = [
            "sed -i.bak 's/cross_compiling=no/cross_compiling=yes/g' configure",
            "sed -i.bak 's/cross_compiling=maybe/cross_compiling=yes/g' configure",
            "rm configure.bak",
        ]
    )
