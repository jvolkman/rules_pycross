"""Shared helpers for creating backend override extensions.

Provides a factory function that eliminates boilerplate when defining
backend-specific override extensions (setuptools, meson, cmake, etc.).
Each backend extension follows the same pattern:
  1. Collect override tags into a JSON dict keyed by repo, then package name.
  2. Write that dict to a generated `@<backend>_overrides//:overrides.json` repo.
  3. The backends extension aggregates these into OVERRIDE_FILES for
     resolved_lock_repo to consume.
"""

load("@bazel_features//:features.bzl", "bazel_features")

def _overrides_repo_impl(rctx):
    """Simple repo that exports an overrides.json file."""
    rctx.file("overrides.json", rctx.attr.content)
    rctx.file("BUILD.bazel", 'exports_files(["overrides.json"])')

create_overrides_repo = repository_rule(
    implementation = _overrides_repo_impl,
    attrs = {"content": attr.string()},
)

def encode_build_system_attrs(tag):
    """Encode BUILD_SYSTEM_ATTRS from a tag into a backend_attrs dict.

    Args:
        tag: A module tag with optional copts, linkopts, native_deps,
            config_settings, and tool_deps attributes.

    Returns:
        A dict of JSON-encoded backend attribute values.
    """
    backend_attrs = {}

    copts = getattr(tag, "copts", None)
    if copts != None and copts:
        backend_attrs["copts"] = json.encode(copts)

    linkopts = getattr(tag, "linkopts", None)
    if linkopts != None and linkopts:
        backend_attrs["linkopts"] = json.encode(linkopts)

    native_deps = getattr(tag, "native_deps", None)
    if native_deps != None and native_deps:
        backend_attrs["native_deps"] = json.encode([str(dep) for dep in native_deps])

    config_settings = getattr(tag, "config_settings", None)
    if config_settings != None and config_settings:
        backend_attrs["config_settings"] = json.encode(config_settings)

    tool_deps = getattr(tag, "tool_deps", None)
    if tool_deps != None and tool_deps:
        backend_attrs["tool_deps"] = json.encode(tool_deps)

    build_env = getattr(tag, "build_env", None)
    if build_env != None and build_env:
        backend_attrs["build_env"] = json.encode(build_env)

    data = getattr(tag, "data", None)
    if data != None and data:
        backend_attrs["data"] = json.encode([str(dep) for dep in data])

    pre_build_hooks = getattr(tag, "pre_build_hooks", None)
    if pre_build_hooks != None and pre_build_hooks:
        backend_attrs["pre_build_hooks"] = json.encode([str(dep) for dep in pre_build_hooks])

    post_build_hooks = getattr(tag, "post_build_hooks", None)
    if post_build_hooks != None and post_build_hooks:
        backend_attrs["post_build_hooks"] = json.encode([str(dep) for dep in post_build_hooks])

    path_tools = getattr(tag, "path_tools", None)
    if path_tools != None and path_tools:
        backend_attrs["path_tools"] = json.encode([str(dep) for dep in path_tools])

    return backend_attrs

def make_override_extension(backend_name, build_backend, override_attrs):
    """Create a module extension for a build-system backend.

    Args:
        backend_name: Short name (e.g. "setuptools"). Used to name the
            generated overrides repo as `<backend_name>_overrides`.
        build_backend: The build backend identifier string stored in the
            override JSON (e.g. "setuptools_build").
        override_attrs: The tag attribute dict for the `override` tag class.

    Returns:
        A `module_extension` value.
    """

    def _impl(module_ctx):
        overrides = {}
        for module in module_ctx.modules:
            for tag in module.tags.override:
                backend_attrs = encode_build_system_attrs(tag)
                overrides.setdefault(tag.repo, {})[tag.name] = {
                    "build_backend": build_backend,
                    "backend_attrs": backend_attrs,
                }

        create_overrides_repo(
            name = backend_name + "_overrides",
            content = json.encode(overrides),
        )

        if bazel_features.external_deps.extension_metadata_has_reproducible:
            return module_ctx.extension_metadata(reproducible = True)
        return module_ctx.extension_metadata()

    return module_extension(
        implementation = _impl,
        tag_classes = dict(
            override = tag_class(
                doc = "Specify %s-specific package overrides." % backend_name,
                attrs = override_attrs,
            ),
        ),
    )
