"""Meson build backend for rules_pycross."""

load("//pycross:backend.bzl", "make_override_extension")
load("//pycross/private:lock_attrs.bzl", "MESON_OVERRIDE_ATTRS")
load("//pycross/private/build/rules:meson_build.bzl", _meson_build = "meson_build")

meson_build = _meson_build

meson = make_override_extension("meson", "meson_build", MESON_OVERRIDE_ATTRS)
