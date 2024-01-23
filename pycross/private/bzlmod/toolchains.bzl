"""Internal extension to create pycross toolchains."""

load("@pythons_hub//:interpreters.bzl", "DEFAULT_PYTHON_VERSION")
load(
    "@rules_pycross_internal//:defaults.bzl",
    "register_toolchains",
    default_platforms = "platforms",
    default_python_versions = "python_versions",
)
load("//pycross/private:toolchain_helpers.bzl", "pycross_toolchains_repo")

def _toolchains_impl(module_ctx):
    creator = None
    for module in module_ctx.modules:
        for tag in module.tags.create_for_python_toolchains:
            # This extension is a singleton.
            if creator:
                fail("toolchains.create_for_python_toolchains already called by module {}".format(creator))

            creator = module.name
            if register_toolchains:
                pycross_toolchains_repo(
                    name = tag.name,
                    python_toolchains_repo = tag.python_versions_repo,
                    requested_python_versions = tag.python_versions,
                    default_python_version = DEFAULT_PYTHON_VERSION,
                    platforms = tag.platforms,
                )
            else:
                _empty_repo(name = tag.name)

toolchains = module_extension(
    doc = "Create toolchains.",
    implementation = _toolchains_impl,
    # OS and arch dependent since we load from @pythons_hub//:interpreters.bzl.
    os_dependent = True,
    arch_dependent = True,
    tag_classes = {
        "create_for_python_toolchains": tag_class(
            attrs = {
                "name": attr.string(
                    default = "pycross_toolchains",
                ),
                "python_versions_repo": attr.label(
                    mandatory = True,
                ),
                "python_versions": attr.string_list(default = default_python_versions),
                "platforms": attr.string_list(default = default_platforms),
            },
        ),
    },
)

_empty_repo = repository_rule(
    implementation = lambda repository_ctx: repository_ctx.file("BUILD.bazel"),
)
