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
load("@pypackaging.bzl", "pypackaging")

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
    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

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

    for attr_name, kind in (
        ("copts", "raw"),
        ("linkopts", "raw"),
        ("native_deps", "label_list"),
        ("config_settings", "raw"),
        ("tool_deps", "label_dict"),
        ("build_env", "raw"),
        ("data", "label_list"),
        ("pre_build_hooks", "label_list"),
        ("post_build_hooks", "label_list"),
        ("path_tools", "label_list"),
        ("repair_exclude_globs", "raw"),
        ("cargo_lock", "label"),
    ):
        val = getattr(tag, attr_name, None)
        if not val:
            continue
        if kind == "label_list":
            val = [str(dep) for dep in val]
        elif kind == "label_dict":
            val = {name: str(label) for name, label in val.items()}
        elif kind == "label":
            val = str(val)
        backend_attrs[attr_name] = json.encode(val)

    return backend_attrs

def _canonicalize_override_key(pkg_name):
    if pkg_name == "*":
        return pkg_name
    name, sep, version = pkg_name.partition("@")
    if not name or name == "*" or (sep and not version):
        # Preserve malformed input so lock_repo_creation's validation reports the original string.
        return pkg_name
    norm = pypackaging.utils.canonicalize_name(name)
    return "{}@{}".format(norm, version) if sep else norm

def _collect_module_overrides(modules, build_backend):
    """Collect override tags across Bzlmod modules with root-module-wins precedence.

    `module_ctx.modules` yields the root module first, so iterate in reverse
    order so the root module overrides transitive dependency modules. Duplicate
    overrides for the same (workspace, package) within a single module fail.
    """
    overrides = {}
    for module in reversed(modules):
        seen_in_module = {}
        for tag in module.tags.override:
            key = tag.workspace
            norm_name = _canonicalize_override_key(tag.name)
            dup_key = (key, norm_name)
            if dup_key in seen_in_module:
                fail("Duplicate {} override for package '{}' in workspace '{}' (module '{}')".format(
                    build_backend,
                    tag.name,
                    key,
                    module.name,
                ))
            seen_in_module[dup_key] = True
            backend_attrs = encode_build_system_attrs(tag)
            overrides.setdefault(key, {})[norm_name] = {
                "build_backend": build_backend,
                "backend_attrs": backend_attrs,
            }
    return overrides

collect_module_overrides_for_testing = _collect_module_overrides

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
        overrides = _collect_module_overrides(module_ctx.modules, build_backend)

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
