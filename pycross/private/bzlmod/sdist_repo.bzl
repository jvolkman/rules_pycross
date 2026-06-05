"""Repository rule for auto-generating a BUILD file for an sdist package.

The common logic is factored into _sdist_repo_common() so it can be called before hooks are invoked.
"""

load("@pycross_backends//:sdist_dispatch.bzl", "SDIST_HOOKS")
load("//pycross/private:internal_repo.bzl", "exec_internal_tool")
load("//pycross/private:util.bzl", "extract_pep508_name")

def _render_build_file(rctx, macro_attrs, backend_macro, extra_build_snippets = None):
    """Render the BUILD.bazel file for an sdist repo.

    Args:
        rctx: The repository context.
        macro_attrs: Dict of macro attribute name -> Starlark literal string.
        backend_macro: The backend macro name (e.g. 'meson_build').
        extra_build_snippets: Optional list of raw BUILD file content strings.
    """
    attr_lines = []
    for key, val in sorted(macro_attrs.items()):
        attr_lines.append("    {} = {},".format(key, val))

    # Load the backend macro from this lock repo's _backend directory.
    # The macro inherits attrs from the underlying rule and pre-fills
    # tool_deps defaults from packages present in the lockfile.
    backend_bzl = "_backend:{}.bzl".format(backend_macro)

    build_content = """\nload("@{lock_repo}//{backend_bzl}", "{backend_macro}")

package(default_visibility = ["//visibility:public"])

{backend_macro}(
{attrs}
)
""".format(
        lock_repo = rctx.attr.lock_repo,
        backend_bzl = backend_bzl,
        backend_macro = backend_macro,
        attrs = "\n".join(attr_lines),
    )

    if extra_build_snippets:
        for snippet in extra_build_snippets:
            build_content += "\n" + snippet + "\n"

    rctx.file("BUILD.bazel", build_content)
    rctx.file("REPO.bazel", "")

def _sdist_repo_common(rctx):
    """Shared sdist repo logic: inspect metadata, resolve backend, apply override configs.

    Args:
        rctx: The repository context.

    Returns:
        A struct with:
            macro_attrs: Dict of macro attribute name -> Starlark literal string.
            backend_macro: The resolved backend macro name.
            applied_override_config: Dict of override config entries that matched the resolved backend.
            render: A function(macro_attrs, backend_macro, extra_build_snippets) to write BUILD.bazel.
    """
    backend_to_rule = rctx.attr.backend_to_rule
    default_backend = rctx.attr.default_backend
    known_backends = {v: True for v in backend_to_rule.values()}

    macro_attrs = {
        "name": "\"wheel\"",
        "sdist": "\"{}\"".format(rctx.attr.sdist),
        "deps": str(rctx.attr.deps),
    }

    if rctx.attr.build_backend:
        backend_macro = rctx.attr.build_backend

        # Validate that the explicitly-set backend is a registered rule name.
        if backend_macro not in known_backends and backend_macro != default_backend:
            fail("Unknown build backend: " + backend_macro +
                 ". Registered backends: " + ", ".join(sorted(known_backends.keys())))

        if rctx.attr.build_dependencies:
            build_deps = []
            for dep in rctx.attr.build_dependencies:
                dep_name = dep.split("@")[0]
                build_deps.append("@{}//:{}".format(rctx.attr.lock_repo, dep_name))
            macro_attrs["build_deps"] = str(build_deps)
    else:
        sdist_path = rctx.path(rctx.attr.sdist)
        output_json = rctx.path("build_metadata.json")

        # Run the Python inspector tool
        exec_internal_tool(
            rctx,
            Label("//pycross/private/tools:inspect_package.py"),
            [
                "--sdist",
                str(sdist_path),
                "--output",
                str(output_json),
                "--lock-json",
                str(rctx.path(rctx.attr.lock_json)),
            ],
        )

        metadata = json.decode(rctx.read(output_json))
        backend = metadata.get("build_backend", "")
        requires = metadata.get("build_requires", [])

        # Print any warnings from the package inspector
        for warning in metadata.get("warnings", []):
            # buildifier: disable=print
            print(warning)

        # Map pyproject backend to pycross rule name via the registry.
        # Falls back to the registered default backend.
        backend_macro = backend_to_rule.get(backend, default_backend)

        # Map build requires to targets in the hub repo
        build_deps = []
        required_build_packages = []
        for req in requires:
            req_name = extract_pep508_name(req)
            if req_name == "oldest-supported-numpy":
                req_name = "numpy"

            required_build_packages.append(req_name)

            # We only add it if it's in the known lock repo mapping.
            # (This will be passed in via rctx.attr.known_packages)
            if req_name in rctx.attr.known_packages:
                build_deps.append("@{}//:{}".format(rctx.attr.lock_repo, req_name))

        macro_attrs["build_deps"] = str(build_deps)

        # For pep517_build, pass the required package names for validation.
        if backend_macro == "pep517_build":
            macro_attrs["required_build_packages"] = str(required_build_packages)

    # Apply override backend configs: only use the entry matching the resolved backend.
    matching_config = {}
    if rctx.attr.override_backend_configs:
        all_configs = json.decode(rctx.attr.override_backend_configs)
        matching_config = all_configs.pop(backend_macro, {})
        for attr_name, json_val in sorted(matching_config.items()):
            decoded = json.decode(json_val)
            if type(decoded) == "string":
                macro_attrs[attr_name] = "\"{}\"".format(decoded)
            else:
                macro_attrs[attr_name] = str(decoded)
        if all_configs:
            # buildifier: disable=print
            print("WARNING: package '{}' has override configs for non-matching backends: {}".format(
                rctx.attr.sdist,
                ", ".join(sorted(all_configs.keys())),
            ))

    # Pass through pre_build_patches if specified.
    if rctx.attr.pre_build_patches:
        macro_attrs["pre_build_patches"] = str(rctx.attr.pre_build_patches)

    # Pass through site_hooks if specified.
    if rctx.attr.site_hooks:
        macro_attrs["site_hooks"] = str(rctx.attr.site_hooks)

    return struct(
        macro_attrs = macro_attrs,
        backend_macro = backend_macro,
        applied_override_config = matching_config,
        render = lambda macro_attrs, backend_macro, extra_build_snippets = None: _render_build_file(rctx, macro_attrs, backend_macro, extra_build_snippets),
    )

