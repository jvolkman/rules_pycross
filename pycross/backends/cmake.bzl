"""CMake build backend for rules_pycross."""

load("//pycross:backend.bzl", "CC_OVERRIDE_ATTRS", "make_override_extension")
load("//pycross/private/build/rules:cmake_build.bzl", _cmake_build = "cmake_build")

cmake_build = _cmake_build

cmake = make_override_extension("cmake", "cmake_build", CC_OVERRIDE_ATTRS)
