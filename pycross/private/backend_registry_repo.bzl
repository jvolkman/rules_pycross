"""Repository rule that generates a build backend registry.

This is created by the backends module extension from `backends.register` tags.
It produces:
  - `registry.bzl`: exports BACKEND_TO_RULE, DEFAULT_BACKEND, BACKEND_CONFIGS
  - `sdist_dispatch.bzl`: exports SDIST_HOOKS mapping backend names to sdist hook functions
  - `package_repo_dispatch.bzl`: exports PACKAGE_REPO_HOOKS mapping backend names to package repo hook functions
"""

def _render_hook_dispatch(doc_title, hook_desc, var_name, bzl_map, fn_map, hook_suffix, rule_names):
    lines = [
        '"""Generated {} dispatch table. Do not edit."""'.format(doc_title),
        "",
    ]
    load_aliases = {}
    for rule_name in sorted(bzl_map.keys()):
        bzl_file = bzl_map[rule_name]
        fn_name = fn_map.get(rule_name, rule_name.replace("_build", hook_suffix))
        alias = "{}_{}".format(hook_suffix, rule_name)
        lines.append('load("{}", {} = "{}")'.format(bzl_file, alias, fn_name))
        load_aliases[rule_name] = alias

    lines.extend([
        "",
        "# Maps backend rule names to their {} functions.".format(hook_desc),
        "{} = {{".format(var_name),
    ])
    for rule_name in sorted(rule_names):
        if rule_name in load_aliases:
            lines.append('    "{}": {},'.format(rule_name, load_aliases[rule_name]))
    lines.extend([
        "}",
        "",
    ])
    return "\n".join(lines)

def _backend_registry_repo_impl(rctx):
    # Emit registry.bzl with the three constants.
    lines = [
        '"""Generated build backend registry. Do not edit."""',
        "",
        "# Maps pyproject.toml build-system.build-backend values to pycross rule names.",
        "BACKEND_TO_RULE = {",
    ]
    for pyproject_name, rule_name in sorted(rctx.attr.backend_to_rule.items()):
        lines.append('    "{}": "{}",'.format(pyproject_name, rule_name))
    lines.extend([
        "}",
        "",
        "# The rule name used when no pyproject backend name matches.",
        'DEFAULT_BACKEND = "{}"'.format(rctx.attr.default_backend),
        "",
        "# Maps pycross rule names to their configuration.",
        "# Each value is a struct-like dict with 'rule_bzl' and 'tool_packages'.",
        "BACKEND_CONFIGS = {",
    ])
    for name in sorted(rctx.attr.backend_configs.keys()):
        config = json.decode(rctx.attr.backend_configs[name])
        lines.append('    "{}": {{'.format(name))
        lines.append('        "rule_bzl": "{}",'.format(config["rule_bzl"]))
        lines.append('        "tool_packages": {},'.format(config["tool_packages"]))
        lines.append("    },")
    lines.extend([
        "}",
        "",
        "OVERRIDE_FILES = [",
    ])
    for f in rctx.attr.override_files:
        lines.append('    Label("{}"),'.format(f))
    lines.extend([
        "]",
        "",
    ])

    rctx.file("registry.bzl", "\n".join(lines))

    rctx.file("sdist_dispatch.bzl", _render_hook_dispatch(
        "sdist repo rule",
        "sdist hook",
        "SDIST_HOOKS",
        rctx.attr.sdist_hook_bzl,
        rctx.attr.sdist_hook_fn,
        "_sdist_hook",
        rctx.attr.backend_configs.keys(),
    ))
    rctx.file("package_repo_dispatch.bzl", _render_hook_dispatch(
        "package repo hook",
        "package repo hook",
        "PACKAGE_REPO_HOOKS",
        rctx.attr.package_repo_hook_bzl,
        rctx.attr.package_repo_hook_fn,
        "_package_repo_hook",
        rctx.attr.backend_configs.keys(),
    ))
    rctx.file("BUILD.bazel", """\
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

exports_files(["registry.bzl", "sdist_dispatch.bzl", "package_repo_dispatch.bzl"])

bzl_library(
    name = "registry",
    srcs = ["registry.bzl"],
    visibility = ["//visibility:public"],
)

bzl_library(
    name = "sdist_dispatch",
    srcs = ["sdist_dispatch.bzl"],
    visibility = ["//visibility:public"],
)

bzl_library(
    name = "package_repo_dispatch",
    srcs = ["package_repo_dispatch.bzl"],
    visibility = ["//visibility:public"],
)
""")
    rctx.file("REPO.bazel", "")

backend_registry_repo = repository_rule(
    implementation = _backend_registry_repo_impl,
    attrs = {
        "backend_to_rule": attr.string_dict(
            doc = "Maps pyproject.toml build-system.build-backend values to pycross rule names.",
        ),
        "default_backend": attr.string(
            doc = "The rule name used when no pyproject backend name matches.",
        ),
        "backend_configs": attr.string_dict(
            doc = "Maps pycross rule names to JSON-encoded config dicts with 'rule_bzl' and 'tool_packages'.",
        ),
        "sdist_hook_bzl": attr.string_dict(
            doc = "Maps backend rule names to their custom sdist hook .bzl file labels.",
        ),
        "sdist_hook_fn": attr.string_dict(
            doc = "Maps backend rule names to the function name in the sdist hook .bzl file.",
        ),
        "override_files": attr.string_list(
            doc = "Labels of JSON files containing backend overrides.",
        ),
        "package_repo_hook_bzl": attr.string_dict(
            doc = "Maps backend rule names to their custom package repo hook .bzl file labels.",
        ),
        "package_repo_hook_fn": attr.string_dict(
            doc = "Maps backend rule names to the function name in the package repo hook .bzl file.",
        ),
    },
)
