"""Implementation of the resolved_lock_repo rule.

`resolved_lock_repo` takes an importable third-party lock (PDM or Poetry) and:
1. runs that lock type's translator to generate a "raw" lock structure.
2. runs `raw_lock_resolver` to generate a resolved lock structure.

The output of #2 is stored as `//:lock.json` and consumed by `package_repo`.
"""

load(":internal_repo.bzl", "exec_internal_tool")
load(":lock_attrs.bzl", "RESOLVE_ATTRS", "handle_resolve_attrs")
load(":pdm_lock_model.bzl", "repo_create_pdm_model", PDM_TRANSLATOR_TOOL = "TRANSLATOR_TOOL")
load(":poetry_lock_model.bzl", "repo_create_poetry_model", POETRY_TRANSLATOR_TOOL = "TRANSLATOR_TOOL")

_RESOLVER_TOOL = Label("//pycross/private/tools:raw_lock_resolver.py")

_ROOT_BUILD = """\
package(default_visibility = ["//visibility:public"])

exports_files([
    "raw_lock.json",
    "lock.json",
])
"""

def _generate_lock_model_file(rctx):
    model_params = json.decode(rctx.attr.lock_model)
    if model_params["model_type"] == "pdm":
        repo_create_pdm_model(rctx, model_params, "raw_lock.json")
    elif model_params["model_type"] == "poetry":
        repo_create_poetry_model(rctx, model_params, "raw_lock.json")
    else:
        fail("Invalid model type: " + model_params["model_type"])

def _generate_lock_file(rctx):
    environment_files_and_labels = [(rctx.path(t), str(t)) for t in rctx.attr.target_environments]
    wheel_names_and_labels = [(rctx.path(local_wheel).basename, local_wheel) for local_wheel in rctx.attr.local_wheels]
    args = handle_resolve_attrs(rctx.attr, environment_files_and_labels, wheel_names_and_labels)
    args.append("--always-include-sdist")
    args.extend(["--lock-model-file", "raw_lock.json"])
    args.extend(["--output", "lock.json"])

    exec_internal_tool(
        rctx,
        _RESOLVER_TOOL,
        args,
    )

def _resolved_lock_repo_impl(rctx):
    rctx.file(rctx.path("BUILD.bazel"), _ROOT_BUILD)
    rctx.report_progress("Generating raw_lock.json")
    _generate_lock_model_file(rctx)
    rctx.report_progress("Generating lock.json")
    _generate_lock_file(rctx)
    rctx.report_progress()

resolved_lock_repo = repository_rule(
    implementation = _resolved_lock_repo_impl,
    attrs = dict(
        lock_model = attr.string(
            mandatory = True,
        ),
        # For pre-pathifying labels
        _tools = attr.label_list(default = [
            _RESOLVER_TOOL,
            PDM_TRANSLATOR_TOOL,
            POETRY_TRANSLATOR_TOOL,
        ]),
    ) | RESOLVE_ATTRS,
)
