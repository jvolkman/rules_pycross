"""Module extension for registering Starlark translator test repos."""

load("@toml.bzl//toml:toml.bzl", "decode")

# buildifier: disable=bzl-visibility
load("//pycross/private:pdm_lock_model.bzl", "translate_pdm")

# buildifier: disable=bzl-visibility
load("//pycross/private:poetry_lock_model.bzl", "translate_poetry")

# buildifier: disable=bzl-visibility
load("//pycross/private:pylock_lock_model.bzl", "translate_pylock")

# buildifier: disable=bzl-visibility
load("//pycross/private:uv_lock_model.bzl", "translate_uv")

def _starlark_translator_repo_impl(rctx):
    """Repository rule that runs a Starlark translator and outputs raw_lock.json."""
    lock_model = json.decode(rctx.attr.lock_model_json)
    lock_model_struct = struct(**lock_model)
    translator = rctx.attr.translator

    lock_content = rctx.read(rctx.path(rctx.attr.lock_file))
    lock_dict = decode(lock_content)

    project_dict = None
    if rctx.attr.project_file:
        project_content = rctx.read(rctx.path(rctx.attr.project_file))
        project_dict = decode(project_content)

    if translator == "pdm":
        raw_lock_data = translate_pdm(project_dict, lock_dict, lock_model_struct)
    elif translator == "poetry":
        raw_lock_data = translate_poetry(project_dict, lock_dict, lock_model_struct)
    elif translator == "uv":
        raw_lock_data = translate_uv(project_dict, lock_dict, lock_model_struct)
    elif translator == "pylock":
        raw_lock_data = translate_pylock(lock_dict, project_dict, lock_model_struct)
    else:
        fail("Unknown translator: " + translator)

    rctx.file("raw_lock.json", json.encode_indent(raw_lock_data, indent = "  ") + "\n")
    rctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

exports_files(["raw_lock.json"])
""")

starlark_translator_repo = repository_rule(
    implementation = _starlark_translator_repo_impl,
    attrs = {
        "translator": attr.string(mandatory = True),
        "lock_file": attr.label(mandatory = True, allow_single_file = True),
        "project_file": attr.label(allow_single_file = True),
        "lock_model_json": attr.string(mandatory = True),
    },
)

_translator_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True, doc = "Name for the generated repo."),
        "translator": attr.string(mandatory = True, doc = "One of pdm, poetry, uv, pylock."),
        "lock_file": attr.label(mandatory = True, allow_single_file = True),
        "project_file": attr.label(allow_single_file = True),
        "lock_model_json": attr.string(mandatory = True, doc = "JSON-encoded lock model attrs."),
    },
)

def _translator_test_repos_impl(module_ctx):
    for mod in module_ctx.modules:
        for tag in mod.tags.translator:
            starlark_translator_repo(
                name = tag.name,
                translator = tag.translator,
                lock_file = tag.lock_file,
                project_file = tag.project_file,
                lock_model_json = tag.lock_model_json,
            )

translator_test_repos = module_extension(
    implementation = _translator_test_repos_impl,
    tag_classes = {
        "translator": _translator_tag,
    },
)
