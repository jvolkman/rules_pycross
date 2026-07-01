"""A simple repo rule that writes JSON data to a file."""

def _json_file_repo_impl(rctx):
    rctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

exports_files(["data.json"])
""")
    rctx.file("data.json", rctx.attr.content)

json_file_repo = repository_rule(
    implementation = _json_file_repo_impl,
    attrs = {
        "content": attr.string(mandatory = True),
    },
)
