"""Implementation of the resolved_lock_repo rule.

`resolved_lock_repo` takes an importable third-party lock (PDM or Poetry) and:
1. runs that lock type's translator to generate a "raw" lock structure.
2. runs `raw_lock_resolver` to generate a resolved lock structure.

The output of #2 is stored as `//:lock.json` and consumed by `package_repo`.
"""

load(":lock_attrs.bzl", "RESOLVE_ATTRS")
load(":lock_resolver.bzl", "resolve")
load(":pdm_lock_model.bzl", "repo_create_pdm_model", PDM_TRANSLATOR_TOOL = "TRANSLATOR_TOOL")
load(":poetry_lock_model.bzl", "repo_create_poetry_model", POETRY_TRANSLATOR_TOOL = "TRANSLATOR_TOOL")
load(":pylock_lock_model.bzl", "repo_create_pylock_model", PYLOCK_TRANSLATOR_TOOL = "TRANSLATOR_TOOL")
load(":uv_lock_model.bzl", "repo_create_uv_model", UV_TRANSLATOR_TOOL = "TRANSLATOR_TOOL")

_ROOT_BUILD = """\
package(default_visibility = ["//visibility:public"])

exports_files([
    "raw_lock.json",
    "lock.json",
])
"""

def _generate_lock_model_file(rctx):
    lock_model = json.decode(rctx.attr.lock_model)

    if type(lock_model) == "dict":
        lock_model = struct(**lock_model)

    project_file = Label(lock_model.project_file) if getattr(lock_model, "project_file", "") else None
    lock_file = Label(lock_model.lock_file)

    if project_file and hasattr(rctx, "watch"):
        rctx.watch(project_file)

    if lock_file and hasattr(rctx, "watch"):
        rctx.watch(lock_file)

    if lock_model.model_type == "pdm":
        repo_create_pdm_model(rctx, project_file, lock_file, lock_model, "raw_lock.json")
    elif lock_model.model_type == "poetry":
        repo_create_poetry_model(rctx, project_file, lock_file, lock_model, "raw_lock.json")
    elif lock_model.model_type == "uv":
        repo_create_uv_model(rctx, project_file, lock_file, lock_model, "raw_lock.json")
    elif lock_model.model_type == "pylock":
        repo_create_pylock_model(rctx, project_file, lock_file, lock_model, "raw_lock.json")
    else:
        fail("Invalid model type: " + lock_model.model_type)

def _generate_lock_file(rctx):
    raw_lock_data = json.decode(rctx.read("raw_lock.json"))
    local_wheels = {rctx.path(w).basename: str(w) for w in rctx.attr.local_wheels}
    annotations_data = {p: json.decode(a) for p, a in rctx.attr.annotations.items()}

    resolved_lock = resolve(
        lock_model_data = raw_lock_data,
        local_wheels = local_wheels,
        remote_wheels = rctx.attr.remote_wheels,
        always_include_sdist = rctx.attr.always_include_sdist,
        disallow_builds = rctx.attr.disallow_builds,
        annotations_data = annotations_data,
        default_build_dependencies_args = rctx.attr.default_build_dependencies,
        default_alias_single_version = rctx.attr.default_alias_single_version,
    )

    resolved_lock_dict = {
        "packages": resolved_lock.packages,
        "pins": resolved_lock.pins,
        "remote_files": resolved_lock.remote_files,
        "cycle_groups": resolved_lock.cycle_groups,
        "variants": resolved_lock.variants,
    }

    rctx.file("lock.json", json.encode(resolved_lock_dict))

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
            PDM_TRANSLATOR_TOOL,
            POETRY_TRANSLATOR_TOOL,
            UV_TRANSLATOR_TOOL,
            PYLOCK_TRANSLATOR_TOOL,
        ]),
    ) | RESOLVE_ATTRS,
)
