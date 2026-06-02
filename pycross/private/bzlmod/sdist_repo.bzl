"""Repository rule for auto-generating a BUILD file for an sdist package."""

load("//pycross/private:internal_repo.bzl", "exec_internal_tool")
load("//pycross/private:util.bzl", "extract_pep508_name")
load(":cargo.bzl", "find_cargo_lock_in_sdist", "vendor_crates_from_lock")

_BACKEND_TO_RULE = {
    "mesonpy": "meson_build",
    "mesonbuild": "meson_build",
    "scikit_build_core.build": "cmake_build",
    "setuptools.build_meta": "setuptools_build",
    "setuptools.build_meta:__legacy__": "setuptools_build",
    "maturin": "maturin_build",
    "hatchling.build": "pep517_build",
    "flit_core.buildapi": "pep517_build",
    "pdm.backend": "pep517_build",
    "poetry.core.masonry.api": "pep517_build",
}

def _sdist_repo_impl(rctx):
    macro_attrs = {
        "name": "\"wheel\"",
        "sdist": "\"{}\"".format(rctx.attr.sdist),
        "deps": str(rctx.attr.deps),
    }

    if rctx.attr.build_backend:
        backend_macro = rctx.attr.build_backend
        if backend_macro not in _BACKEND_TO_RULE.values():
            fail("Unknown build backend: " + backend_macro)

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

        # Map backend to rule
        # If not in the dictionary, we fall back to setuptools_build as the generic PEP 517 builder
        backend_macro = _BACKEND_TO_RULE.get(backend, "setuptools_build")

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

    # Add optional overrides if they are set/non-empty
    if rctx.attr.copts:
        macro_attrs["copts"] = str(rctx.attr.copts)
    if rctx.attr.linkopts:
        macro_attrs["linkopts"] = str(rctx.attr.linkopts)
    if rctx.attr.native_deps:
        macro_attrs["native_deps"] = str(rctx.attr.native_deps)
    if rctx.attr.config_settings:
        macro_attrs["config_settings"] = str(rctx.attr.config_settings)
    if rctx.attr.tool_deps:
        macro_attrs["tool_deps"] = str(rctx.attr.tool_deps)
    if rctx.attr.cargo_lock:
        macro_attrs["cargo_lock"] = "\"{}\"".format(rctx.attr.cargo_lock)

    has_vendored = False
    if backend_macro == "maturin_build":
        cargo_lock_path = None
        if rctx.attr.cargo_lock:
            cargo_lock_path = rctx.path(rctx.attr.cargo_lock)
        else:
            # Extract sdist to find Cargo.lock
            tmp_dir = "cargo_lock_check_tmp"
            rctx.extract(archive = rctx.attr.sdist, output = tmp_dir)

            sdist_root = None
            for child in rctx.path(tmp_dir).readdir():
                if child.is_dir:
                    sdist_root = child
                    break
            if not sdist_root:
                sdist_root = rctx.path(tmp_dir)

            lock_candidate = find_cargo_lock_in_sdist(rctx, sdist_root)
            if lock_candidate.exists:
                # Copy it out before deleting tmp
                extracted_lock = rctx.path("Cargo.lock.extracted")
                rctx.file(extracted_lock, rctx.read(lock_candidate))
                cargo_lock_path = extracted_lock

            rctx.delete(tmp_dir)

        if cargo_lock_path:
            vendor_crates_from_lock(rctx, cargo_lock_path)
            has_vendored = True

            # Clean up temporary extracted lock
            extracted = rctx.path("Cargo.lock.extracted")
            if extracted.exists:
                rctx.delete("Cargo.lock.extracted")

    if has_vendored:
        macro_attrs["vendored_crates"] = "\":vendored_crates\""

    # Now render the macro attributes in BUILD.bazel format
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

pycross_sdist_repo = repository_rule(
    implementation = _sdist_repo_impl,
    attrs = {
        "sdist": attr.label(mandatory = True),
        "deps": attr.string_list(doc = "Runtime dependencies from lock file."),
        "known_packages": attr.string_list(doc = "List of packages present in the lock file to filter build_requires."),
        "lock_repo": attr.string(doc = "Name of the lock hub repo (e.g. 'uv').", mandatory = True),
        "build_backend": attr.string(doc = "The build backend to use."),
        "copts": attr.string_list(doc = "C compiler options."),
        "linkopts": attr.string_list(doc = "Linker options."),
        "native_deps": attr.string_list(doc = "Labels of native C/C++ dependencies."),
        "config_settings": attr.string_list_dict(doc = "Build configuration settings passed to backend."),
        "tool_deps": attr.string_dict(doc = "Overridden tool dependencies."),
        "build_dependencies": attr.string_list(doc = "Overridden build-time dependencies."),
        "cargo_lock": attr.label(allow_single_file = [".lock"], doc = "A Cargo.lock file to use."),
    },
)
