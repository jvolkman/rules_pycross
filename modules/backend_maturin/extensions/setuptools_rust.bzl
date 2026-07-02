"""Setuptools Rust overrides extension."""

load("@bazel_features//:features.bzl", "bazel_features")
load(
    "@rules_pycross//pycross:backend.bzl",
    "BUILD_SYSTEM_ATTRS",
    "CC_BUILD_SYSTEM_ATTRS",
    "create_overrides_repo",
    "encode_build_system_attrs",
)

_CORE_OVERRIDE_ATTRS = dict(
    name = attr.string(
        doc = "The package key (name or name@version).",
        mandatory = True,
    ),
    repo = attr.string(
        doc = "The repository name (if applying to a specific lock file).",
    ),
    workspace = attr.string(
        doc = "The workspace name (if applying to all members of a workspace).",
    ),
)

_SETUPTOOLS_RUST_OVERRIDE_ATTRS = _CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS

def _setuptools_rust_overrides_impl(module_ctx):
    overrides = {}

    for module in module_ctx.modules:
        for tag in module.tags.override:
            if tag.repo and tag.workspace:
                fail("override for '{}' specifies both repo and workspace".format(tag.name))
            if not tag.repo and not tag.workspace:
                fail("override for '{}' must specify either repo or workspace".format(tag.name))

            backend_attrs = encode_build_system_attrs(tag)
            if tag.cargo_lock:
                backend_attrs["cargo_lock"] = json.encode(str(tag.cargo_lock))
            if tag.sdist:
                backend_attrs["sdist"] = json.encode(str(tag.sdist))

            key = "repo:" + tag.repo if tag.repo else "workspace:" + tag.workspace
            overrides.setdefault(key, {})[tag.name] = {
                "build_backend": "setuptools_rust_build",
                "backend_attrs": backend_attrs,
            }

    create_overrides_repo(
        name = "setuptools_rust_overrides",
        content = json.encode(overrides),
    )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(reproducible = True)
    return module_ctx.extension_metadata()

override_attrs = dict(
    sdist = attr.label(
        doc = "Label to the sdist target. Used to resolve repository visibility in the generated _cargo repo.",
    ),
    cargo_lock = attr.label(
        doc = "A Cargo.lock file to use. If not provided, the sdist's own Cargo.lock is used.",
        allow_single_file = [".lock"],
    ),
    **_SETUPTOOLS_RUST_OVERRIDE_ATTRS
)

setuptools_rust = module_extension(
    implementation = _setuptools_rust_overrides_impl,
    tag_classes = dict(
        override = tag_class(
            doc = "Specify setuptools-rust-specific package overrides.",
            attrs = override_attrs,
        ),
    ),
)
