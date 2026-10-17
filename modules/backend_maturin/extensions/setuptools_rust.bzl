"""Setuptools Rust overrides extension."""

load("@rules_pycross//pycross:backend.bzl", "make_override_extension")
load(":maturin.bzl", "override_attrs")

setuptools_rust = make_override_extension("setuptools_rust", "setuptools_rust_build", override_attrs)
