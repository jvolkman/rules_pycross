"""Repository rule for auto-generating a BUILD file for an sdist package.

The common logic is factored into sdist_repo_common() so that backend-specific
repo rules (e.g. maturin_sdist_repo) can reuse it.
"""

load("//pycross/private:internal_repo.bzl", "exec_internal_tool")
load("//pycross/private:util.bzl", "extract_pep508_name")

def _render_build_file(rctx, macro_attrs, backend_macro, has_vendored = False):
    """Render the BUILD.bazel file for an sdist repo.

    Args:
        rctx: The repository context.
        macro_attrs: Dict of macro attribute name -> Starlark literal string.
        backend_macro: The backend macro name (e.g. 'meson_build').
        has_vendored: Whether cargo crates were vendored (adds filegroup).
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

    if has_vendored:
        build_content += """
filegroup(
    name = "vendored_crates",
    srcs = glob(["vendor/**"]),
)
"""

    rctx.file("BUILD.bazel", build_content)
    rctx.file("REPO.bazel", "")

def sdist_repo_common(rctx):
    """Shared sdist repo logic: inspect metadata, resolve backend, decode backend_attrs.

    Args:
        rctx: The repository context.

    Returns:
        A struct with:
            macro_attrs: Dict of macro attribute name -> Starlark literal string.
            backend_macro: The resolved backend macro name.
            render: A function(macro_attrs, backend_macro, has_vendored) to write BUILD.bazel.
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
            ],
        )

        metadata = json.decode(rctx.read(output_json))
        backend = metadata.get("build_backend", "")
        requires = metadata.get("build_requires", [])

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

    # Render backend_attrs: each key becomes a macro attr, each value is
    # a JSON-encoded Starlark literal that we decode and render.
    for attr_name, json_val in sorted(rctx.attr.backend_attrs.items()):
        decoded = json.decode(json_val)
        if type(decoded) == "string":
            macro_attrs[attr_name] = "\"{}\"".format(decoded)
        else:
            macro_attrs[attr_name] = str(decoded)

    return struct(
        macro_attrs = macro_attrs,
        backend_macro = backend_macro,
        render = lambda macro_attrs, backend_macro, has_vendored = False: _render_build_file(rctx, macro_attrs, backend_macro, has_vendored),
    )

# -- Default (generic) sdist repo rule --

def _sdist_repo_impl(rctx):
    result = sdist_repo_common(rctx)
    result.render(result.macro_attrs, result.backend_macro)

_SDIST_REPO_ATTRS = {
    "sdist": attr.label(mandatory = True),
    "deps": attr.string_list(doc = "Runtime dependencies from lock file."),
    "known_packages": attr.string_list(doc = "List of packages present in the lock file to filter build_requires."),
    "lock_repo": attr.string(doc = "Name of the lock hub repo (e.g. 'uv').", mandatory = True),
    "build_backend": attr.string(doc = "The build backend to use."),
    "backend_to_rule": attr.string_dict(
        doc = "Registry mapping pyproject backend names to pycross rule names.",
    ),
    "default_backend": attr.string(
        doc = "The rule name used when no pyproject backend name matches.",
    ),
    "build_dependencies": attr.string_list(doc = "Overridden build-time dependencies."),
    "backend_attrs": attr.string_dict(doc = "Arbitrary backend-specific attrs. Keys are attr names; values are JSON-encoded Starlark literals."),
}

pycross_sdist_repo = repository_rule(
    implementation = _sdist_repo_impl,
    attrs = _SDIST_REPO_ATTRS,
)

# Exported for backend-specific repo rules to reuse.
SDIST_REPO_ATTRS = _SDIST_REPO_ATTRS
