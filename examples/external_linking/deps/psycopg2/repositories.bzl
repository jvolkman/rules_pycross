"""Pre-built Postgresql repositories"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

VERSIONS = ["14"]

PLATFORM_CONSTRAINTS = {
    "linux_x86_64": ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    "darwin_x86_64": ["@platforms//os:macos", "@platforms//cpu:x86_64"],
    "darwin_arm64": ["@platforms//os:macos", "@platforms//cpu:arm64"],
}

_BUILD_FILE_CONTENT = """\
package(default_visibility = ["//visibility:public"])
filegroup(
    name = "files",
    srcs = glob(["**/*"]),
)
"""

def pg_repo(version, platform):
    return "postgresql%s_%s" % (version, platform)

def repositories():
    """Create postgresql repositories."""

    # See our own forked repo for the source of these archives.
    # https://github.com/cedarai/embedded-postgres-binaries

    http_archive(
        name = pg_repo("14", "linux_x86_64"),
        url = "https://github.com/cedarai/embedded-postgres-binaries/releases/download/14.2-with-tools-20220304/postgresql-14.2-linux-amd64.txz",
        build_file_content = _BUILD_FILE_CONTENT,
        sha256 = "58c6a2971fecec35e1155633abdba54100efffa68b5951fb2ba90de202e9a49f",
    )
    http_archive(
        name = pg_repo("14", "darwin_x86_64"),
        url = "https://github.com/cedarai/embedded-postgres-binaries/releases/download/14.2-with-tools-20220304/postgresql-14.2-darwin-amd64.txz",
        build_file_content = _BUILD_FILE_CONTENT,
        sha256 = "fd75be9794fe22a6b53380cea4e0b482eac3118b02909b6eab8313a480d19d16",
    )
    http_archive(
        name = pg_repo("14", "darwin_arm64"),
        url = "https://github.com/cedarai/embedded-postgres-binaries/releases/download/14.2-with-tools-20220304/postgresql-14.2-darwin-arm64.txz",
        build_file_content = _BUILD_FILE_CONTENT,
        sha256 = "096e0416e9e902e36109a5b962765c672002e0b55b52b72a6eaf2ed72acf686d",
    )
