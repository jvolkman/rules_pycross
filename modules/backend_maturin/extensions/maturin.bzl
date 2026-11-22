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
    "CC_OVERRIDE_ATTRS",
    "make_override_extension",
)

override_attrs = dict(
    cargo_lock = attr.label(
        doc = "A Cargo.lock file to use. If not provided, the sdist's own Cargo.lock is used.",
        allow_single_file = [".lock"],
    ),
    **CC_OVERRIDE_ATTRS
)

maturin = make_override_extension("maturin", "maturin_build", override_attrs)
