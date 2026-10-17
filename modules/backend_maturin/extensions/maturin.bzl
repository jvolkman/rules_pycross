"""Maturin overrides extension.

Provides the `maturin` module extension with an `override` tag class
for declaring maturin-specific package overrides. The overrides are written to
`@maturin_overrides//:overrides.json`, which the `backends` registry passes to
every lock extension.

For each overridden package that has an sdist, the lock repos also get a
`_cargo` package with a `pycross_generate_cargo_lock` target per version (for
example `bazel run @pypi//_cargo:jiter@<version>` writes a Cargo.lock for jiter).
"""

load(
    "@rules_pycross//pycross:backend.bzl",
    "BUILD_SYSTEM_ATTRS",
    "CC_BUILD_SYSTEM_ATTRS",
    "make_override_extension",
)

_CORE_OVERRIDE_ATTRS = dict(
    name = attr.string(
        doc = "The package name, `name@version`, or '*' to apply to all packages built with this backend. " +
              "For a package `name@version`, matching entries are layered from least to most specific " +
              "(`*`, then `name`, then `name@version`); each field set by a more specific entry replaces " +
              "the less specific value. The version must match a locked version exactly.",
        mandatory = True,
    ),
    workspace = attr.string(
        doc = "The workspace whose packages this override applies to.",
        mandatory = True,
    ),
)

override_attrs = dict(
    cargo_lock = attr.label(
        doc = "A Cargo.lock file to use. If not provided, the sdist's own Cargo.lock is used.",
        allow_single_file = [".lock"],
    ),
    **(_CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS)
)

maturin = make_override_extension("maturin", "maturin_build", override_attrs)
