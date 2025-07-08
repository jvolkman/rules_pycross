"""Implementation of the pycross_lock_file_repo rule."""

def _pycross_lock_file_repo_impl(rctx):
    lock_file_label = rctx.attr.lock_file
    if hasattr(rctx, "watch"):
        rctx.watch(lock_file_label)

    rctx.file(rctx.path("requirements.bzl"), """\
load("{lock_file}", "PINS", "repositories")

def requirement(pkg):
    # Convert given name into normalized package name.
    # https://packaging.python.org/en/latest/specifications/name-normalization/#name-normalization
    pkg = pkg.replace("_", "-").replace(".", "-").lower()
    for i in range(len(pkg)):
        if "--" in pkg:
            pkg = pkg.replace("--", "-")
        else:
            break
    return "@{repo_name}//deps:%s" % pkg

all_requirements = ["@{repo_name}//deps:%s" % v for v in PINS.values()]

install_deps = repositories
""".format(lock_file = lock_file_label, repo_name = rctx.attr.name))

    rctx.file(
        rctx.path("BUILD.bazel"),
        """\
package(default_visibility = ["//visibility:public"])

exports_files(["requirements.bzl"])
""",
    )

    rctx.file(
        rctx.path("deps/BUILD.bazel"),
        """\
package(default_visibility = ["//visibility:public"])

load("{lock_file}", "targets")

targets()
""".format(lock_file = lock_file_label),
    )

pycross_lock_file_repo = repository_rule(
    implementation = _pycross_lock_file_repo_impl,
    attrs = {
        "lock_file": attr.label(
            doc = "The generated bzl lock file.",
            allow_single_file = [".bzl"],
            mandatory = True,
        ),
    },
)
