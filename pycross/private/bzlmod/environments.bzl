load("@pythons_hub//:interpreters.bzl", "DEFAULT_PYTHON_VERSION")
load("//pycross/private:toolchain_helpers.bzl", "DEFAULT_GLIBC_VERSION", "DEFAULT_MACOS_VERSION", "pycross_environments_repo")

def _environments_impl(module_ctx):
    for module in module_ctx.modules:
        for tag in module.tags.create_for_python_toolchains:
            pycross_environments_repo(
                name = tag.name,
                python_toolchains_repo = tag.python_versions_repo,
                requested_python_versions = tag.python_versions,
                default_python_version = DEFAULT_PYTHON_VERSION,
                platforms = tag.platforms,
                glibc_version = tag.glibc_version,
                macos_version = tag.macos_version,
            )

environments = module_extension(
    doc = "Create target environments.",
    implementation = _environments_impl,
    tag_classes = {
        "create_for_python_toolchains": tag_class(
            attrs = {
                "name": attr.string(
                    default = "pycross_environments",
                ),
                "python_versions_repo": attr.label(
                    mandatory = True,
                ),
                "python_versions": attr.string_list(),
                "platforms": attr.string_list(),
                "glibc_version": attr.string(default = DEFAULT_GLIBC_VERSION),
                "macos_version": attr.string(default = DEFAULT_MACOS_VERSION),
            },
        ),
    },
)
