"""Maturin build backend for rules_pycross."""

load("//pycross/private/build/rules:maturin_build.bzl", _maturin_build = "maturin_build")

maturin_build = _maturin_build
