"""The environments extension creates target environment definitions."""

load("@pythons_hub//:interpreters.bzl", "DEFAULT_PYTHON_VERSION")
load(
    "@rules_pycross_internal//:defaults.bzl",
    default_glibc_version = "glibc_version",
    default_macos_version = "macos_version",
    default_platforms = "platforms",
    default_python_versions = "python_versions",
)
load("//pycross/private:toolchain_helpers.bzl", "pycross_environments_repo")
load(":tag_attrs.bzl", "CREATE_ENVIRONMENTS_ATTRS")

def _environments_impl(module_ctx):
    for module in module_ctx.modules:
        for tag in module.tags.create_for_python_toolchains:
            pycross_environments_repo(
                name = tag.name,
                python_toolchains_repo = tag.python_versions_repo,
                default_python_version = DEFAULT_PYTHON_VERSION,
                platforms = tag.platforms or default_platforms,
                requested_python_versions = tag.python_versions or default_python_versions,
                glibc_version = tag.glibc_version or default_glibc_version,
                macos_version = tag.macos_version or default_macos_version,
            )

environments = module_extension(
    doc = "Create target environments.",
    implementation = _environments_impl,
    tag_classes = {
        "create_for_python_toolchains": tag_class(
            attrs = dict(
                name = attr.string(
                    mandatory = True,
                ),
                python_versions_repo = attr.label(
                    mandatory = True,
                ),
            ) | CREATE_ENVIRONMENTS_ATTRS,
        ),
    },
)
