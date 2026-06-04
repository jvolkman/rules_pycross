"""Setuptools build backend for rules_pycross."""

load("//pycross/private/build/rules:setuptools_build.bzl", _setuptools_build = "setuptools_build")
load("//pycross/private/bzlmod:override_helpers.bzl", "make_override_extension")
load("//pycross/private/bzlmod:tag_attrs.bzl", "SETUPTOOLS_OVERRIDE_ATTRS")

setuptools_build = _setuptools_build

setuptools = make_override_extension("setuptools", "setuptools_build", SETUPTOOLS_OVERRIDE_ATTRS)
