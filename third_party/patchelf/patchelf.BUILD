package(default_visibility = ["//visibility:public"])

cc_binary(
    name = "patchelf",
    srcs = [
        "src/patchelf.cc",
        "src/patchelf.h",
        "src/elf.h",
    ],
    copts = [
        "-std=c++17",
    ],
    local_defines = [
        'PACKAGE_STRING="\\"patchelf 0.17.0\\""',
    ],
)
