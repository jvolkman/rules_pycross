"""Repository rule that generates a build backend registry.

This is created by the pycross module extension from `register_backend` tags.
It produces a `registry.bzl` file that exports:
  - BACKEND_TO_RULE: dict mapping pyproject backend names to pycross rule names
  - DEFAULT_BACKEND: the rule name used when no pyproject backend matches
  - BACKEND_CONFIGS: dict mapping pycross rule names to their config
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
    ])

    rctx.file("registry.bzl", "\n".join(lines))
    rctx.file("BUILD.bazel", 'exports_files(["registry.bzl"])\n')
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
    },
)
