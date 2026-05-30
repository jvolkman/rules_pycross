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

config_setting(
    name = "linux_arm64",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:arm64",
    ],
)

filegroup(
    name = "all_srcs",
    srcs = glob(["**/*"]),
)

configure_make(
    name = "postgresql",
    configure_options = [
        "--without-readline",
        "--without-perl",
        "--with-ssl=openssl",
        "--without-icu",
        "--prefix=/usr",
        "--exec-prefix=/usr",
    ] + select({
        ":macos_x86_64": ["--host=amd64-apple-darwin"],
        ":macos_arm64": ["--host=aarch64-apple-darwin"],
        ":linux_x86_64": ["--host=amd64-linux"],
        ":linux_arm64": ["--host=aarch64-linux"],
    }),
    copts = [
        "-DOPENSSL_NO_FILENAMES",
        "-O2",
        "-Wl,-S",
    ],
    env = {
        "ZIC": "/usr/sbin/zic",
        # Alignment cache variables for cross-compilation. AC_CHECK_ALIGNOF
        # uses AC_RUN_IFELSE which can't execute target binaries on the host,
        # causing it to fall back to 0 (invalid, not a power of 2).
        "ac_cv_alignof_short": "2",
        "ac_cv_alignof_int": "4",
        "ac_cv_alignof_long": "8",
        "ac_cv_alignof_int64_t": "8",
        "ac_cv_alignof_double": "8",
        "ac_cv_alignof_PG_INT128_TYPE": "16",
    },
    lib_source = ":all_srcs",
    out_bin_dir = "usr/bin",
    out_binaries = [
        "pg_config",
    ],
    out_include_dir = "usr/include",
    out_lib_dir = "usr/lib",
    out_shared_libs = select({
        "@platforms//os:macos": [
            "libpq.dylib",
            "libpq.5.dylib",
        ],
        "@platforms//os:linux": [
            "libpq.so",
            "libpq.so.5",
        ],
    }),
    targets = [
        "-C src/bin/pg_config install DESTDIR=$BUILD_TMPDIR/$INSTALL_PREFIX",
        "-C src/include install DESTDIR=$BUILD_TMPDIR/$INSTALL_PREFIX",
        "-C src/interfaces/libpq install DESTDIR=$BUILD_TMPDIR/$INSTALL_PREFIX",
    ],
    deps = [
        "@//third_party/openssl",
        "@//third_party/zlib",
    ],
)
