"""Repository rule for auto-generating a BUILD file for an sdist package.

The common logic is factored into _sdist_repo_common() so it can be called before hooks are invoked.
"""

load("@pycross_backends//:registry.bzl", "BACKEND_CONFIGS", "BACKEND_TO_RULE", "DEFAULT_BACKEND")
load("@pycross_backends//:sdist_dispatch.bzl", "SDIST_HOOKS", "SDIST_HOOK_FILES")
load("@pypackaging.bzl", "pypackaging")
load("//pycross/private:internal_repo.bzl", "exec_internal_tool")
load("//pycross/private:util.bzl", "extract_pep508_name", "parse_package_key", "underscore_name")

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
    required = [extract_pep508_name(r.strip()) for r in requires_str.split(",") if r.strip()]
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

def _render_build_content(macro_attrs, backend_macro, rule_bzl, site_paths, bin_paths, extra_build_snippets = None):
    """Render the BUILD.bazel content string for an sdist repo.

    Args:
        macro_attrs: Dict of macro attribute name -> Starlark literal string.
        backend_macro: The backend rule/macro name (e.g. 'meson_build').
        rule_bzl: Label string of the .bzl file exporting `backend_macro`.
        site_paths: The site-packages paths for the package.
        bin_paths: The bin paths for the package.
        extra_build_snippets: Optional list of raw BUILD file content strings.

    Returns:
        The rendered BUILD.bazel file content.
    """
    attr_lines = []
    for key, val in sorted(macro_attrs.items()):
        attr_lines.append("    {} = {},".format(key, val))

    build_content = """\nload("{rule_bzl}", "{backend_macro}")
load("@rules_pycross//pycross/private:wheel_library.bzl", "pycross_wheel_metadata")

package(default_visibility = ["//visibility:public"])

exports_files(["inspection.json"])

{backend_macro}(
{attrs}
)

pycross_wheel_metadata(
    name = "wheel",
    wheel = ":wheel_build",
    site_paths = {site_paths},
    site_paths_exact = False,
    bin_paths = {bin_paths},
)
""".format(
        rule_bzl = rule_bzl,
        backend_macro = backend_macro,
        attrs = "\n".join(attr_lines),
        site_paths = site_paths,
        bin_paths = bin_paths,
    )

    if extra_build_snippets:
        for snippet in extra_build_snippets:
            build_content += "\n" + snippet + "\n"

    return build_content

def _render_build_file(rctx, macro_attrs, backend_macro, site_paths, bin_paths, extra_build_snippets = None, backend_configs = None):
    """Render the BUILD.bazel file for an sdist repo.

    Args:
        rctx: The repository context.
        macro_attrs: Dict of macro attribute name -> Starlark literal string.
        backend_macro: The backend macro name (e.g. 'meson_build').
        site_paths: The site-packages paths for the package.
        bin_paths: The bin paths for the package.
        extra_build_snippets: Optional list of raw BUILD file content strings.
        backend_configs: Optional backend config registry override (defaults to `BACKEND_CONFIGS`).
    """
    configs = backend_configs if backend_configs != None else BACKEND_CONFIGS
    config = configs.get(backend_macro)
    if config == None:
        fail("Unknown build backend: " + backend_macro +
             ". Registered backends: " + ", ".join(sorted(configs.keys())))

    build_content = _render_build_content(
        macro_attrs,
        backend_macro,
        config["rule_bzl"],
        site_paths,
        bin_paths,
        extra_build_snippets = extra_build_snippets,
    )

    rctx.file("BUILD.bazel", build_content)
    rctx.file("REPO.bazel", "")

def _validate_build_backend(attr, backend_to_rule = None, backend_configs = None, default_backend = None):
    if not attr.build_backend:
        return
    backend_to_rule = backend_to_rule if backend_to_rule != None else BACKEND_TO_RULE
    backend_configs = backend_configs if backend_configs != None else BACKEND_CONFIGS
    default_backend = default_backend if default_backend != None else DEFAULT_BACKEND

    known_backends = {name: True for name in backend_configs.keys()}
    for name in backend_to_rule.values():
        known_backends[name] = True
    if default_backend:
        known_backends[default_backend] = True
    if attr.build_backend not in known_backends:
        fail("Unknown build backend: " + attr.build_backend +
             ". Registered backends: " + ", ".join(sorted(known_backends.keys())))

# Tool package names that every build rule accepts in tool_deps, in addition to the
# backend's registered tool_packages.
_COMMON_TOOL_PACKAGES = ["repairwheel"]

