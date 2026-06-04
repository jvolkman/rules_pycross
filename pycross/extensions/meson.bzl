"""Meson overrides extension."""

load("//pycross/private/bzlmod:override_helpers.bzl", "make_override_extension")
load("//pycross/private/bzlmod:tag_attrs.bzl", "MESON_OVERRIDE_ATTRS")

meson = make_override_extension("meson", "meson_build", MESON_OVERRIDE_ATTRS)
