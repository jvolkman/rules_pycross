"""Setuptools overrides extension."""

load("//pycross/private/bzlmod:override_helpers.bzl", "make_override_extension")
load("//pycross/private/bzlmod:tag_attrs.bzl", "SETUPTOOLS_OVERRIDE_ATTRS")

setuptools = make_override_extension("setuptools", "setuptools_build", SETUPTOOLS_OVERRIDE_ATTRS)
