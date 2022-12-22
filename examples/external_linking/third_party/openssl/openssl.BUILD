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
    args = ["-j8"],  # Useful for iteration; may not be good in a prod build
    configure_command = "Configure",
    configure_in_place = True,
    configure_options = CONFIGURE_OPTIONS,
    copts = [
        "-DOPENSSL_NO_APPLE_CRYPTO_RANDOM",
        "-DOPENSSL_NO_FILENAMES",
        "-O2",
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
    out_lib_dir = select({
        "@platforms//os:linux": "usr/lib64",
        "//conditions:default": "usr/lib",
    }),
    out_include_dir = "usr/include",
    out_binaries = ["openssl"],
    # Note that for Linux builds, libssl must come before libcrypto on the linker command-line.
    # As such, libssl must be listed before libcrypto
    out_shared_libs = select({
        "@platforms//os:macos": [
            "libssl.3.dylib",
            "libcrypto.3.dylib",
        ],
        "//conditions:default": [
            "libssl.so.3",
            "libcrypto.so.3",
        ],
    }),
    targets = MAKE_TARGETS,
    toolchains = ["@rules_perl//:current_toolchain"],
)
