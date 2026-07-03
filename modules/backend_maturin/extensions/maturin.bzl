"""Maturin overrides extension.

Provides the `maturin` module extension with an `override` tag class
for declaring maturin-specific package overrides. Generates:

  1. `@maturin_overrides//:overrides.json` — consumed by lock_import via
     `lock_import.override_source(file = ...)`.

  2. `@<repo>_cargo//` repos — containing `pycross_generate_cargo_lock` targets
     for each maturin-overridden package.
"""

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
    workspace = attr.string(
        doc = "The workspace name (if applying to all members of a workspace).",
    ),
)

_MATURIN_OVERRIDE_ATTRS = _CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS

def _maturin_overrides_impl(module_ctx):
    maturin_overrides = {}

    for module in module_ctx.modules:
        # Process maturin overrides
        for tag in module.tags.override:
            if not tag.workspace:
                fail("override for '{}' must specify workspace".format(tag.name))

            backend_attrs = encode_build_system_attrs(tag)
            if tag.cargo_lock:
                backend_attrs["cargo_lock"] = json.encode(str(tag.cargo_lock))
            if tag.sdist:
                backend_attrs["sdist"] = json.encode(str(tag.sdist))

            key = tag.workspace
            maturin_overrides.setdefault(key, {})[tag.name] = {
                "build_backend": "maturin_build",
                "backend_attrs": backend_attrs,
            }

    # Write overrides JSON
    create_overrides_repo(
        name = "maturin_overrides",
        content = json.encode(maturin_overrides),
    )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(reproducible = True)
    return module_ctx.extension_metadata()

override_attrs = dict(
    sdist = attr.label(
        doc = "Label to the sdist target (e.g. @uv//pkg:sdist). Used to resolve repository visibility in the generated _cargo repo.",
    ),
    cargo_lock = attr.label(
        doc = "A Cargo.lock file to use. If not provided, the sdist's own Cargo.lock is used.",
        allow_single_file = [".lock"],
    ),
    **_MATURIN_OVERRIDE_ATTRS
)

maturin = module_extension(
    implementation = _maturin_overrides_impl,
    tag_classes = dict(
        override = tag_class(
            doc = "Specify maturin-specific package overrides.",
            attrs = override_attrs,
        ),
    ),
)
