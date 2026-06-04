"""Meson build backend for rules_pycross."""

load("//pycross/private/build/rules:meson_build.bzl", _meson_build = "meson_build")
load("//pycross/private/bzlmod:override_helpers.bzl", "make_override_extension")
load("//pycross/private/bzlmod:tag_attrs.bzl", "MESON_OVERRIDE_ATTRS")

meson_build = _meson_build

meson = make_override_extension("meson", "meson_build", MESON_OVERRIDE_ATTRS)
