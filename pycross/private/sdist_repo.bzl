"""Repository rule for auto-generating a BUILD file for an sdist package.

The common logic is factored into _sdist_repo_common() so it can be called before hooks are invoked.
"""

load("@pycross_backends//:sdist_dispatch.bzl", "SDIST_HOOKS")
load("//pycross/private:internal_repo.bzl", "exec_internal_tool")
load("//pycross/private:util.bzl", "extract_pep508_name", "key_name", "underscore_name")

def _parse_backend_spec(spec):
    """Parse a backend spec like 'setuptools.build_meta[setuptools-rust,wheel]'.

    Args:
        spec: The backend spec string.

    Returns:
        A tuple of (backend_name, required_packages) where required_packages
        is a list of PEP 503 normalized package names.
    """
    bracket = spec.find("[")
    if bracket == -1:
        return (spec, [])
    backend_name = spec[:bracket]
    requires_str = spec[bracket + 1:-1]  # strip [ and ]
    required = [r.strip() for r in requires_str.split(",") if r.strip()]
    return (backend_name, required)

def _resolve_backend(backend_to_rule, default_backend, pyproject_backend, build_requires_names):
    """Resolve the best-matching backend rule for a package.

    Entries in backend_to_rule may use bracket notation to specify required
    build-system.requires packages, e.g. 'setuptools.build_meta[setuptools-rust]'.
    When multiple entries match the same pyproject backend, the one with the
    most satisfied build_requires wins (most-specific match).

    Args:
        backend_to_rule: Dict mapping pyproject backend specs to rule names.
        default_backend: Fallback rule name when nothing matches.
        pyproject_backend: The build-backend value from pyproject.toml.
        build_requires_names: List of normalized package names from build-system.requires.

    Returns:
        The best-matching rule name.
    """
    best_rule = None
    best_specificity = -1

    for spec, rule_name in backend_to_rule.items():
        backend_name, required = _parse_backend_spec(spec)

        if backend_name != pyproject_backend:
            continue

        # Check if all required packages are present in build requires.
        all_satisfied = True
        for req in required:
            if req not in build_requires_names:
                all_satisfied = False
                break

        if not all_satisfied:
            continue

        specificity = len(required)
        if specificity > best_specificity:
            best_specificity = specificity
            best_rule = rule_name

    return best_rule if best_rule else default_backend

