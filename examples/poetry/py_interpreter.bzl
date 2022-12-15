OSX_OS_NAME = "mac os x"
LINUX_OS_NAME = "linux"

def _python_build_standalone_interpreter_impl(repository_ctx):
    os_name = repository_ctx.os.name.lower()

    # TODO(Jonathon): This can't differentiate ARM (Mac M1) from old x86.
    # TODO(Jonathon: Support Windows.
    if os_name == OSX_OS_NAME:
        url = "https://github.com/indygreg/python-build-standalone/releases/download/20200822/cpython-3.7.9-x86_64-apple-darwin-pgo-20200823T0123.tar.zst"
        integrity_shasum = "e50a03a0db1f49f4d8521fa531f67390652457c83ca9c20b1dcbaf2e36770b1b"
    elif os_name == LINUX_OS_NAME:
        url = "https://github.com/indygreg/python-build-standalone/releases/download/20200822/cpython-3.7.9-x86_64-unknown-linux-gnu-pgo-20200823T0036.tar.zst"
        integrity_shasum = "c6d6256d13e929e77e7ee6e53470fe63ad19d173fee6d56bb1b2dbda67081543"
    else:
        fail("OS '{}' is not supported.".format(os_name))

    # TODO(Jonathon): Just use download_and_extract when it supports zstd. https://github.com/bazelbuild/bazel/pull/11968
    repository_ctx.download(
        url = [url],
        sha256 = integrity_shasum,
        output = "python.tar.zst",
    )

    # TODO(Jonathon): NOT HERMETIC. Need to install 'unzstd' in rule and use it.
    unzstd_bin_path = repository_ctx.which("unzstd")
    if unzstd_bin_path == None:
        if os_name == OSX_OS_NAME:
            fail("Require zstd to unpack download, try brew install zstd, and run again.")
        else:
            fail("On OSX and Linux this Python toolchain requires that the zstd and unzstd exes are available on the $PATH, but it was not found.")

    # NOTE: *Not Hermetic*. Need to install 'unzstd' in rule and use it.

    exec_result = repository_ctx.execute([
        "tar",
        "--extract",
        "--strip-components=2",
        "--use-compress-program={unzstd}".format(unzstd = unzstd_bin_path),
        "--file=python.tar.zst",
    ])

    if exec_result.return_code:
        fail(exec_result.stderr)

    repository_ctx.delete("python.tar.zst")

    repository_ctx.execute(["chmod", "-R", "ugo-w", "lib"])

    BUILD_FILE_CONTENT = """
filegroup(
    name = "files",
    srcs = glob(
        include = [
            "*.exe",
            "*.dll",
            "bin/**",
            "DLLs/**",
            "extensions/**",
            "include/**",
            "lib/**",
            "libs/**",
            "Scripts/**",
            "share/**",
        ],
        exclude = [
            "**/* *", # Bazel does not support spaces in file names.
        ],
    ),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "interpreter",
    srcs = ["bin/python3.7m"],
    visibility = ["//visibility:public"],
)
"""

    repository_ctx.file("BUILD.bazel", BUILD_FILE_CONTENT)
    return None

python_build_standalone_interpreter = repository_rule(
    implementation = _python_build_standalone_interpreter_impl,
    attrs = {},
)
