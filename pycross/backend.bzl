"""Public API for pycross backend module authors.

This module provides the building blocks needed to implement custom
wheel-building rules and override extensions that integrate with
rules_pycross.
"""

load(
    "//pycross/private:lock_attrs.bzl",
    _BUILD_SYSTEM_ATTRS = "BUILD_SYSTEM_ATTRS",
    _CC_BUILD_SYSTEM_ATTRS = "CC_BUILD_SYSTEM_ATTRS",
    _CC_OVERRIDE_ATTRS = "CC_OVERRIDE_ATTRS",
    _CORE_OVERRIDE_ATTRS = "CORE_OVERRIDE_ATTRS",
)
load(
    "//pycross/private:override_helpers.bzl",
    _create_overrides_repo = "create_overrides_repo",
    _encode_build_system_attrs = "encode_build_system_attrs",
    _make_override_extension = "make_override_extension",
    _merge_backend_overrides = "merge_backend_overrides",
)
load(
    "//pycross/private:providers.bzl",
    _PycrossExtractedWheelInfo = "PycrossExtractedWheelInfo",
    _PycrossPackageInfo = "PycrossPackageInfo",
)
load(
    "//pycross/private/build:resource_sets.bzl",
    _get_resource_set = "get_resource_set",
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
    _PycrossExtractedToolInfo = "PycrossExtractedToolInfo",
    _extract_wheel_tools = "extract_wheel_tools",
    _make_wheel_tool_aspect = "make_wheel_tool_aspect",
    _register_bin_extract_action = "register_bin_extract_action",
)
load(
    "//pycross/private/build/rules:common_attrs.bzl",
    _CC_BUILD_ATTRS = "CC_BUILD_ATTRS",
    _CC_FRAGMENTS = "CC_FRAGMENTS",
    _CC_TOOLCHAINS = "CC_TOOLCHAINS",
    _CC_TOOLCHAIN_ATTRS = "CC_TOOLCHAIN_ATTRS",
    _COMMON_BUILD_ATTRS = "COMMON_BUILD_ATTRS",
    _COMMON_TOOLCHAINS = "COMMON_TOOLCHAINS",
    _REPAIR_BUILD_ATTRS = "REPAIR_BUILD_ATTRS",
    _TOOL_EXTRACT_ATTRS = "TOOL_EXTRACT_ATTRS",
    _defer_build_error = "defer_build_error",
    _get_unzipped_wheel = "get_unzipped_wheel",
    _group_tool_deps = "group_tool_deps",
    _resolve_path_tools = "resolve_path_tools",
    _run_wheel_build = "run_wheel_build",
)

# Providers
PycrossExtractedToolInfo = _PycrossExtractedToolInfo
PycrossExtractedWheelInfo = _PycrossExtractedWheelInfo
PycrossPackageInfo = _PycrossPackageInfo

# Transition
pycross_exec_platform_transition = _pycross_exec_platform_transition

# Actions & tool extraction
extract_cc_layer = _extract_cc_layer
extract_wheel_tools = _extract_wheel_tools
make_wheel_tool_aspect = _make_wheel_tool_aspect
register_pep517_action = _register_pep517_action
register_repair_action = _register_repair_action
register_bin_extract_action = _register_bin_extract_action
run_wheel_build = _run_wheel_build

# Attribute dictionaries & toolchains
COMMON_BUILD_ATTRS = _COMMON_BUILD_ATTRS
COMMON_TOOLCHAINS = _COMMON_TOOLCHAINS
CC_BUILD_ATTRS = _CC_BUILD_ATTRS
CC_TOOLCHAIN_ATTRS = _CC_TOOLCHAIN_ATTRS
CC_TOOLCHAINS = _CC_TOOLCHAINS
CC_FRAGMENTS = _CC_FRAGMENTS
REPAIR_BUILD_ATTRS = _REPAIR_BUILD_ATTRS
TOOL_EXTRACT_ATTRS = _TOOL_EXTRACT_ATTRS

# Utilities
defer_build_error = _defer_build_error
get_resource_set = _get_resource_set
get_unzipped_wheel = _get_unzipped_wheel
group_tool_deps = _group_tool_deps
resolve_path_tools = _resolve_path_tools

# Override extension helpers
make_override_extension = _make_override_extension
merge_backend_overrides = _merge_backend_overrides
create_overrides_repo = _create_overrides_repo
encode_build_system_attrs = _encode_build_system_attrs
BUILD_SYSTEM_ATTRS = _BUILD_SYSTEM_ATTRS
CC_BUILD_SYSTEM_ATTRS = _CC_BUILD_SYSTEM_ATTRS
CORE_OVERRIDE_ATTRS = _CORE_OVERRIDE_ATTRS
CC_OVERRIDE_ATTRS = _CC_OVERRIDE_ATTRS
