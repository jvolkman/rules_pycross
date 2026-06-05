"""Repository rule that generates a build backend registry.

This is created by the backends module extension from `backends.register` tags.
It produces:
  - `registry.bzl`: exports BACKEND_TO_RULE, DEFAULT_BACKEND, BACKEND_CONFIGS
  - `sdist_dispatch.bzl`: exports SDIST_HOOKS mapping backend names to sdist hook functions
"""

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

    # Emit sdist_dispatch.bzl with per-backend repo rule mappings.
    dispatch_lines = [
        '"""Generated sdist repo rule dispatch table. Do not edit."""',
        "",
    ]

    # Collect unique (bzl_file, symbol) pairs for backends that have custom sdist hooks.
    load_aliases = {}  # rule_name -> alias symbol
    for rule_name in sorted(rctx.attr.sdist_hook_bzl.keys()):
        bzl_file = rctx.attr.sdist_hook_bzl[rule_name]
        fn_name = rctx.attr.sdist_hook_fn.get(rule_name, rule_name.replace("_build", "_sdist_hook"))
        alias = "_sdist_hook_{}".format(rule_name)
        dispatch_lines.append('load("{}", {} = "{}")'.format(bzl_file, alias, fn_name))
        load_aliases[rule_name] = alias

    dispatch_lines.extend([
        "",
        "# Maps backend rule names to their sdist hook functions.",
        "SDIST_HOOKS = {",
    ])

    for rule_name in sorted(rctx.attr.backend_configs.keys()):
        if rule_name in load_aliases:
            dispatch_lines.append('    "{}": {},'.format(rule_name, load_aliases[rule_name]))

    dispatch_lines.extend([
        "}",
        "",
    ])

    rctx.file("sdist_dispatch.bzl", "\n".join(dispatch_lines))
    rctx.file("BUILD.bazel", """\
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

exports_files(["registry.bzl", "sdist_dispatch.bzl"])

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
    },
)
