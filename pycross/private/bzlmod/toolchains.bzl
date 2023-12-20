load("@pythons_hub//:interpreters.bzl", "DEFAULT_PYTHON_VERSION")
load("//pycross/private:toolchain_helpers.bzl", "pycross_toolchains_repo")

def _toolchains_impl(module_ctx):
    for module in module_ctx.modules:
        for tag in module.tags.create_for_python_toolchains:
            pycross_toolchains_repo(
                name = tag.name,
                python_toolchains_repo = tag.python_versions_repo,
                requested_python_versions = tag.python_versions,
                default_python_version = DEFAULT_PYTHON_VERSION,
                platforms = tag.platforms,
            )

toolchains = module_extension(
    doc = "Create toolchains.",
    implementation = _toolchains_impl,
    tag_classes = {
        "create_for_python_toolchains": tag_class(
            attrs = {
                "name": attr.string(
                    default = "pycross_toolchains",
                ),
                "python_versions_repo": attr.label(
                    mandatory = True,
                ),
                "python_versions": attr.string_list(),
                "platforms": attr.string_list(),
            },
        ),
    },
)
