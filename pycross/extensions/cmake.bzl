"""CMake overrides extension."""

load("//pycross/private/bzlmod:override_helpers.bzl", "make_override_extension")
load("//pycross/private/bzlmod:tag_attrs.bzl", "CMAKE_OVERRIDE_ATTRS")

cmake = make_override_extension("cmake", "cmake_build", CMAKE_OVERRIDE_ATTRS)
