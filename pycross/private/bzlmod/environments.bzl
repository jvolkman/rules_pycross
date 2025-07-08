"""The environments extension creates target environment definitions."""

load("@bazel_features//:features.bzl", "bazel_features")
load(
    "@rules_pycross_internal//:defaults.bzl",
    default_glibc_version = "glibc_version",
    default_macos_version = "macos_version",
    default_musl_version = "musl_version",
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
                python_toolchains_repo = "@python_versions",
                pythons_hub_repo = "@pythons_hub",
                platforms = tag.platforms or default_platforms,
                requested_python_versions = tag.python_versions or default_python_versions,
                glibc_version = tag.glibc_version or default_glibc_version,
                musl_version = tag.musl_version or default_musl_version,
                macos_version = tag.macos_version or default_macos_version,
            )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(reproducible = True)
    return module_ctx.extension_metadata()

environments = module_extension(
    doc = "Create target environments.",
    implementation = _environments_impl,
    tag_classes = {
        "create_for_python_toolchains": tag_class(
            attrs = dict(
                name = attr.string(
                    mandatory = True,
                ),
            ) | CREATE_ENVIRONMENTS_ATTRS,
        ),
    },
)
