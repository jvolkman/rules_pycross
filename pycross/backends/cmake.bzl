"""CMake build backend for rules_pycross."""

load("//pycross:backend.bzl", "make_override_extension")
load("//pycross/private/build/rules:cmake_build.bzl", _cmake_build = "cmake_build")
load("//pycross/private/bzlmod:tag_attrs.bzl", "CMAKE_OVERRIDE_ATTRS")

cmake_build = _cmake_build

cmake = make_override_extension("cmake", "cmake_build", CMAKE_OVERRIDE_ATTRS)
