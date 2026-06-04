"""Setuptools overrides extension."""

load("//pycross/private/bzlmod:tag_attrs.bzl", "SETUPTOOLS_OVERRIDE_ATTRS")

def _overrides_repo_impl(rctx):
    rctx.file("overrides.json", rctx.attr.content)
    rctx.file("BUILD.bazel", 'exports_files(["overrides.json"])')

_overrides_repo = repository_rule(
    implementation = _overrides_repo_impl,
    attrs = {"content": attr.string()},
)

def _setuptools_overrides_impl(module_ctx):
    overrides = {}
    for module in module_ctx.modules:
        for tag in module.tags.override:
            backend_attrs = {}
            if tag.copts:
                backend_attrs["copts"] = json.encode(tag.copts)
            if tag.linkopts:
                backend_attrs["linkopts"] = json.encode(tag.linkopts)
            if tag.native_deps:
                backend_attrs["native_deps"] = json.encode([str(dep) for dep in tag.native_deps])
            if tag.config_settings:
                backend_attrs["config_settings"] = json.encode(tag.config_settings)
            if tag.tool_deps:
                backend_attrs["tool_deps"] = json.encode(tag.tool_deps)

            key = tag.repo + ":" + tag.name
            overrides[key] = {
                "build_backend": "setuptools_build",
                "backend_attrs": backend_attrs,
            }

    _overrides_repo(
        name = "setuptools_overrides",
        content = json.encode(overrides),
    )

setuptools = module_extension(
    implementation = _setuptools_overrides_impl,
    tag_classes = dict(
        override = tag_class(
            doc = "Specify setuptools-specific package overrides.",
            attrs = SETUPTOOLS_OVERRIDE_ATTRS,
        ),
    ),
)