def _merge_tool_deps_override(tool_deps, override, tool_packages, backend_macro, sdist):
    """Merge an override's tool_deps ({tool package name: label}) over the defaults in place.

    Build rules group tool_deps by PycrossPackageInfo.package_name, so keys that are not
    one of the backend's tool packages would be silently ignored; reject them instead.
    """
    allowed = {name: True for name in tool_packages + _COMMON_TOOL_PACKAGES}
    for name, label in sorted(override.items()):
        norm_name = extract_pep508_name(name)
        if norm_name not in allowed:
            fail("tool_deps override for '{}' has unknown tool package '{}'; {} accepts: {}".format(
                sdist,
                name,
                backend_macro,
                ", ".join(sorted(allowed.keys())),
            ))
        tool_deps[norm_name] = label

def _compute_sdist_build_config(attr, metadata, backend_to_rule = None, backend_configs = None, default_backend = None):
    """Compute macro attributes, resolved backend, and paths from sdist metadata and repo attrs.

    Args:
        attr: A struct or rctx.attr with sdist_repo attributes.
        metadata: Decoded dict from inspect_package.py.
        backend_to_rule: Optional pyproject-backend -> rule-name map (defaults to `BACKEND_TO_RULE`).
        backend_configs: Optional rule-name -> config dict map (defaults to `BACKEND_CONFIGS`).
        default_backend: Optional fallback rule name (defaults to `DEFAULT_BACKEND`).

    Returns:
        A struct with macro_attrs, backend_macro, site_paths, bin_paths,
        applied_override_config, non_matching_override_backends.
    """
    backend_to_rule = backend_to_rule if backend_to_rule != None else BACKEND_TO_RULE
    backend_configs = backend_configs if backend_configs != None else BACKEND_CONFIGS
    default_backend = default_backend if default_backend != None else DEFAULT_BACKEND

    _validate_build_backend(
        attr,
        backend_to_rule = backend_to_rule,
        backend_configs = backend_configs,
        default_backend = default_backend,
    )

    macro_attrs = {
        "name": repr("wheel_build"),
        "sdist": repr(str(attr.sdist)),
        "deps": str(attr.deps),
    }

    if attr.whldir_name:
        macro_attrs["whldir_name"] = repr(attr.whldir_name)

    if attr.source_dir:
        macro_attrs["source_dir"] = repr(attr.source_dir)

    backend = metadata.get("build_backend", "")
    requires = metadata.get("build_requires", [])

    site_paths = metadata.get("site_paths", [])
    bin_paths = metadata.get("bin_paths", [])

    parsed_requires = [(req, pypackaging.requirements.parse(req)) for req in requires]
    build_requires_names = [parsed.name for _, parsed in parsed_requires]
    if attr.build_backend:
        backend_macro = attr.build_backend
    else:
        # Map pyproject backend to pycross rule name via the registry.
        # Uses bracket-notation matching: entries like 'setuptools.build_meta[setuptools-rust]'
        # are preferred when the package's build-system.requires includes the bracketed deps.
        # Falls back to the registered default backend.
        backend_macro = _resolve_backend(backend_to_rule, default_backend, backend, build_requires_names)

    known_packages_set = {extract_pep508_name(k): True for k in attr.known_packages}

    # Map build requires and extra_build_tools to targets in the workspace repo
    build_deps = {}
    required_build_packages = {}
    versioned_build_requires = []
    for req, parsed_req in parsed_requires:
        req_name = parsed_req.name
        is_oldest_numpy = req_name == "oldest-supported-numpy"
        if is_oldest_numpy:
            req_name = "numpy"

        # Marker-gated entries may not apply to the target environment (and so
        # may be absent from the lock); don't require them or validate their
        # version specifiers unconditionally. Skip oldest-supported-numpy version
        # validation because it uses calendar versions (e.g. >=2022.1) that are
        # incompatible with numpy's own version scheme.
        if not parsed_req.marker:
            required_build_packages[req_name] = True
            if not is_oldest_numpy and parsed_req.specifier and parsed_req.specifier.specs:
                versioned_build_requires.append(req)

        # We only add it if it's in the known lock repo mapping.
        # (This will be passed in via rctx.attr.known_packages)
        if req_name in known_packages_set:
            build_deps["@{}//{}:pkg".format(attr.thin_repo, underscore_name(req_name))] = True

    for dep in attr.extra_build_tools:
        dep_name = parse_package_key(dep).name
        build_deps["@{}//{}:pkg".format(attr.thin_repo, underscore_name(dep_name))] = True

    macro_attrs["build_deps"] = str(sorted(build_deps.keys()))
    if versioned_build_requires:
        macro_attrs["build_requires"] = str(versioned_build_requires)

    # Populate tool_deps from the resolved backend's tool_packages that are present in the lock.
    # Keyed by normalized tool package name so that override tool_deps can replace single entries.
    tool_packages = [
        extract_pep508_name(pkg)
        for pkg in backend_configs.get(backend_macro, {}).get("tool_packages", [])
    ]
    tool_deps = {}
    for pkg_name in tool_packages:
        if pkg_name in known_packages_set:
            tool_deps[pkg_name] = "@{}//{}:pkg".format(attr.thin_repo, underscore_name(pkg_name))

    # For pep517_build, pass the required package names for validation.
    if backend_macro == "pep517_build":
        macro_attrs["required_build_packages"] = str(sorted(required_build_packages.keys()))

    # Apply override backend configs: only use the entry matching the resolved backend.
    matching_config = {}
    non_matching_backends = []
    if attr.override_backend_configs:
        all_configs = json.decode(attr.override_backend_configs)

        matching_config = all_configs.pop(backend_macro, {})
        for attr_name, json_val in sorted(matching_config.items()):
            decoded = json.decode(json_val)
            if attr_name == "tool_deps":
                _merge_tool_deps_override(tool_deps, decoded, tool_packages, backend_macro, attr.sdist)
            elif type(decoded) == "string":
                macro_attrs[attr_name] = repr(decoded)
            else:
                macro_attrs[attr_name] = str(decoded)
        if all_configs:
            non_matching_backends = sorted(all_configs.keys())

    if tool_packages or tool_deps:
        macro_attrs["tool_deps"] = str(sorted({label: True for label in tool_deps.values()}.keys()))

    # Pass through pre_build_patches if specified.
    if attr.pre_build_patches:
        macro_attrs["pre_build_patches"] = str([str(p) for p in attr.pre_build_patches])

    # Pass through site_hooks if specified.
    if attr.site_hooks:
        macro_attrs["site_hooks"] = str(attr.site_hooks)

    return struct(
        macro_attrs = macro_attrs,
        backend_macro = backend_macro,
        site_paths = site_paths,
        bin_paths = bin_paths,
        applied_override_config = matching_config,
        non_matching_override_backends = non_matching_backends,
    )

