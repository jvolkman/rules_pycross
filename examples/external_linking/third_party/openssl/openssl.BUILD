"""An openssl build file based on a snippet found in the github issue:
https://github.com/bazelbuild/rules_foreign_cc/issues/337

Note that the $(PERL) "make variable" (https://docs.bazel.build/versions/main/be/make-variables.html)
is populated by the perl toolchain provided by rules_perl.
"""

load("@rules_foreign_cc//foreign_cc:defs.bzl", "configure_make")

package(default_visibility = ["//visibility:public"])

# Read https://wiki.openssl.org/index.php/Compilation_and_Installation

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
    srcs = glob(
        include = ["**"],
        exclude = ["*.bazel"],
    ),
)

CONFIGURE_OPTIONS = [
    "no-comp",
    "no-tests",
    "no-engine",
    "no-legacy",
    "--prefix=/usr",  # See comment below about DESTDIR
] + select({
    ":macos_x86_64": ["darwin64-x86_64-cc"],
    ":macos_arm64": ["darwin64-arm64-cc"],
    ":linux_x86_64": ["linux-x86_64-clang"],
    ":linux_arm64": ["linux-aarch64"],
})

LIB_NAME = "openssl"

MAKE_TARGETS = [
    "build_programs",
    # Use DESTDIR here to make install actually place things where
    # rules_foreign_cc expects. Any paths encoded in the binary will
    # be /usr-prefixed.
    "install_sw DESTDIR=$BUILD_TMPDIR/$INSTALL_PREFIX",
]

configure_make(
    name = "openssl",
    configure_command = "Configure",
    configure_in_place = True,
    configure_options = CONFIGURE_OPTIONS,
    copts = [
        "-DOPENSSL_NO_APPLE_CRYPTO_RANDOM",
        "-DOPENSSL_NO_FILENAMES",
        "-O2",
        "-Wl,-S",
    ],
    env = select({
        "@platforms//os:macos": {
            "PERL": "$$EXT_BUILD_ROOT$$/$(PERL)",
        },
        "//conditions:default": {
            "PERL": "$$EXT_BUILD_ROOT$$/$(PERL)",
        },
    }),
    lib_name = LIB_NAME,
    lib_source = ":all_srcs",
    out_bin_dir = "usr/bin",
    out_binaries = ["openssl"],
    out_include_dir = "usr/include",
    out_lib_dir = select({
        ":linux_x86_64": "usr/lib64",
        "//conditions:default": "usr/lib",
    }),
    # Note that for Linux builds, libssl must come before libcrypto on the linker command-line.
    # As such, libssl must be listed before libcrypto
    out_shared_libs = select({
        "@platforms//os:macos": [
            "libssl.dylib",
            "libssl.3.dylib",
            "libcrypto.dylib",
            "libcrypto.3.dylib",
        ],
        "//conditions:default": [
            "libssl.so",
            "libssl.so.3",
            "libcrypto.so",
            "libcrypto.so.3",
        ],
    }),
    targets = MAKE_TARGETS,
    toolchains = ["@rules_perl//:current_toolchain"],
)
