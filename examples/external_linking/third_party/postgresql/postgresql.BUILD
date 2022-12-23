load("@rules_foreign_cc//foreign_cc:defs.bzl", "configure_make")

package(default_visibility = ["//visibility:public"])

config_setting(
    name = "macos_x86_64",
    constraint_values = [
        "@platforms//os:macos",
        "@platforms//cpu:x86_64",
    ],
)

config_setting(
    name = "macos_arm64",
    constraint_values = [
        "@platforms//os:macos",
        "@platforms//cpu:arm64",
    ],
)

config_setting(
    name = "linux_x86_64",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)

filegroup(
    name = "all_srcs",
    srcs = glob(["**/*"]),
)

configure_make(
    name = "postgresql",
    lib_source = ":all_srcs",
    configure_options = [
        "--without-readline",
        "--without-perl",
        "--with-ssl=openssl",
        "--prefix=/usr",
        "--exec-prefix=/usr",
    ] + select({
        ":macos_x86_64": ["--host=amd64-apple-darwin"],
        ":macos_arm64": ["--host=aarch64-apple-darwin"],
        ":linux_x86_64": ["--host=amd64-linux"],
    }),
    copts = [
        "-DOPENSSL_NO_FILENAMES",
        "-O2",
    ],
    env = {
        "ZIC": "/usr/sbin/zic",
    },
    targets = [
        "-C src/bin install DESTDIR=$BUILD_TMPDIR/$INSTALL_PREFIX",
        "-C src/include install DESTDIR=$BUILD_TMPDIR/$INSTALL_PREFIX",
        "-C src/interfaces install DESTDIR=$BUILD_TMPDIR/$INSTALL_PREFIX",
    ],
    deps = [
        "@//third_party/openssl",
        "@//third_party/zlib",
    ],
    out_bin_dir = "usr/bin",
    out_lib_dir = "usr/lib",
    out_include_dir = "usr/include",
    out_shared_libs = select({
        "@platforms//os:macos": ["libpq.dylib"],
        "@platforms//os:linux": ["libpq.so"],
    }),
    out_binaries = [
        "pg_config",
    ],
)