def _render_build_file(rctx, macro_attrs, backend_macro, site_paths, bin_paths, data_paths, include_paths, extra_build_snippets = None):
    """Render the BUILD.bazel file for an sdist repo.

    Args:
        rctx: The repository context.
        macro_attrs: Dict of macro attribute name -> Starlark literal string.
        backend_macro: The backend macro name (e.g. 'meson_build').
        site_paths: The site-packages paths for the package.
        bin_paths: The bin paths for the package.
        data_paths: The data paths for the package.
        include_paths: The include paths for the package.
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
load("@rules_pycross//pycross/private:wheel_library.bzl", "pycross_wheel_metadata")

package(default_visibility = ["//visibility:public"])

{backend_macro}(
{attrs}
)

pycross_wheel_metadata(
    name = "wheel",
    wheel = ":wheel_build",
    site_paths = {site_paths},
    bin_paths = {bin_paths},
    data_paths = {data_paths},
    include_paths = {include_paths},
)
""".format(
        thin_repo = rctx.attr.thin_repo,
        lock_repo = rctx.attr.lock_repo,
        backend_bzl = backend_bzl,
        backend_macro = backend_macro,
        attrs = "\n".join(attr_lines),
        site_paths = site_paths,
        bin_paths = bin_paths,
        data_paths = data_paths,
        include_paths = include_paths,
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
        "name": "\"wheel_build\"",
        "sdist": "\"{}\"".format(rctx.attr.sdist),
        "deps": str(rctx.attr.deps),
    }

    if rctx.attr.whldir_name:
        macro_attrs["whldir_name"] = "\"{}\"".format(rctx.attr.whldir_name)

    if rctx.attr.source_dir:
        macro_attrs["source_dir"] = "\"{}\"".format(rctx.attr.source_dir)

    if rctx.attr.build_backend:
        backend_macro = rctx.attr.build_backend

        # Validate that the explicitly-set backend is a registered rule name.
        if backend_macro not in known_backends and backend_macro != default_backend:
            fail("Unknown build backend: " + backend_macro +
                 ". Registered backends: " + ", ".join(sorted(known_backends.keys())))

        if rctx.attr.build_dependencies:
            build_deps = []
            for dep in rctx.attr.build_dependencies:
                dep_name = key_name(dep)
                build_deps.append("@{}//{}:pkg".format(rctx.attr.lock_repo, underscore_name(dep_name)))
            macro_attrs["build_deps"] = str(build_deps)

        site_paths = []
        bin_paths = []
        data_paths = []
        include_paths = []
        rctx.file("inspection.json", json.encode({"site_paths": [], "bin_paths": [], "data_paths": [], "include_paths": []}))
    else:
        sdist_path = rctx.path(rctx.attr.sdist)
        output_json = rctx.path("build_metadata.json")

        # Run the Python inspector tool
        inspect_args = [
            "--sdist",
            str(sdist_path),
            "--output",
            str(output_json),
            "--lock-json",
            str(rctx.path(rctx.attr.lock_json)),
        ]
        if rctx.attr.source_dir:
            inspect_args.extend(["--source-dir", rctx.attr.source_dir])

        exec_internal_tool(
            rctx,
            Label("//pycross/private/tools:inspect_package.py"),
            inspect_args,
        )

        metadata = json.decode(rctx.read(output_json))
        backend = metadata.get("build_backend", "")
        requires = metadata.get("build_requires", [])

        site_paths = metadata.get("site_paths", [])
        bin_paths = metadata.get("bin_paths", [])
        data_paths = metadata.get("data_paths", [])
        include_paths = metadata.get("include_paths", [])
        rctx.file("inspection.json", json.encode({
            "site_paths": site_paths,
            "bin_paths": bin_paths,
            "data_paths": data_paths,
            "include_paths": include_paths,
        }))

        # Print any warnings from the package inspector
        for warning in metadata.get("warnings", []):
            # buildifier: disable=print
            print(warning)

        # Map pyproject backend to pycross rule name via the registry.
        # Uses bracket-notation matching: entries like 'setuptools.build_meta[setuptools-rust]'
        # are preferred when the package's build-system.requires includes the bracketed deps.
        # Falls back to the registered default backend.
        build_requires_names = [extract_pep508_name(r) for r in requires]
        backend_macro = _resolve_backend(backend_to_rule, default_backend, backend, build_requires_names)

        # Map build requires to targets in the workspace repo
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
                build_deps.append("@{}//{}:pkg".format(rctx.attr.thin_repo, underscore_name(req_name)))

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
        site_paths = site_paths,
        bin_paths = bin_paths,
        data_paths = data_paths,
        include_paths = include_paths,
        applied_override_config = matching_config,
        render = lambda macro_attrs, backend_macro, extra_build_snippets = None: _render_build_file(rctx, macro_attrs, backend_macro, site_paths, bin_paths, data_paths, include_paths, extra_build_snippets),
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
    "lock_repo": attr.string(doc = "Name of the lock workspace repo (e.g. 'uv__pkgs').", mandatory = True),
    "build_backend": attr.string(doc = "The build backend to use."),
    "backend_to_rule": attr.string_dict(
        doc = "Registry mapping pyproject backend names to pycross rule names.",
    ),
    "thin_repo": attr.string(
        doc = "Name of the thin workspace repo.",
        mandatory = True,
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
    "whldir_name": attr.string(doc = "Name for the output .whldir TreeArtifact directory."),
    "source_dir": attr.string(doc = "Subdirectory within the sdist archive to build."),
}

pycross_sdist_repo = repository_rule(
    implementation = _sdist_repo_impl,
    attrs = _SDIST_REPO_ATTRS,
)
