"""Public API for pycross backend module authors.

This module provides the building blocks needed to implement custom
wheel-building rules and override extensions that integrate with
rules_pycross.
"""

load(
    "//pycross/private:providers.bzl",
    _PycrossExtractedWheelInfo = "PycrossExtractedWheelInfo",
    _PycrossPackageInfo = "PycrossPackageInfo",
    _PycrossWheelInfo = "PycrossWheelInfo",
)
load(
    "//pycross/private/build:transitions.bzl",
    _pycross_exec_platform_transition = "pycross_exec_platform_transition",
)
load(
    "//pycross/private/build/actions:cc_layer.bzl",
    _extract_cc_layer = "extract_cc_layer",
)
load(
    "//pycross/private/build/actions:pep517_action.bzl",
    _register_pep517_action = "register_pep517_action",
)
load(
    "//pycross/private/build/actions:repair_action.bzl",
    _register_repair_action = "register_repair_action",
)
load(
    "//pycross/private/build/actions:tool_extract.bzl",
    _register_bin_extract_action = "register_bin_extract_action",
)
load(
    "//pycross/private/build/rules:common_attrs.bzl",
    _CC_BUILD_ATTRS = "CC_BUILD_ATTRS",
    _CC_FRAGMENTS = "CC_FRAGMENTS",
    _CC_TOOLCHAINS = "CC_TOOLCHAINS",
    _CC_TOOLCHAIN_ATTRS = "CC_TOOLCHAIN_ATTRS",
    _COMMON_BUILD_ATTRS = "COMMON_BUILD_ATTRS",
    _get_unzipped_wheel = "get_unzipped_wheel",
    _get_wheel_file = "get_wheel_file",
    _group_tool_deps = "group_tool_deps",
)
load(
    "//pycross/private/bzlmod:override_helpers.bzl",
    _create_overrides_repo = "create_overrides_repo",
    _encode_build_system_attrs = "encode_build_system_attrs",
    _make_override_extension = "make_override_extension",
)
load(
    "//pycross/private/bzlmod:sdist_repo.bzl",
    _SDIST_REPO_ATTRS = "SDIST_REPO_ATTRS",
    _sdist_repo_common = "sdist_repo_common",
)

# Providers
PycrossWheelInfo = _PycrossWheelInfo
PycrossExtractedWheelInfo = _PycrossExtractedWheelInfo
PycrossPackageInfo = _PycrossPackageInfo

# Transition
pycross_exec_platform_transition = _pycross_exec_platform_transition

# Actions
extract_cc_layer = _extract_cc_layer
register_pep517_action = _register_pep517_action
register_repair_action = _register_repair_action
register_bin_extract_action = _register_bin_extract_action

# Attribute dictionaries
COMMON_BUILD_ATTRS = _COMMON_BUILD_ATTRS
CC_BUILD_ATTRS = _CC_BUILD_ATTRS
CC_TOOLCHAIN_ATTRS = _CC_TOOLCHAIN_ATTRS
CC_TOOLCHAINS = _CC_TOOLCHAINS
CC_FRAGMENTS = _CC_FRAGMENTS

# Utilities
get_unzipped_wheel = _get_unzipped_wheel
get_wheel_file = _get_wheel_file
group_tool_deps = _group_tool_deps

# Sdist repo helpers
SDIST_REPO_ATTRS = _SDIST_REPO_ATTRS
sdist_repo_common = _sdist_repo_common

# Override extension helpers
make_override_extension = _make_override_extension
create_overrides_repo = _create_overrides_repo
encode_build_system_attrs = _encode_build_system_attrs
