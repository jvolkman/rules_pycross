"""Shared helpers for creating backend override extensions.

Provides a factory function that eliminates boilerplate when defining
backend-specific override extensions (setuptools, meson, cmake, etc.).
Each backend extension follows the same pattern:
  1. Collect override tags into a JSON dict keyed by "repo:package".
  2. Write that dict to a generated `@<backend>_overrides//:overrides.json` repo.
  3. The user wires it into lock_import via `override_source(file = ...)`.
"""

def _overrides_repo_impl(rctx):
    """Simple repo that exports an overrides.json file."""
    rctx.file("overrides.json", rctx.attr.content)
    rctx.file("BUILD.bazel", 'exports_files(["overrides.json"])')

_overrides_repo = repository_rule(
    implementation = _overrides_repo_impl,
    attrs = {"content": attr.string()},
)

def _encode_build_system_attrs(tag):
    """Encode BUILD_SYSTEM_ATTRS from a tag into a backend_attrs dict."""
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
                backend_attrs = _encode_build_system_attrs(tag)
                key = tag.repo + ":" + tag.name
                overrides[key] = {
                    "build_backend": build_backend,
                    "backend_attrs": backend_attrs,
                }

        _overrides_repo(
            name = backend_name + "_overrides",
            content = json.encode(overrides),
        )

    return module_extension(
        implementation = _impl,
        tag_classes = dict(
            override = tag_class(
                doc = "Specify %s-specific package overrides." % backend_name,
                attrs = override_attrs,
            ),
        ),
    )