def _select_hook_extract_patterns(attr, hook_files_by_backend, backend_to_rule = None, default_backend = None):
    """Return sorted deduplicated sdist file patterns requested by applicable sdist hooks."""
    if not hook_files_by_backend:
        return []
    if attr.build_backend:
        raw_patterns = hook_files_by_backend.get(attr.build_backend, [])
    else:
        backend_to_rule = backend_to_rule if backend_to_rule != None else BACKEND_TO_RULE
        default_backend = default_backend if default_backend != None else DEFAULT_BACKEND
        possible = {v: True for v in backend_to_rule.values()}
        if default_backend:
            possible[default_backend] = True
        raw_patterns = []
        for backend_name, backend_patterns in hook_files_by_backend.items():
            if backend_name in possible:
                raw_patterns.extend(backend_patterns)
    return sorted({pat: True for pat in raw_patterns}.keys())

def _sdist_repo_common(rctx):
    """Shared sdist repo logic: inspect metadata, resolve backend, apply override configs.

    Args:
        rctx: The repository context.

    Returns:
        A struct with:
            macro_attrs: Dict of macro attribute name -> Starlark literal string.
            backend_macro: The resolved backend macro name.
            applied_override_config: Dict of override config entries that matched the resolved backend.
            hook_files_dir: Optional Path to temporary dir of sdist files extracted for hooks.
            render: A function(macro_attrs, backend_macro, extra_build_snippets) to write BUILD.bazel.
    """
    _validate_build_backend(rctx.attr)

    if rctx.attr.sdist_unverified:
        # buildifier: disable=print
        print("WARNING: Building sdist '{}' without a sha256 hash in the lock file; integrity was not verified.".format(
            rctx.attr.sdist,
        ))

    sdist_path = rctx.path(rctx.attr.sdist)
    if hasattr(rctx, "watch"):
        # rctx.path() does not record file contents as repo inputs, so watch
        # pre_build_patches explicitly. Verified remote sdists carry their
        # sha256 in `sdist_sha256` (so cache hits don't need to materialize
        # the archive repo); watch unpinned/local sdists directly.
        if not rctx.attr.sdist_sha256:
            rctx.watch(sdist_path)
        for patch_label in rctx.attr.pre_build_patches:
            rctx.watch(patch_label)
    output_json = rctx.path("build_metadata.json")

    # Run the Python inspector tool
    inspect_args = [
        "--sdist",
        str(sdist_path),
        "--output",
        str(output_json),
    ]
    if rctx.attr.source_dir:
        inspect_args.extend(["--source-dir", rctx.attr.source_dir])
    for patch_label in rctx.attr.pre_build_patches:
        inspect_args.extend(["--pre-build-patch", str(rctx.path(patch_label))])

    extract_patterns = _select_hook_extract_patterns(rctx.attr, SDIST_HOOK_FILES)
    hook_files_dir = None
    if extract_patterns:
        hook_files_dir = rctx.path("_sdist_hook_files")
        inspect_args.extend(["--extract-files-dir", str(hook_files_dir)])
        for pattern in extract_patterns:
            inspect_args.extend(["--extract-file", pattern])

    exec_internal_tool(
        rctx,
        Label("//pycross/private/tools:inspect_package.py"),
        inspect_args,
        include_patch_module = bool(rctx.attr.pre_build_patches),
    )

    metadata = json.decode(rctx.read(output_json))
    rctx.delete(output_json)
    warnings = list(metadata.get("warnings", []))

    # Print any warnings from the package inspector
    for warning in warnings:
        # buildifier: disable=print
        print(warning)

    config = _compute_sdist_build_config(rctx.attr, metadata)
    site_paths = config.site_paths
    bin_paths = config.bin_paths

    rctx.file("inspection.json", json.encode({
        "site_paths": site_paths,
        "bin_paths": bin_paths,
        "data_paths": [],
        "include_paths": [],
        "warnings": warnings,
    }))

    if config.non_matching_override_backends:
        # buildifier: disable=print
        print("WARNING: package '{}' has override configs for non-matching backends: {}".format(
            rctx.attr.sdist,
            ", ".join(config.non_matching_override_backends),
        ))

    return struct(
        macro_attrs = config.macro_attrs,
        backend_macro = config.backend_macro,
        site_paths = site_paths,
        bin_paths = bin_paths,
        applied_override_config = config.applied_override_config,
        hook_files_dir = hook_files_dir,
        render = lambda macro_attrs, backend_macro, extra_build_snippets = None: _render_build_file(rctx, macro_attrs, backend_macro, site_paths, bin_paths, extra_build_snippets),
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

    if result.hook_files_dir != None and result.hook_files_dir.exists:
        rctx.delete(result.hook_files_dir)

    result.render(macro_attrs, backend_macro, extra_build_snippets)

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)

    return None