# -- Default (generic) sdist repo rule --

def _sdist_repo_impl(rctx):
    result = _sdist_repo_common(rctx)
    macro_attrs = dict(result.macro_attrs)
    backend_macro = result.backend_macro
    extra_build_snippets = None

    hook = SDIST_HOOKS.get(backend_macro)
    if hook:
        hook_result = hook(rctx, result)
        if hook_result:
            macro_attrs.update(hook_result.extra_attrs)
            extra_build_snippets = hook_result.extra_build_snippets

    result.render(macro_attrs, backend_macro, extra_build_snippets)

_SDIST_REPO_ATTRS = {
    "sdist": attr.label(mandatory = True),
    "deps": attr.string_list(doc = "Runtime dependencies from lock file."),
    "known_packages": attr.string_list(doc = "List of packages present in the lock file to filter build_requires."),
    "lock_json": attr.label(doc = "The lock.json file from the resolved lock repo.", mandatory = True),
    "lock_repo": attr.string(doc = "Name of the lock hub repo (e.g. 'uv').", mandatory = True),
    "build_backend": attr.string(doc = "The build backend to use."),
    "backend_to_rule": attr.string_dict(
        doc = "Registry mapping pyproject backend names to pycross rule names.",
    ),
    "default_backend": attr.string(
        doc = "The rule name used when no pyproject backend name matches.",
    ),
    "build_dependencies": attr.string_list(doc = "Overridden build-time dependencies."),
    "override_backend_configs": attr.string(
        doc = "JSON-encoded dict mapping backend rule names to their backend_attrs for this package. " +
              "Populated from backend override extensions. Only the entry matching the resolved backend is applied.",
    ),
    "pre_build_patches": attr.string_list(doc = "Patches to apply to the sdist source tree before building."),
    "site_hooks": attr.string_list(doc = "Python code snippets to execute on interpreter startup during builds."),
}

pycross_sdist_repo = repository_rule(
    implementation = _sdist_repo_impl,
    attrs = _SDIST_REPO_ATTRS,
)
