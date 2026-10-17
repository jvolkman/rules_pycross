"""Shared helpers for creating backend override extensions.

Provides a factory function that eliminates boilerplate when defining
backend-specific override extensions (setuptools, meson, cmake, etc.).
Each backend extension follows the same pattern:
  1. Collect override tags into a JSON dict keyed by workspace, then package name.
  2. Write that dict to a generated `@<backend>_overrides//:overrides.json` repo.
  3. The backends extension aggregates these into OVERRIDE_FILES for
     lock_repo_creation to consume.
"""

load("@bazel_features//:features.bzl", "bazel_features")

def merge_backend_overrides(scope, pkg_name, version = ""):
    """Merge wildcard, package-specific, and version-specific backend overrides.

    Entries are layered from least to most specific: "*", then "name", then
    "name@version". Each layer overrides individual fields of the previous ones.
    Fields are replaced, not merged (i.e. if both wildcard and specific set copts,
    the more specific value wins entirely).

    Args:
        scope: dict mapping override keys ("*", "name", or "name@version") to
            {backend_name: backend_attrs} dicts.
        pkg_name: the normalized package name to look up.
        version: optional package version; enables "name@version" entries.

    Returns:
        A merged dict of {backend_name: backend_attrs}, or empty dict.
    """
    result = {}
    keys = ["*", pkg_name]
    if version:
        keys.append("{}@{}".format(pkg_name, version))

    for key in keys:
        for b_name, b_attrs in scope.get(key, {}).items():
            result.setdefault(b_name, {}).update(b_attrs)

    return result

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

    for attr_name in ("copts", "linkopts", "config_settings", "build_env", "repair_exclude_globs"):
        val = getattr(tag, attr_name, None)
        if val:
            backend_attrs[attr_name] = json.encode(val)

    for attr_name in ("native_deps", "data", "pre_build_hooks", "post_build_hooks", "path_tools"):
        val = getattr(tag, attr_name, None)
        if val:
            backend_attrs[attr_name] = json.encode([str(dep) for dep in val])

    tool_deps = getattr(tag, "tool_deps", None)
    if tool_deps:
        backend_attrs["tool_deps"] = json.encode({name: str(label) for name, label in tool_deps.items()})

    cargo_lock = getattr(tag, "cargo_lock", None)
    if cargo_lock:
        backend_attrs["cargo_lock"] = json.encode(str(cargo_lock))

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
                key = tag.workspace
                overrides.setdefault(key, {})[tag.name] = {
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
                doc = "Specify %s-specific package overrides." % backend_name.replace("_", "-"),
                attrs = override_attrs,
            ),
        ),
    )