_SDIST_REPO_ATTRS = {
    "sdist": attr.label(mandatory = True),
    "sdist_sha256": attr.string(
        doc = "Verified SHA256 of `sdist`. When set, the repo rule relies on this attribute " +
              "for cache invalidation instead of watching `sdist`, so repo contents cache hits " +
              "do not need to materialize the archive repo.",
    ),
    "sdist_unverified": attr.bool(
        default = False,
        doc = "Whether `sdist` was fetched from a direct URL without a lockfile sha256 hash.",
    ),
    "deps": attr.string_list(doc = "Runtime dependencies from lock file."),
    "known_packages": attr.string_list(doc = "Sorted canonical package names pinned in the build tools repo, used to filter build_requires."),
    "build_backend": attr.string(doc = "The build backend to use."),
    "thin_repo": attr.string(
        doc = "Name of the thin workspace repo.",
        mandatory = True,
    ),
    "extra_build_tools": attr.string_list(doc = "Additional build-time tool packages."),
    "override_backend_configs": attr.string(
        doc = "JSON-encoded dict mapping backend rule names to their backend_attrs for this package. " +
              "Populated from backend override extensions. Only the entry matching the resolved backend is applied.",
    ),
    "pre_build_patches": attr.label_list(doc = "Patches to apply to the sdist source tree before building."),
    "site_hooks": attr.string_list(doc = "Python code snippets to execute on interpreter startup during builds."),
    "whldir_name": attr.string(doc = "Name for the output .whldir TreeArtifact directory."),
    "source_dir": attr.string(doc = "Subdirectory within the sdist archive to build."),
}

pycross_sdist_repo = repository_rule(
    implementation = _sdist_repo_impl,
    attrs = _SDIST_REPO_ATTRS,
)

# Visible for testing
compute_sdist_build_config_for_testing = _compute_sdist_build_config
render_build_content_for_testing = _render_build_content
select_hook_extract_patterns_for_testing = _select_hook_extract_patterns
