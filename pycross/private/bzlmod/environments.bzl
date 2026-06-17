"""The environments extension creates target environment definitions."""

load("@bazel_features//:features.bzl", "bazel_features")
load(
    "@rules_pycross_internal_config//:defaults.bzl",
    default_glibc_version = "glibc_version",
    default_macos_version = "macos_version",
    default_musl_version = "musl_version",
    default_platforms = "platforms",
    default_python_versions = "python_versions",
)
load("//pycross/private:toolchain_helpers.bzl", "pycross_environments_repo")

_VERSION_ATTRS = dict(
    glibc_version = attr.string(
        doc = "Default glibc version for Linux platforms.",
    ),
    musl_version = attr.string(
        doc = "Default musl version for Linux musl platforms.",
    ),
    macos_version = attr.string(
        doc = "Default macOS version for Darwin platforms.",
    ),
)

_CREATE_FOR_PYTHON_TOOLCHAINS_ATTRS = dict(
    name = attr.string(
        doc = "The environments repo name.",
        default = "pycross_environments",
    ),
    python_versions = attr.string_list(
        doc = (
            "The list of Python versions to support. " +
            "By default all registered versions are supported."
        ),
    ),
    platforms = attr.string_list(
        doc = (
            "The list of Python platforms to support. " +
            "Mutually exclusive with platform() tags for this environments repo. " +
            "By default all supported platforms are included."
        ),
    ),
    **_VERSION_ATTRS
)

_CREATE_ATTRS = dict(
    name = attr.string(
        doc = "The environments repo name.",
        mandatory = True,
    ),
    **_VERSION_ATTRS
)

_PYTHON_ATTRS = dict(
    envs = attr.string(
        doc = "Name of the environments repo. Defaults to 'pycross_environments'.",
        default = "pycross_environments",
    ),
    version = attr.string(
        doc = "Python version (e.g. '3.11.6' or '3.12').",
        mandatory = True,
    ),
)

_PLATFORM_ATTRS = dict(
    envs = attr.string(
        doc = "Name of the environments repo. Defaults to 'pycross_environments'.",
        default = "pycross_environments",
    ),
    target = attr.string(
        doc = "Platform triple (e.g. 'x86_64-unknown-linux-gnu').",
        mandatory = True,
    ),
    glibc_version = attr.string(
        doc = "Override glibc version for this platform.",
    ),
    musl_version = attr.string(
        doc = "Override musl version for this platform.",
    ),
    macos_version = attr.string(
        doc = "Override macOS version for this platform.",
    ),
)

def _environments_impl(module_ctx):
    # Collect all create_for_python_toolchains and create tags.
    repos = {}  # name -> {tag, kind, python_versions, platform_configs}

    for module in module_ctx.modules:
        for tag in module.tags.create_for_python_toolchains:
            name = tag.name
            if name in repos:
                fail("Duplicate environments repo name: {}".format(name))
            repos[name] = struct(
                tag = tag,
                kind = "toolchains",
                python_versions = [],
                platform_configs = [],
            )

        for tag in module.tags.create:
            name = tag.name
            if name in repos:
                fail("Duplicate environments repo name: {}".format(name))
            repos[name] = struct(
                tag = tag,
                kind = "explicit",
                python_versions = [],
                platform_configs = [],
            )

    # Collect python() tags (only valid for "explicit" repos).
    for module in module_ctx.modules:
        for tag in module.tags.python:
            name = tag.envs
            if name not in repos:
                fail("python() tag references unknown environments repo: {}".format(name))
            repo = repos[name]
            if repo.kind != "explicit":
                fail(
                    "python() tags can only be used with create(), not create_for_python_toolchains(). " +
                    "Repo '{}' auto-discovers Python versions from rules_python.".format(name),
                )
            repo.python_versions.append(tag.version)

    # Collect platform() tags.
    for module in module_ctx.modules:
        for tag in module.tags.platform:
            name = tag.envs
            if name not in repos:
                fail("platform() tag references unknown environments repo: {}".format(name))
            repo = repos[name]

            # Check mutual exclusivity with platforms list.
            if repo.kind == "toolchains" and repo.tag.platforms:
                fail(
                    "Cannot use platform() tags with a create_for_python_toolchains() that has a " +
                    "'platforms' list. Use one or the other for repo '{}'.".format(name),
                )

            repo.platform_configs.append({
                "target": tag.target,
                "glibc_version": tag.glibc_version if tag.glibc_version else None,
                "musl_version": tag.musl_version if tag.musl_version else None,
                "macos_version": tag.macos_version if tag.macos_version else None,
            })

    # Create environment repos.
    for name, repo in repos.items():
        tag = repo.tag

        if repo.kind == "toolchains":
            pycross_environments_repo(
                name = name,
                python_toolchains_repo = "@python_versions",
                pythons_hub_repo = "@pythons_hub",
                platforms = tag.platforms or default_platforms,
                requested_python_versions = tag.python_versions or default_python_versions,
                glibc_version = tag.glibc_version or default_glibc_version,
                musl_version = tag.musl_version or default_musl_version,
                macos_version = tag.macos_version or default_macos_version,
                platform_configs = json.encode(repo.platform_configs) if repo.platform_configs else None,
            )
        else:
            # "explicit" mode: python versions from python() tags.
            if not repo.python_versions:
                fail("create() repo '{}' has no python() tags. Add at least one.".format(name))

            pycross_environments_repo(
                name = name,
                python_toolchains_repo = "@python_versions",
                pythons_hub_repo = "@pythons_hub",
                platforms = [],
                requested_python_versions = repo.python_versions,
                glibc_version = tag.glibc_version or default_glibc_version,
                musl_version = tag.musl_version or default_musl_version,
                macos_version = tag.macos_version or default_macos_version,
                platform_configs = json.encode(repo.platform_configs) if repo.platform_configs else None,
            )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(reproducible = True)
    return module_ctx.extension_metadata()

environments = module_extension(
    doc = "Create target environments.",
    implementation = _environments_impl,
    tag_classes = {
        "create_for_python_toolchains": tag_class(
            doc = "Create an environments repo using Python versions discovered from rules_python.",
            attrs = _CREATE_FOR_PYTHON_TOOLCHAINS_ATTRS,
        ),
        "create": tag_class(
            doc = "Create an environments repo with explicit Python versions (BYOT).",
            attrs = _CREATE_ATTRS,
        ),
        "python": tag_class(
            doc = "Declare a Python version for a create() environments repo.",
            attrs = _PYTHON_ATTRS,
        ),
        "platform": tag_class(
            doc = "Declare a target platform with optional per-platform version overrides.",
            attrs = _PLATFORM_ATTRS,
        ),
    },
)
