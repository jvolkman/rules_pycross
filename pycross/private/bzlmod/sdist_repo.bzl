"""Repository rule for auto-generating a BUILD file for an sdist package."""

load("//pycross/private:internal_repo.bzl", "exec_internal_tool")
load("//pycross/private:util.bzl", "extract_pep508_name", "sanitize_name")

_BACKEND_TO_PROFILE = {
    "mesonpy": "meson_build",
    "mesonbuild": "meson_build",
    "scikit_build_core.build": "cmake_build",
    "setuptools.build_meta": "setuptools_build",
    "setuptools.build_meta:__legacy__": "setuptools_build",
    "maturin": "maturin_build",
    "hatchling.build": "hatch_build",
    "flit_core.buildapi": "flit_build",
}

_PROFILE_TO_BZL = {
    "meson_build": "meson.bzl",
    "cmake_build": "cmake.bzl",
    "setuptools_build": "setuptools.bzl",
    "maturin_build": "maturin.bzl",
    "hatch_build": "hatch.bzl",
    "flit_build": "flit.bzl",
}

def _sdist_repo_impl(rctx):
    macro_attrs = {
        "name": "\"pkg\"",
        "sdist": "\"{}\"".format(rctx.attr.sdist),
        "deps": str(rctx.attr.deps),
    }

    if rctx.attr.build_profile:
        profile_macro = rctx.attr.build_profile
        if profile_macro not in _PROFILE_TO_BZL:
            fail("Unknown build profile: " + profile_macro)
        profile_bzl = _PROFILE_TO_BZL[profile_macro]

        if rctx.attr.build_dependencies:
            build_deps = []
            for dep in rctx.attr.build_dependencies:
                dep_name = dep.split("@")[0]
                build_deps.append("@{}//:{}".format(rctx.attr.lock_repo, sanitize_name(dep_name)))
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

        # Map backend to profile
        # If not in the dictionary, we fall back to setuptools_build as the generic PEP 517 builder
        profile_macro = _BACKEND_TO_PROFILE.get(backend, "setuptools_build")
        profile_bzl = _PROFILE_TO_BZL.get(profile_macro, "setuptools.bzl")

        # Map build requires to targets in the hub repo
        build_deps = []
        for req in requires:
            req_name = extract_pep508_name(req)
            if req_name == "oldest_supported_numpy":
                req_name = "numpy"

            # We only add it if it's in the known lock repo mapping.
            # (This will be passed in via rctx.attr.known_packages)
            if req_name in rctx.attr.known_packages:
                build_deps.append("@{}//:{}".format(rctx.attr.lock_repo, req_name))
        macro_attrs["build_deps"] = str(build_deps)

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

    macro_attrs["repo"] = "\"@{}\"".format(rctx.attr.lock_repo)

    # Now render the macro attributes in BUILD.bazel format
    attr_lines = []
    for key, val in sorted(macro_attrs.items()):
        attr_lines.append("    {} = {},".format(key, val))

    build_content = """\nload("@rules_pycross//pycross/profiles:{profile_bzl}", "{profile_macro}")

package(default_visibility = ["//visibility:public"])

{profile_macro}(
{attrs}
)
""".format(
        profile_bzl = profile_bzl,
        profile_macro = profile_macro,
        attrs = "\n".join(attr_lines),
    )

    rctx.file("BUILD.bazel", build_content)
    rctx.file("REPO.bazel", "")

pycross_sdist_repo = repository_rule(
    implementation = _sdist_repo_impl,
    attrs = {
        "sdist": attr.label(mandatory = True),
        "deps": attr.string_list(doc = "Runtime dependencies from lock file."),
        "known_packages": attr.string_list(doc = "List of packages present in the lock file to filter build_requires."),
        "lock_repo": attr.string(doc = "Name of the lock hub repo (e.g. 'uv').", mandatory = True),
        "build_profile": attr.string(doc = "The build profile to use."),
        "copts": attr.string_list(doc = "C compiler options."),
        "linkopts": attr.string_list(doc = "Linker options."),
        "native_deps": attr.string_list(doc = "Labels of native C/C++ dependencies."),
        "config_settings": attr.string_list_dict(doc = "Build configuration settings passed to backend."),
        "tool_deps": attr.string_dict(doc = "Overridden tool dependencies."),
        "build_dependencies": attr.string_list(doc = "Overridden build-time dependencies."),
    },
)
