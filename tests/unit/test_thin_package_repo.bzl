"""Tests for _pin_build from thin_package_repo.bzl"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:package_repo.bzl", "backend_tool_deps_labels_for_testing", "overlapping_rivals_for_testing", "run_package_repo_hooks_for_testing")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:thin_package_repo.bzl",
    "cargo_build_for_testing",
    "collect_variants_for_testing",
    "flag_values_for_testing",
    "is_platform_specific_for_testing",
    "modules_mapping_deps_for_testing",
    "packages_bzl_for_testing",
    "pin_build_for_testing",
    "pin_versions_for_testing",
    "render_maybe_build_for_testing",
    "render_transition_bzl_for_testing",
    "requirements_bzl_for_testing",
    "transition_settings_for_testing",
    "variant_fallbacks_for_testing",
    "variants_build_for_testing",
)

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "coerce_transition_values", "marker_evaluator_name", "split_setting_value", "url_filename")

# ── Test: no platform → non-transitioning proxies ──────────────────

# buildifier: disable=unused-variable
def _test_pin_build_no_transition_impl(env, target):
    """Without target_platform, should use pycross_library_proxy / pycross_file_proxy."""
    res = pin_build_for_testing(
        target_name = "numpy",
        pin_target_dict = {"": "numpy@1.26.0"},
        workspace_repo = "my_workspace",
    ).build

    # Should load the non-transitioning rules
    env.expect.that_bool("pycross_library_proxy" in res).equals(True)
    env.expect.that_bool("pycross_file_proxy" in res).equals(True)

    # Should NOT have transitioning variants
    env.expect.that_bool("pycross_transitioning_library_proxy" not in res).equals(True)
    env.expect.that_bool("pycross_transitioning_file_proxy" not in res).equals(True)

    # Should NOT have a platform line
    env.expect.that_bool("platform =" not in res).equals(True)

    # Should have the package alias
    env.expect.that_bool('name = "numpy"' in res).equals(True)

def _test_pin_build_no_transition(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_no_transition_impl)

# ── Test: with platform → transitioning proxies ────────────────────

# buildifier: disable=unused-variable
def _test_pin_build_with_platform_impl(env, target):
    """With target_platform, should use pycross_transitioning_library_proxy / pycross_transitioning_file_proxy."""
    res = pin_build_for_testing(
        target_name = "numpy",
        pin_target_dict = {"": "numpy@1.26.0"},
        workspace_repo = "my_workspace",
        target_platform = "@my//platform:linux",
    ).build

    # Should load the transitioning rules
    env.expect.that_bool("pycross_transitioning_library_proxy" in res).equals(True)
    env.expect.that_bool("pycross_transitioning_file_proxy" in res).equals(True)

    # Should NOT have the non-transitioning variants as standalone rule calls
    # (they may appear as substrings of the transitioning names, so check the load line)
    load_line = [line for line in res.split("\n") if line.startswith("load(")][0]
    env.expect.that_bool("pycross_transitioning_library_proxy" in load_line).equals(True)
    env.expect.that_bool("pycross_transitioning_file_proxy" in load_line).equals(True)

    # Should have platform lines
    env.expect.that_bool('platform = "@my//platform:linux"' in res).equals(True)

def _test_pin_build_with_platform(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_with_platform_impl)

# ── Test: load statements differ based on platform ─────────────────

# buildifier: disable=unused-variable
def _test_pin_build_transition_loads_impl(env, target):
    """The load statement should import transitioning variants iff target_platform is set."""
    res_no_platform = pin_build_for_testing(
        target_name = "foo",
        pin_target_dict = {"": "foo@1.0"},
        workspace_repo = "ws",
    ).build
    res_with_platform = pin_build_for_testing(
        target_name = "foo",
        pin_target_dict = {"": "foo@1.0"},
        workspace_repo = "ws",
        target_platform = "//:my_platform",
    ).build

    # Without platform: load should have non-transitioning
    load_no = [line for line in res_no_platform.split("\n") if line.startswith("load(")][0]
    env.expect.that_bool('"pycross_library_proxy"' in load_no).equals(True)
    env.expect.that_bool('"pycross_file_proxy"' in load_no).equals(True)
    env.expect.that_bool("transitioning" not in load_no).equals(True)

    # With platform: load should have transitioning
    load_with = [line for line in res_with_platform.split("\n") if line.startswith("load(")][0]
    env.expect.that_bool('"pycross_transitioning_library_proxy"' in load_with).equals(True)
    env.expect.that_bool('"pycross_transitioning_file_proxy"' in load_with).equals(True)

def _test_pin_build_transition_loads(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_transition_loads_impl)

# ── Test: extras with platform use transitioning proxy ─────────────

# buildifier: disable=unused-variable
def _test_pin_build_extras_with_platform_impl(env, target):
    """Extra targets should also use the transitioning variant and include platform."""
    res = pin_build_for_testing(
        target_name = "numpy",
        pin_target_dict = {"": "numpy@1.26.0"},
        workspace_repo = "my_workspace",
        extras_dict = {"gpu": {"": "numpy[gpu]@1.26.0"}},
        target_platform = "@my//platform:linux",
    ).build

    # Extra target should exist
    env.expect.that_bool('name = "[gpu]"' in res).equals(True)

    # Should use transitioning lib proxy for extras
    env.expect.that_bool("pycross_transitioning_library_proxy" in res).equals(True)

    # The extra target block should include platform
    # Count platform occurrences: pkg, wheel, dist_info, and gpu extra = at least 4
    platform_count = res.count('platform = "@my//platform:linux"')
    env.expect.that_bool(platform_count >= 4).equals(True)

def _test_pin_build_extras_with_platform(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_extras_with_platform_impl)

# ── Test: sdist with platform uses transitioning file proxy ────────

# buildifier: disable=unused-variable
def _test_pin_build_sdist_with_platform_impl(env, target):
    """When package has sdist_file and target_platform is set, sdist proxy should use transitioning file proxy."""
    res = pin_build_for_testing(
        target_name = "numpy",
        pin_target_dict = {"": "numpy@1.26.0"},
        sdist_target_dict = {"": "numpy@1.26.0"},
        workspace_repo = "my_workspace",
        target_platform = "@my//platform:linux",
    ).build

    # Should have the sdist target
    env.expect.that_bool('name = "sdist"' in res).equals(True)

    # sdist should use transitioning file proxy
    env.expect.that_bool("pycross_transitioning_file_proxy" in res).equals(True)

    # sdist block should include platform
    sdist_section = res.split('name = "sdist"')[1].split(")")[0]
    env.expect.that_bool("@my//platform:linux" in sdist_section).equals(True)

def _test_pin_build_sdist_with_platform(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_sdist_with_platform_impl)

# ── Test: variants with platform ───────────────────────────────────

# buildifier: disable=unused-variable
def _test_pin_build_variants_with_platform_impl(env, target):
    """Combines variants (has_aggregated_variant=True, non-trivial pin_target_dict) with platform transition."""
    res_struct = pin_build_for_testing(
        target_name = "numpy",
        pin_target_dict = {
            "cpu": "numpy@1.26.0",
            "gpu": "numpy@1.26.0+gpu",
        },
        workspace_repo = "my_workspace",
        has_aggregated_variant = True,
        extras_dict = {"extra1": {"cpu": "numpy[extra1]@1.26.0", "gpu": "numpy[extra1]@1.26.0+gpu"}},
        target_platform = "@my//platform:linux",
    )
    res = res_struct.build + "\n" + (res_struct.actual_build or "")

    # Should use select for variants
    env.expect.that_bool("select({" in res).equals(True)

    # Should reference the variant config settings
    env.expect.that_bool("is_cpu" in res).equals(True)
    env.expect.that_bool("is_gpu" in res).equals(True)

    # Should use transitioning proxies
    env.expect.that_bool("pycross_transitioning_library_proxy" in res).equals(True)

    # Should have platform on every proxy target
    env.expect.that_bool('platform = "@my//platform:linux"' in res).equals(True)

    # With has_aggregated_variant, the pkg actual should use [_all_]
    env.expect.that_bool("[_all_]@" in res).equals(True)

    # With has_aggregated_variant + extras, the [] base target should use lib_rule (not alias)
    env.expect.that_bool('name = "[]"' in res).equals(True)

    # Extras with variants should also use select in actual_build
    extra_section = (res_struct.actual_build or "").split('name = "extra_extra1"')[1].split(")")[0]
    env.expect.that_bool("select({" in extra_section).equals(True)

    # Variant defaults come from the repo's transition, not from //conditions:default.
    env.expect.that_bool('"//conditions:default": ":numpy@1.26.0' in res).equals(False)

def _test_pin_build_variants_with_platform(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_variants_with_platform_impl)

# ── Test: no platform, no sdist → minimal output ──────────────────

# buildifier: disable=unused-variable
def _test_pin_build_basic_structure_impl(env, target):
    """Basic structure: alias, pkg proxy, wheel proxy, dist_info proxy, data alias."""
    res = pin_build_for_testing(
        target_name = "requests",
        pin_target_dict = {"": "requests@2.31.0"},
        workspace_repo = "ws",
    ).build

    # Should have the top-level alias
    env.expect.that_bool('name = "requests"' in res).equals(True)
    env.expect.that_bool('actual = ":pkg"' in res).equals(True)

    # Should have pkg proxy pointing to lock target
    env.expect.that_bool('name = "pkg"' in res).equals(True)
    env.expect.that_bool('"@ws//_lock:requests@2.31.0"' in res).equals(True)

    # Should have wheel proxy pointing to wheel target
    env.expect.that_bool('name = "wheel"' in res).equals(True)
    env.expect.that_bool('"@ws//_wheel:requests@2.31.0"' in res).equals(True)

    # Should have dist_info proxy
    env.expect.that_bool('name = "dist_info"' in res).equals(True)
    env.expect.that_bool('"@ws//_lock:_dist_info_requests@2.31.0"' in res).equals(True)

    # Should have data alias
    env.expect.that_bool('name = "data"' in res).equals(True)

    # Should NOT have sdist target
    env.expect.that_bool("sdist" not in res).equals(True)

def _test_pin_build_basic_structure(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_basic_structure_impl)

# ── Test: transition_bzl → per-package uses transitioning rules from generated bzl ─

# buildifier: disable=unused-variable
def _test_pin_build_with_transition_bzl_impl(env, target):
    """When transition_bzl is set, per-package BUILD uses transitioning rules loaded from the generated file."""
    result = pin_build_for_testing(
        target_name = "numpy",
        pin_target_dict = {"": "numpy@1.26.0"},
        sdist_target_dict = {"": "numpy@1.26.0"},
        workspace_repo = "my_workspace",
        extras_dict = {"gpu": {"": "numpy[gpu]@1.26.0"}},
        target_platform = "//:_internal_platform",
        transition_bzl = "//:_transition.bzl",
    )
    res = result.build

    # Should load transitioning rules from the generated _transition.bzl
    load_line = [line for line in res.split("\n") if line.startswith("load(")][0]
    env.expect.that_bool('"//:_transition.bzl"' in load_line).equals(True)
    env.expect.that_bool('"pycross_transitioning_library_proxy"' in load_line).equals(True)
    env.expect.that_bool('"pycross_transitioning_file_proxy"' in load_line).equals(True)

    # Should have platform = lines (transitioning rules require platform)
    env.expect.that_bool('platform = "//:_internal_platform"' in res).equals(True)

    # Should still have the expected targets
    env.expect.that_bool('name = "pkg"' in res).equals(True)
    env.expect.that_bool('name = "wheel"' in res).equals(True)
    env.expect.that_bool('name = "dist_info"' in res).equals(True)
    env.expect.that_bool('name = "sdist"' in res).equals(True)
    env.expect.that_bool('name = "[gpu]"' in res).equals(True)

    # With single-entry target dicts, there should be no __actual package
    env.expect.that_bool(result.actual_build == None).equals(True)

def _test_pin_build_with_transition_bzl(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_with_transition_bzl_impl)

# ── Test: transition_bzl with variants → intermediate select aliases ─

# buildifier: disable=unused-variable
def _test_pin_build_transition_bzl_variants_impl(env, target):
    """When transition_bzl is set and pins have variants, intermediate alias targets are emitted for select()."""
    result = pin_build_for_testing(
        target_name = "numpy",
        pin_target_dict = {
            "cpu": "numpy@1.26.0",
            "gpu": "numpy@1.26.0+gpu",
        },
        workspace_repo = "my_workspace",
        has_aggregated_variant = True,
        extras_dict = {"extra1": {"cpu": "numpy[extra1]@1.26.0", "gpu": "numpy[extra1]@1.26.0+gpu"}},
        target_platform = "//:_internal_platform",
        transition_bzl = "//:_transition.bzl",
    )
    res = result.build
    actual = result.actual_build

    # Should load from _transition.bzl
    load_line = [line for line in res.split("\n") if line.startswith("load(")][0]
    env.expect.that_bool('"//:_transition.bzl"' in load_line).equals(True)

    # Should use transitioning proxies
    env.expect.that_bool("pycross_transitioning_library_proxy" in res).equals(True)

    # Main BUILD should NOT contain the select aliases (they live in __actual package)
    env.expect.that_bool("select({" not in res).equals(True)

    # Main BUILD proxy targets should reference __actual package
    env.expect.that_bool('//__actual/numpy:pkg",' in res).equals(True)

    # __actual package should exist and contain the select aliases
    env.expect.that_bool(actual != None).equals(True)
    env.expect.that_bool('name = "pkg"' in actual).equals(True)
    env.expect.that_bool('name = "wheel"' in actual).equals(True)
    env.expect.that_bool('name = "dist_info"' in actual).equals(True)
    env.expect.that_bool('name = "all"' in actual).equals(True)
    env.expect.that_bool('name = "extra_extra1"' in actual).equals(True)
    env.expect.that_bool("select({" in actual).equals(True)

    # __actual package should have restricted visibility
    env.expect.that_bool('"//numpy:__pkg__"' in actual).equals(True)

    # Should have platform on proxy targets in main BUILD
    env.expect.that_bool('platform = "//:_internal_platform"' in res).equals(True)

def _test_pin_build_transition_bzl_variants(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_transition_bzl_variants_impl)

# ── Test: marked build targets and extras use maybe aliases ─────────

# buildifier: disable=unused-variable
def _test_requirements_bzl_root_marker_aliases_impl(env, target):
    mock_rctx = struct(name = "my_repo")
    pins = {
        "foo": {"": "foo@1.0"},
        "foo[linux-extra]": {"": "foo[linux-extra]@1.0"},
    }
    packages = {
        "foo@1.0": {"build_target": "@//custom:foo"},
        "foo[linux-extra]@1.0": {
            "build_target": "@//custom:foo_extra",
            "availability_markers": ["sys_platform == \"linux\""],
        },
    }
    res = requirements_bzl_for_testing(mock_rctx, pins, packages)

    # The unconditional base remains unconditional. Only the marked extra
    # selects the empty library away on incompatible platforms.
    env.expect.that_bool("@@my_repo//foo\"" in res).equals(True)
    env.expect.that_bool("@@my_repo//foo:maybe" not in res).equals(True)
    env.expect.that_bool("@@my_repo//foo:[linux-extra]_maybe" in res).equals(True)

def _test_requirements_bzl_root_marker_aliases(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_requirements_bzl_root_marker_aliases_impl)

# ── Test suite ─────────────────────────────────────────────────────

# ── Test: is_platform_specific ─────────────────────────────────────

# buildifier: disable=unused-variable
def _test_is_platform_specific_impl(env, target):
    """Verify is_platform_specific correctly classifies packages."""

    # Package with wheels but no sdist → platform-specific
    env.expect.that_bool(is_platform_specific_for_testing({
        "wheel_candidates": [{"filename": "pkg-1.0-cp310-win_amd64.whl"}],
    })).equals(True)

    # Package with universal py3-none-any (or py2.py3-none-any, or with build tag)
    # wheel and no availability_markers → NOT platform-specific even without sdist
    env.expect.that_bool(is_platform_specific_for_testing({
        "wheel_candidates": [{"filename": "pkg-1.0-py3-none-any.whl"}],
    })).equals(False)
    env.expect.that_bool(is_platform_specific_for_testing({
        "wheel_candidates": [{"filename": "pkg-1.0-py2.py3-none-any.whl"}],
    })).equals(False)
    env.expect.that_bool(is_platform_specific_for_testing({
        "wheel_candidates": [{"filename": "pkg-1.0-1-py3-none-any.whl"}],
    })).equals(False)

    # Malformed 7-part filename does not take the universal fast path
    env.expect.that_bool(is_platform_specific_for_testing({
        "wheel_candidates": [{"filename": "bad-pkg-1.0-1-py3-none-any.whl"}],
    })).equals(True)

    # Universal wheel WITH availability_markers → still platform-specific
    env.expect.that_bool(is_platform_specific_for_testing({
        "wheel_candidates": [{"filename": "pkg-1.0-py3-none-any.whl"}],
        "availability_markers": ["sys_platform != 'win32'"],
    })).equals(True)

    # Version-constrained pure wheel (py311-none-any) → platform-specific
    env.expect.that_bool(is_platform_specific_for_testing({
        "wheel_candidates": [{"filename": "pkg-1.0-py311-none-any.whl"}],
    })).equals(True)

    # Package with wheels AND sdist → NOT platform-specific
    env.expect.that_bool(is_platform_specific_for_testing({
        "wheel_candidates": [{"filename": "pkg-1.0-cp310-win_amd64.whl"}],
        "sdist_file": {"key": "sdist_key"},
    })).equals(False)

    # Package with wheels AND build_target → NOT platform-specific
    env.expect.that_bool(is_platform_specific_for_testing({
        "wheel_candidates": [{"filename": "pkg-1.0-cp310-win_amd64.whl"}],
        "build_target": "@some//:target",
    })).equals(False)

    # Package with no wheel_candidates (extras wrapper) → NOT platform-specific
    env.expect.that_bool(is_platform_specific_for_testing({})).equals(False)

def _test_is_platform_specific(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_is_platform_specific_impl)

# ── Test: _requirements_bzl with maybe aliases ─────────────────────

# buildifier: disable=unused-variable
def _test_requirements_bzl_maybe_aliases_impl(env, target):
    """Verify all_requirements uses _maybe_ entries for platform-specific packages."""
    mock_rctx = struct(name = "my_repo")
    pins = {
        "numpy": {"": "numpy@1.26.0"},
        "pywin32": {"": "pywin32@312"},
    }
    packages = {
        "numpy@1.26.0": {
            "wheel_candidates": [{"filename": "numpy-1.26.0-cp310-manylinux.whl"}],
            "sdist_file": {"key": "numpy_sdist"},
        },
        "pywin32@312": {
            "wheel_candidates": [{"filename": "pywin32-312-cp310-win_amd64.whl"}],
            # No sdist → platform-specific
        },
    }
    res = requirements_bzl_for_testing(mock_rctx, pins, packages)

    # numpy has sdist → should be unconditional
    env.expect.that_bool("@@my_repo//numpy" in res).equals(True)
    env.expect.that_bool("@@my_repo//numpy:maybe" not in res).equals(True)

    # pywin32 has no sdist → should use per-package :maybe target
    env.expect.that_bool("@@my_repo//pywin32:maybe" in res).equals(True)

def _test_requirements_bzl_maybe_aliases(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_requirements_bzl_maybe_aliases_impl)

# ── Test: _requirements_bzl all unconditional ──────────────────────

# buildifier: disable=unused-variable
def _test_requirements_bzl_all_unconditional_impl(env, target):
    """When all packages have sdist, no _maybe_ entries should appear."""
    mock_rctx = struct(name = "my_repo")
    pins = {
        "foo": {"": "foo@1.0"},
        "bar": {"": "bar@2.0"},
    }
    packages = {
        "foo@1.0": {
            "wheel_candidates": [{"filename": "foo-1.0-py3-none-any.whl"}],
            "sdist_file": {"key": "foo_sdist"},
        },
        "bar@2.0": {
            "wheel_candidates": [{"filename": "bar-2.0-py3-none-any.whl"}],
            "sdist_file": {"key": "bar_sdist"},
        },
    }
    res = requirements_bzl_for_testing(mock_rctx, pins, packages)

    env.expect.that_bool("_maybe_" in res).equals(False)
    env.expect.that_bool("@@my_repo//foo" in res).equals(True)
    env.expect.that_bool("@@my_repo//bar" in res).equals(True)

def _test_requirements_bzl_all_unconditional(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_requirements_bzl_all_unconditional_impl)

# ── Test: _requirements_bzl with extra-bearing pins ────────────────

# buildifier: disable=unused-variable
def _test_requirements_bzl_extra_pins_impl(env, target):
    """Extra-bearing pins produce distinct :[extra] entries in all_requirements."""
    mock_rctx = struct(name = "my_repo")
    pins = {
        "foo[bar]": {"": "foo[bar]@1.0"},
        "foo[baz]": {"": "foo[baz]@1.0"},
    }
    packages = {
        "foo@1.0": {
            "wheel_candidates": [{"filename": "foo-1.0-py3-none-any.whl"}],
            "sdist_file": {"key": "foo_sdist"},
        },
    }
    res = requirements_bzl_for_testing(mock_rctx, pins, packages)

    # Both extras should appear as separate entries.
    env.expect.that_bool("@@my_repo//foo:[bar]" in res).equals(True)
    env.expect.that_bool("@@my_repo//foo:[baz]" in res).equals(True)

def _test_requirements_bzl_extra_pins(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_requirements_bzl_extra_pins_impl)

# ── Test: multi-branch maybe and [extra]_maybe aliases ─────────────

# buildifier: disable=unused-variable
def _test_pin_build_multi_branch_maybe_impl(env, target):
    """Multi-branch pins emit per-branch availability helpers and branch-aware maybe select()."""
    res = pin_build_for_testing(
        target_name = "foo",
        pin_target_dict = {
            "res_foo_1_0": "foo@1.0",
            "res_foo_2_0": "foo@2.0",
        },
        workspace_repo = "ws",
        extras_dict = {
            "bar": {
                "res_foo_1_0": "foo[bar]@1.0",
                "res_foo_2_0": "foo[bar]@2.0",
            },
        },
        maybe_available_keys = ["foo@1.0"],
        extras_maybe_keys = {"bar": ["foo[bar]@1.0", "foo[bar]@2.0"]},
    ).build

    # Base maybe: foo@1.0 is platform-specific (uses helper _maybe_foo_1_0),
    # while foo@2.0 is unconditional (maps directly to :pkg).
    env.expect.that_bool('name = "_maybe_foo_1_0"' in res).equals(True)
    env.expect.that_bool('"@ws//_lock:_available_foo@1.0": ":pkg"' in res).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_foo_1_0": ":_maybe_foo_1_0"' in res).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_foo_2_0": ":pkg"' in res).equals(True)

    # Extra maybe: both foo[bar]@1.0 and foo[bar]@2.0 are platform-specific.
    env.expect.that_bool('name = "_maybe_extra_bar_foo_bar__1_0"' in res).equals(True)
    env.expect.that_bool('name = "_maybe_extra_bar_foo_bar__2_0"' in res).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_foo_1_0": ":_maybe_extra_bar_foo_bar__1_0"' in res).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_foo_2_0": ":_maybe_extra_bar_foo_bar__2_0"' in res).equals(True)

def _test_pin_build_multi_branch_maybe(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_multi_branch_maybe_impl)

# buildifier: disable=unused-variable
def _test_flag_values_impl(env, target):
    """Repeated flags collect values in order; a bare flag means True; no comma splitting."""
    res = flag_values_for_testing([
        "--//command_line_option:copt=-Wl,-rpath,/x",
        "--@ws//_variants:extra_a",
        "--//command_line_option:copt=-O2",
        "--//command_line_option:compilation_mode=opt",
    ])
    env.expect.that_dict(res).contains_exactly({
        "//command_line_option:copt": ["-Wl,-rpath,/x", "-O2"],
        "@ws//_variants:extra_a": ["True"],
        "//command_line_option:compilation_mode": ["opt"],
    })

def _test_flag_values(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_flag_values_impl)

# buildifier: disable=unused-variable
def _test_transition_value_coercion_impl(env, target):
    """settings values split on commas for list settings only; flags lists are kept per entry."""
    env.expect.that_collection(split_setting_value([], "-O2,-g")).contains_exactly(["-O2", "-g"]).in_order()
    env.expect.that_collection(split_setting_value([], "")).contains_exactly([])
    env.expect.that_collection(split_setting_value("", "a,b")).contains_exactly(["a,b"])
    env.expect.that_collection(coerce_transition_values([], ["-Wl,-rpath,/x", "-O2"])).contains_exactly(["-Wl,-rpath,/x", "-O2"]).in_order()
    env.expect.that_str(coerce_transition_values("", ["a,b"])).equals("a,b")
    env.expect.that_bool(coerce_transition_values(False, ["True", "0"])).equals(False)
    env.expect.that_int(coerce_transition_values(0, ["3"])).equals(3)

def _test_transition_value_coercion(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_transition_value_coercion_impl)

# buildifier: disable=unused-variable
def _test_requirements_bzl_extra_of_platform_specific_impl(env, target):
    """Extras of a wheel-only package use the [extra]_maybe target in all_requirements."""
    mock_rctx = struct(name = "my_repo")
    pins = {"plat[extra]": {"": "plat[extra]@1.0"}}
    packages = {
        "plat@1.0": {"wheel_candidates": [{"filename": "plat-1.0-cp310-win_amd64.whl"}]},
        "plat[extra]@1.0": {},
    }
    res = requirements_bzl_for_testing(mock_rctx, pins, packages)
    env.expect.that_str(res).contains("@@my_repo//plat:[extra]_maybe")

# buildifier: disable=unused-variable
def _test_requirements_bzl_testonly_split_impl(env, target):
    """Testonly pins go to all_testonly_requirements, not all_requirements."""
    mock_rctx = struct(name = "my_repo")
    pins = {
        "foo": {"": "foo@1.0"},
        "pytest": {"": "pytest@8.0"},
        "pytest[toml]": {"": "pytest[toml]@8.0"},
    }
    packages = {
        "foo@1.0": {"sdist_file": {"key": "foo_sdist"}},
        "pytest@8.0": {"sdist_file": {"key": "pytest_sdist"}},
    }
    res = requirements_bzl_for_testing(mock_rctx, pins, packages, {"pytest": True})
    all_reqs, testonly_reqs = res.split("all_requirements = [")[1].split("all_testonly_requirements = [")
    env.expect.that_str(all_reqs).contains("@@my_repo//foo")
    env.expect.that_bool("pytest" in all_reqs).equals(False)
    env.expect.that_str(testonly_reqs).contains('"@@my_repo//pytest"')
    env.expect.that_str(testonly_reqs).contains('"@@my_repo//pytest:[toml]"')

def _test_requirements_bzl_testonly_split(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_requirements_bzl_testonly_split_impl)

def _test_requirements_bzl_extra_of_platform_specific(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_requirements_bzl_extra_of_platform_specific_impl)

# buildifier: disable=unused-variable
def _test_pin_build_aggregated_only_branches_with_extras_impl(env, target):
    """has_aggregated_variant uses [_all_] only for fork branches that have extras."""
    res = pin_build_for_testing(
        target_name = "foo",
        pin_target_dict = {
            "res_foo_1_0": "foo@1.0",
            "res_foo_2_0": "foo@2.0",
        },
        workspace_repo = "ws",
        has_aggregated_variant = True,
        aggregated_keys = {"foo@1.0": True},
    ).build
    env.expect.that_str(res).contains('"@ws//_lock:is_res_foo_1_0": "@ws//_lock:foo[_all_]@1.0"')
    env.expect.that_str(res).contains('"@ws//_lock:is_res_foo_2_0": "@ws//_lock:foo@2.0"')

def _test_pin_build_aggregated_only_branches_with_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_aggregated_only_branches_with_extras_impl)

# ── Test: multi-branch sdist and _packages.bzl ─────────────────────

# buildifier: disable=unused-variable
def _test_pin_build_multi_branch_sdist_impl(env, target):
    """When only a non-first branch has an sdist, :sdist and PACKAGES.has_sdist still reflect it."""
    pin_target_dict = {
        "res_foo_1_0": "foo@1.0",
        "res_foo_2_0": "foo@2.0",
    }
    packages = {
        "foo@1.0": {
            "wheel_candidates": [{"filename": "foo-1.0-py3-none-any.whl"}],
        },
        "foo@2.0": {
            "wheel_candidates": [{"filename": "foo-2.0-py3-none-any.whl"}],
            "sdist_file": {"key": "foo_2_sdist"},
        },
    }
    res = pin_build_for_testing(
        target_name = "foo",
        pin_target_dict = pin_target_dict,
        workspace_repo = "ws",
        sdist_target_dict = {"res_foo_2_0": "foo@2.0"},
    ).build

    env.expect.that_bool('name = "sdist"' in res).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_foo_1_0": "@rules_pycross//pycross/private:no_match_error"' in res).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_foo_2_0": "@ws//_sdist:foo@2.0"' in res).equals(True)
    env.expect.that_bool('"//conditions:default": "@rules_pycross//pycross/private:no_match_error"' in res).equals(True)
    env.expect.that_bool('"@ws//_sdist:foo@1.0"' not in res).equals(True)

    pkgs_bzl = packages_bzl_for_testing(
        {"foo": {"base_target": pin_target_dict, "extras": {}}},
        packages,
    )
    env.expect.that_bool("has_sdist = True," in pkgs_bzl).equals(True)

def _test_pin_build_multi_branch_sdist(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_multi_branch_sdist_impl)

# ── Test: multi-branch _cargo/BUILD.bazel ──────────────────────────

# buildifier: disable=unused-variable
def _test_cargo_build_multi_branch_impl(env, target):
    """_cargo_build uses _target_select across branches with sdist_file and falls back to no_match_error."""
    grouped_pins = {
        "jiter": {
            "base_target": {
                "res_jiter_0_5_0": "jiter@0.5.0",
                "res_jiter_0_6_0": "jiter@0.6.0",
            },
            "extras": {},
        },
        "partial": {
            "base_target": {
                "res_partial_1_0": "partial@1.0",
                "res_partial_2_0": "partial@2.0",
            },
            "extras": {},
        },
    }
    packages = {
        "jiter@0.5.0": {"sdist_file": {"key": "sdist_0_5"}},
        "jiter@0.6.0": {"sdist_file": {"key": "sdist_0_6"}},
        "partial@1.0": {},
        "partial@2.0": {"sdist_file": {"key": "sdist_partial_2"}},
    }
    cargo_bzl = cargo_build_for_testing(
        grouped_pins,
        packages,
        {
            "jiter": {"maturin_build": {}},
            "partial": {"maturin_build": {}},
        },
        "ws",
    )
    env.expect.that_bool(cargo_bzl != None).equals(True)
    env.expect.that_bool("select({" in cargo_bzl).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_jiter_0_5_0": "@ws//_cargo:jiter@0.5.0"' in cargo_bzl).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_jiter_0_6_0": "@ws//_cargo:jiter@0.6.0"' in cargo_bzl).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_partial_1_0": "@rules_pycross//pycross/private:no_match_error"' in cargo_bzl).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_partial_2_0": "@ws//_cargo:partial@2.0"' in cargo_bzl).equals(True)
    env.expect.that_bool('"//conditions:default": "@rules_pycross//pycross/private:no_match_error"' in cargo_bzl).equals(True)

def _test_cargo_build_multi_branch(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cargo_build_multi_branch_impl)

# ── Test: _backend_tool_deps_labels ────────────────────────────────

# buildifier: disable=unused-variable
def _test_backend_tool_deps_labels_impl(env, target):
    """_backend_tool_deps_labels skips extra keys and emits @<build_repo>//<pkg>:pkg labels."""
    packages = {
        "setuptools[core]@68.0.0": {},
        "setuptools@9.0.0": {},
        "setuptools@68.0.0": {},
        "setuptools@75.1.0": {},
        "scikit-build-core@0.10.0": {},
        "wheel[testing]@0.45.0": {},
    }
    labels = backend_tool_deps_labels_for_testing(
        ["setuptools", "scikit-build-core", "wheel", "flit-core"],
        packages,
        "uv__build",
    )
    env.expect.that_collection(labels).contains_exactly([
        "@uv__build//setuptools:pkg",
        "@uv__build//scikit_build_core:pkg",
    ])

def _test_backend_tool_deps_labels(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_backend_tool_deps_labels_impl)

# ── Test: multi-branch pin falls back to no_match_error on uncovered branches ─

# buildifier: disable=unused-variable
def _test_pin_build_multi_branch_no_match_fallback_impl(env, target):
    """Multi-branch pins without a default variant emit //conditions:default -> no_match_error."""
    res = pin_build_for_testing(
        target_name = "setuptools",
        pin_target_dict = {
            "res_setuptools_68_0_0": "setuptools@68.0.0",
            "res_setuptools_75_1_0": "setuptools@75.1.0",
        },
        workspace_repo = "ws",
    ).build

    pkg_section = res.split('name = "pkg"')[1].split(")")[0]
    env.expect.that_bool('"@ws//_lock:is_res_setuptools_68_0_0": "@ws//_lock:setuptools@68.0.0"' in pkg_section).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_setuptools_75_1_0": "@ws//_lock:setuptools@75.1.0"' in pkg_section).equals(True)
    env.expect.that_bool('"//conditions:default": "@rules_pycross//pycross/private:no_match_error"' in pkg_section).equals(True)

    wheel_section = res.split('name = "wheel"')[1].split(")")[0]
    env.expect.that_bool('"//conditions:default": "@rules_pycross//pycross/private:no_match_error"' in wheel_section).equals(True)

def _test_pin_build_multi_branch_no_match_fallback(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_multi_branch_no_match_fallback_impl)

# ── Test: maybe and [extra]_maybe with transitions use __actual ────

# buildifier: disable=unused-variable
def _test_pin_build_maybe_with_transition_impl(env, target):
    """When has_transition is set, :maybe and :[extra]_maybe selects live in __actual/<pkg>."""

    # 1. Single-branch platform-specific pin with target_platform
    single = pin_build_for_testing(
        target_name = "pywin32",
        pin_target_dict = {"": "pywin32@312"},
        workspace_repo = "ws",
        target_platform = "@my//platform:linux",
        maybe_available_keys = ["pywin32@312"],
    )
    env.expect.that_bool("select({" not in single.build).equals(True)
    env.expect.that_bool('name = "maybe"' in single.build).equals(True)
    env.expect.that_bool('actual = "//__actual/pywin32:maybe"' in single.build).equals(True)
    env.expect.that_bool(single.actual_build != None).equals(True)
    env.expect.that_bool('name = "maybe"' in single.actual_build).equals(True)
    env.expect.that_bool('"@ws//_lock:_available_pywin32@312": "@ws//_lock:pywin32@312"' in single.actual_build).equals(True)

    # 2. Multi-branch pin and extra with transition_bzl + target_platform + testonly
    multi = pin_build_for_testing(
        target_name = "foo",
        pin_target_dict = {
            "res_foo_1_0": "foo@1.0",
            "res_foo_2_0": "foo@2.0",
        },
        workspace_repo = "ws",
        extras_dict = {
            "bar": {
                "res_foo_1_0": "foo[bar]@1.0",
                "res_foo_2_0": "foo[bar]@2.0",
            },
        },
        target_platform = "//:_internal_platform",
        transition_bzl = "//:_transition.bzl",
        maybe_available_keys = ["foo@1.0"],
        extras_maybe_keys = {"bar": ["foo[bar]@1.0", "foo[bar]@2.0"]},
        testonly = True,
    )
    env.expect.that_bool("select({" not in multi.build).equals(True)
    env.expect.that_bool('actual = "//__actual/foo:maybe"' in multi.build).equals(True)
    env.expect.that_bool('actual = "//__actual/foo:extra_bar_maybe"' in multi.build).equals(True)

    maybe_section = multi.build.split('name = "maybe"')[1].split(")")[0]
    env.expect.that_bool("testonly = True," in maybe_section).equals(True)
    env.expect.that_bool('platform = "//:_internal_platform"' in maybe_section).equals(True)

    extra_maybe_section = multi.build.split('name = "[bar]_maybe"')[1].split(")")[0]
    env.expect.that_bool("testonly = True," in extra_maybe_section).equals(True)
    env.expect.that_bool('platform = "//:_internal_platform"' in extra_maybe_section).equals(True)

    env.expect.that_bool('name = "_maybe_foo_1_0"' in multi.actual_build).equals(True)
    env.expect.that_bool('"@ws//_lock:_available_foo@1.0": "//__actual/foo:pkg"' in multi.actual_build).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_foo_1_0": ":_maybe_foo_1_0"' in multi.actual_build).equals(True)
    env.expect.that_bool('"@ws//_lock:is_res_foo_2_0": "//__actual/foo:pkg"' in multi.actual_build).equals(True)

    env.expect.that_bool('name = "_maybe_extra_bar_foo_bar__1_0"' in multi.actual_build).equals(True)
    env.expect.that_bool('name = "_maybe_extra_bar_foo_bar__2_0"' in multi.actual_build).equals(True)
    env.expect.that_bool('"@ws//_lock:_available_foo[bar]@1.0": "//__actual/foo:extra_bar"' in multi.actual_build).equals(True)
    env.expect.that_bool('name = "extra_bar_maybe"' in multi.actual_build).equals(True)

def _test_pin_build_maybe_with_transition(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_maybe_with_transition_impl)

# ── Test: unselected variant fallback uses _no_variant_<set> ───────

# buildifier: disable=unused-variable
def _test_pin_build_no_variant_fallback_impl(env, target):
    """Variant pins without a default variant emit _unselected_<set> -> _no_variant_<set> and preserve //conditions:default."""
    no_variant_fallbacks = variant_fallbacks_for_testing({
        "extra_variant-a": ["extra_variant-a_extra_variant-b"],
        "extra_variant-b": ["extra_variant-a_extra_variant-b"],
    })
    res = pin_build_for_testing(
        target_name = "typing_extensions",
        pin_target_dict = {
            "extra_variant-a": "typing-extensions@4.11.0",
            "extra_variant-b": "typing-extensions@4.12.0",
        },
        workspace_repo = "ws",
        no_variant_fallbacks = no_variant_fallbacks,
        maybe_available_keys = ["typing-extensions@4.11.0"],
    ).build

    pkg_section = res.split('name = "pkg"')[1].split(")")[0]
    env.expect.that_bool('"@ws//_lock:is_extra_variant-a": "@ws//_lock:typing-extensions@4.11.0"' in pkg_section).equals(True)
    env.expect.that_bool('"@ws//_lock:is_extra_variant-b": "@ws//_lock:typing-extensions@4.12.0"' in pkg_section).equals(True)
    env.expect.that_bool('"@ws//_lock:_unselected_extra_variant-a_extra_variant-b": "//_variants:_no_variant_extra_variant-a_extra_variant-b"' in pkg_section).equals(True)
    env.expect.that_bool('"//conditions:default": "@rules_pycross//pycross/private:no_match_error"' in pkg_section).equals(True)

    maybe_section = res.split('name = "maybe"')[1].split(")")[0]
    env.expect.that_bool('"@ws//_lock:_unselected_extra_variant-a_extra_variant-b": "//_variants:_no_variant_extra_variant-a_extra_variant-b"' in maybe_section).equals(True)
    env.expect.that_bool('"//conditions:default": "//:_empty_library"' in maybe_section).equals(True)

def _test_pin_build_no_variant_fallback(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_no_variant_fallback_impl)

# ── Test suite ─────────────────────────────────────────────────────

# ── Test: _variants/BUILD.bazel generation ────────────────────────

_SHARED_TEST_VARIANTS = [{
    "items": [
        {"package": "app-a", "kind": "group", "name": "test", "flags": ["group_test", "group_app-a_test"]},
        {"package": "app-b", "kind": "group", "name": "test", "flags": ["group_test", "group_app-b_test"]},
    ],
}]

# buildifier: disable=unused-variable
def _test_variants_build_shared_flag_impl(env, target):
    """A flag covering two items is match_all, and is left out of the no-variant message."""
    info = collect_variants_for_testing(_SHARED_TEST_VARIANTS)
    env.expect.that_dict(info.flags).contains_exactly({
        "group_test": ["group_app-a_test", "group_app-b_test"],
        "group_app-a_test": ["group_app-a_test"],
        "group_app-b_test": ["group_app-b_test"],
    })
    build = variants_build_for_testing(info, "ws__pkgs", "lock_all")
    group_test = build.split('name = "is_group_test"')[1].split(")")[0]
    env.expect.that_bool("match_all" in group_test).equals(True)
    env.expect.that_bool('"@ws__pkgs//_lock:is_group_app-a_test"' in group_test).equals(True)
    env.expect.that_bool('"@ws__pkgs//_lock:is_group_app-b_test"' in group_test).equals(True)
    env.expect.that_bool('string_flag(\n    name = "_variants",\n    build_setting_default = "",\n)' in build).equals(True)
    env.expect.that_bool('alias(\n    name = "is_group_app-a_test",' in build).equals(True)
    env.expect.that_bool(
        "Set one of the _variants flags on your pycross repo: group_app-a_test, group_app-b_test (e.g. --@lock_all//_variants:group_app-a_test=True or --@lock_all//_variants=group_app-a_test)" in build,
    ).equals(True)

def _test_variants_build_shared_flag(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_variants_build_shared_flag_impl)

# buildifier: disable=unused-variable
def _test_variants_build_repo_default_impl(env, target):
    """The repo default's is_<flag> also matches when nothing in the set is selected."""
    info = collect_variants_for_testing([{
        "items": [
            {"package": "my-app", "kind": "group", "name": "a", "flags": ["group_a", "group_my-app_a"]},
            {"package": "my-app", "kind": "group", "name": "b", "flags": ["group_b", "group_my-app_b"]},
        ],
        "repo_default": "group_my-app_a",
    }])
    build = variants_build_for_testing(info, "ws__pkgs", "pypi")
    unselected = '"@ws__pkgs//_lock:_unselected_group_my-app_a_group_my-app_b"'
    selected_a = build.split('name = "_selected_group_my-app_a"')[1].split(")")[0]
    env.expect.that_bool("match_any" in selected_a and unselected in selected_a).equals(True)
    is_a = build.split('name = "is_group_a"')[1].split(")")[0]
    env.expect.that_str(is_a.strip()).contains('actual = ":_selected_group_my-app_a"')
    is_b = build.split('name = "is_group_b"')[1].split(")")[0]
    env.expect.that_bool(unselected in is_b).equals(False)

    # The message lists one flag per item: the short names, since they're unambiguous.
    env.expect.that_bool("pycross repo: group_a, group_b (e.g. --@pypi//_variants:group_a=True or --@pypi//_variants=group_a)" in build).equals(True)

# buildifier: disable=unused-variable
def _test_variants_build_shared_flag_pinned_impl(env, target):
    """A shared flag over two pinned items matches outside the repo's transition too."""
    variants = [
        {
            "items": [
                {"package": pkg, "kind": "group", "name": "test", "flags": ["group_test", "group_{}_test".format(pkg)]},
                {"package": pkg, "kind": "group", "name": "slow", "flags": ["group_slow", "group_{}_slow".format(pkg)]},
            ],
            "repo_pin": "group_{}_test".format(pkg),
        }
        for pkg in ["app-a", "app-b"]
    ]
    build = variants_build_for_testing(collect_variants_for_testing(variants), "ws__pkgs", "lock_all")
    group_test = build.split('name = "is_group_test"')[1].split(")")[0]
    env.expect.that_str(group_test).contains("match_all")
    env.expect.that_str(group_test).contains('":_selected_group_app-a_test"')
    env.expect.that_str(group_test).contains('":_selected_group_app-b_test"')

def _test_variants_build_shared_flag_pinned(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_variants_build_shared_flag_pinned_impl)

def _test_variants_build_repo_default(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_variants_build_repo_default_impl)

# buildifier: disable=unused-variable
def _test_pin_build_overlapping_sets_impl(env, target):
    """A select touching two conflict sets falls back only when both are unselected."""
    s0 = "extra_cpu_extra_gpu"
    s1 = "extra_cpu_group_gpu-test"
    fallbacks = variant_fallbacks_for_testing({"extra_cpu": [s0, s1], "extra_gpu": [s0]})
    res = pin_build_for_testing(
        target_name = "iniconfig",
        pin_target_dict = {"extra_cpu": "iniconfig@1.1.1", "extra_gpu": "iniconfig@2.0.0"},
        workspace_repo = "ws",
        no_variant_fallbacks = fallbacks,
    ).build
    env.expect.that_int(len(fallbacks.groups)).equals(1)
    group = fallbacks.groups.keys()[0]
    env.expect.that_collection(fallbacks.groups[group]).contains_exactly([s0, s1]).in_order()

    # The error names the set that covers both branches.
    pkg_section = res.split('name = "pkg"')[1].split(")")[0]
    env.expect.that_str(pkg_section).contains('"//_variants:{}": "//_variants:_no_variant_{}"'.format(group, s0))
    env.expect.that_bool("@ws//_lock:_unselected_" in pkg_section).equals(False)

    build = variants_build_for_testing(
        collect_variants_for_testing([
            {"items": [{"package": "app", "kind": "extra", "name": "cpu"}, {"package": "app", "kind": "extra", "name": "gpu"}]},
            {"items": [{"package": "app", "kind": "extra", "name": "cpu"}, {"package": "app", "kind": "group", "name": "gpu-test"}]},
        ]),
        "ws",
        "pypi",
        unselected_groups = fallbacks.groups,
    )
    group_section = build.split('name = "{}"'.format(group))[1].split(")")[0]
    env.expect.that_str(group_section).contains("match_all")
    env.expect.that_str(group_section).contains('"@ws//_lock:_unselected_{}"'.format(s0))
    env.expect.that_str(group_section).contains('"@ws//_lock:_unselected_{}"'.format(s1))

def _test_pin_build_overlapping_sets(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_overlapping_sets_impl)

_S0 = "extra_app_cpu_extra_app_gpu"
_S1 = "extra_app_cpu_group_app_gpu-test"
_S2 = "extra_app_x_extra_app_y"

def _overlapping_variant_info(requested, pin = {}, default = {}):
    sets = [
        [{"package": "app", "kind": "extra", "name": "cpu"}, {"package": "app", "kind": "extra", "name": "gpu"}],
        [{"package": "app", "kind": "extra", "name": "cpu"}, {"package": "app", "kind": "group", "name": "gpu-test"}],
        [{"package": "app", "kind": "extra", "name": "x"}, {"package": "app", "kind": "extra", "name": "y"}],
    ]
    variants = []
    for i, items in enumerate(sets):
        vset = {"items": items, "repo_requested": requested.get(i, [])}
        if i in pin:
            vset["repo_pin"] = pin[i]
        if i in default:
            vset["repo_default"] = default[i]
        variants.append(vset)
    return collect_variants_for_testing(variants)

# buildifier: disable=unused-variable
def _test_transition_settings_impl(env, target):
    """A transitioned repo limits unpinned sets to usable items and drops rival defaults."""

    def settings(info, variant_pins = {}, has_other_flags = False):
        return transition_settings_for_testing(info, variant_pins, "ws", "repo", has_other_flags).fixed_settings

    # Auto-pinned to gpu. cpu (its rival) is all it requests from the second set,
    # and it requests nothing from the third.
    info = _overlapping_variant_info({0: ["extra_app_gpu"], 1: []}, pin = {0: "extra_app_gpu"})
    env.expect.that_dict(settings(info)).contains_exactly({
        "@ws//_lock:_pin_" + _S0: "extra_app_gpu",
        "@ws//_lock:_usable_" + _S1: "",
        "@ws//_lock:_usable_" + _S2: "",
    })

    # A flag pins gpu; the repo also requests cpu and gpu-test. Only gpu-test
    # stays usable in the second set, and its cpu default is dropped.
    info = _overlapping_variant_info(
        {0: ["extra_app_cpu", "extra_app_gpu"], 1: ["extra_app_cpu", "group_app_gpu-test"], 2: ["extra_app_x", "extra_app_y"]},
        default = {1: "extra_app_cpu"},
    )
    env.expect.that_dict(settings(info, variant_pins = {_S0: "extra_app_gpu"}, has_other_flags = True)).contains_exactly({
        "@ws//_lock:_pin_" + _S0: "extra_app_gpu",
        "@ws//_lock:_usable_" + _S1: "group_app_gpu-test",
    })

    # A repo with no transition sets nothing.
    info = _overlapping_variant_info({0: ["extra_app_cpu", "extra_app_gpu"]})
    env.expect.that_dict(settings(info)).contains_exactly({})

    # Outside the transition, `is_<flag>` follows the flag pin, not the rival default.
    info = _overlapping_variant_info({0: ["extra_app_cpu", "extra_app_gpu"], 1: ["extra_app_cpu"]}, default = {1: "extra_app_cpu"})
    result = transition_settings_for_testing(info, {_S0: "extra_app_gpu"}, "ws", "repo", True)
    build = variants_build_for_testing(info, "ws", "repo", pins_by_set = result.pins_by_set, excluded = result.excluded)
    env.expect.that_str(build).contains('name = "_selected_extra_app_gpu"')
    env.expect.that_bool('name = "_selected_extra_app_cpu"' in build).equals(False)

def _test_transition_settings(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_transition_settings_impl)

def _test_variants_build_hidden_flags_impl(env, _target):
    """Auto-generated __build repos omit _variants flags while keeping _no_variant_ targets."""
    info = collect_variants_for_testing([{
        "items": [
            {"package": "app", "kind": "extra", "name": "cpu", "flags": ["extra_cpu"]},
            {"package": "app", "kind": "extra", "name": "gpu", "flags": ["extra_gpu"]},
        ],
        "repo_default": "extra_app_cpu",
    }])
    build = variants_build_for_testing(info, "ws__pkgs", "ws__build", expose_variant_flags = False)
    env.expect.that_bool("bool_flag(" in build).equals(False)
    env.expect.that_bool("string_flag(" in build).equals(False)
    env.expect.that_bool("is_extra_cpu" in build).equals(False)
    env.expect.that_bool("_selected_" in build).equals(False)
    env.expect.that_str(build).contains('name = "_no_variant_extra_app_cpu_extra_app_gpu"')
    env.expect.that_str(build).contains("has no _variants flag for it")

def _test_variants_build_hidden_flags(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_variants_build_hidden_flags_impl)

# buildifier: disable=unused-variable
def _test_pin_build_member_availability_markers_impl(env, target):
    """Thin repos compose per-member availability_markers directly instead of sharing _available_<pkg>."""
    linux_eval = marker_evaluator_name("sys_platform == 'linux'", "")
    darwin_eval = marker_evaluator_name("sys_platform == 'darwin'", "")

    # 1. Wheel-only package without member markers references _wheel_available_<pkg>.
    wheel_only = pin_build_for_testing(
        target_name = "native_pkg",
        pin_target_dict = {"": "native-pkg@1.0"},
        workspace_repo = "ws",
        maybe_available_keys = ["native-pkg@1.0"],
        packages = {
            "native-pkg@1.0": {
                "wheel_candidates": [{"filename": "native_pkg-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"}],
            },
        },
    ).build
    env.expect.that_str(wheel_only).contains('"@ws//_lock:_wheel_available_native-pkg@1.0": ":pkg"')
    env.expect.that_bool("selects.config_setting_group(" in wheel_only).equals(False)

    # 2. Pure-Python package with 1 member marker uses that marker evaluator directly.
    marked = pin_build_for_testing(
        target_name = "linux_only",
        pin_target_dict = {"": "linux-only@1.0"},
        workspace_repo = "ws",
        maybe_available_keys = ["linux-only@1.0"],
        packages = {
            "linux-only@1.0": {
                "wheel_candidates": [{"filename": "linux_only-1.0-py3-none-any.whl"}],
                "availability_markers": ["sys_platform == 'linux'"],
            },
        },
    ).build
    env.expect.that_str(marked).contains('"@ws//_lock:{}_match": ":pkg"'.format(linux_eval))
    env.expect.that_bool("_available_linux-only" in marked).equals(False)

    # 3. Wheel-only package with 2 member markers + extra with its own marker combines with match_any + match_all.
    combined = pin_build_for_testing(
        target_name = "combo",
        pin_target_dict = {"": "combo@1.0"},
        workspace_repo = "ws",
        extras_dict = {"ext": {"": "combo[ext]@1.0"}},
        maybe_available_keys = ["combo@1.0"],
        extras_maybe_keys = {"ext": ["combo[ext]@1.0"]},
        target_platform = "@my//platform:linux",
        packages = {
            "combo@1.0": {
                "wheel_candidates": [{"filename": "combo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"}],
                "availability_markers": ["sys_platform == 'linux'", "sys_platform == 'darwin'"],
            },
            "combo[ext]@1.0": {
                "availability_markers": ["sys_platform == 'linux'"],
            },
        },
    )
    env.expect.that_str(combined.actual_build).contains('load("@bazel_skylib//lib:selects.bzl", "selects")')
    env.expect.that_str(combined.actual_build).contains('"@ws//_lock:_wheel_available_combo@1.0"')
    env.expect.that_str(combined.actual_build).contains('"@ws//_lock:{}_match"'.format(linux_eval))
    env.expect.that_str(combined.actual_build).contains('"@ws//_lock:{}_match"'.format(darwin_eval))
    env.expect.that_str(combined.actual_build).contains("match_any = [")
    env.expect.that_str(combined.actual_build).contains("match_all = [")

    # 4. Non-transitioned multi-marker pin loads selects before package().
    untransitioned = pin_build_for_testing(
        target_name = "combo",
        pin_target_dict = {"": "combo@1.0"},
        workspace_repo = "ws",
        extras_dict = {"ext": {"": "combo[ext]@1.0"}},
        maybe_available_keys = ["combo@1.0"],
        extras_maybe_keys = {"ext": ["combo[ext]@1.0"]},
        packages = {
            "combo@1.0": {
                "wheel_candidates": [{"filename": "combo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"}],
                "availability_markers": ["sys_platform == 'linux'", "sys_platform == 'darwin'"],
            },
            "combo[ext]@1.0": {},
        },
    ).build
    selects_idx = untransitioned.find('load("@bazel_skylib//lib:selects.bzl", "selects")')
    pkg_idx = untransitioned.find("package(")
    env.expect.that_bool(selects_idx > 0 and selects_idx < pkg_idx).equals(True)
    env.expect.that_str(untransitioned).contains('"@ws//_lock:_wheel_available_combo@1.0"')

def _test_pin_build_member_availability_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_member_availability_markers_impl)

# buildifier: disable=unused-variable
def _test_cargo_build_filters_backends_and_wildcards_impl(env, target):
    """_cargo_build only emits aliases for cargo-hook backends and supports versioned, wildcard, and extras-only pins."""
    packages = {
        "c-pkg@1.0": {"sdist_file": {"key": "c_sdist"}},
        "rust-v1@1.0": {"sdist_file": {"key": "r1_sdist"}},
        "rust-v2@2.0": {"sdist_file": {"key": "r2_sdist"}},
        "extra-rust@1.0": {"sdist_file": {"key": "er_sdist"}},
        "extra-rust[all]@1.0": {},
    }
    grouped_pins = {
        "c-pkg": {"base_target": {"": "c-pkg@1.0"}, "extras": {}},
        "rust-v1": {"base_target": {"": "rust-v1@1.0"}, "extras": {}},
        "rust-v2": {"base_target": {"": "rust-v2@2.0"}, "extras": {}},
        "extra-rust": {"base_target": {}, "extras": {"all": {"": "extra-rust[all]@1.0"}}},
    }

    # Non-cargo backend overrides alone produce no _cargo/BUILD.bazel.
    non_cargo = cargo_build_for_testing(
        grouped_pins,
        packages,
        {"c-pkg": {"setuptools_build": {"copt": ["-O2"]}}, "rust-v1": {"cmake_build": {}}},
        "ws",
    )
    env.expect.that_bool(non_cargo == None).equals(True)

    # Empty cargo_backends produces None even with maturin overrides.
    no_hook = cargo_build_for_testing(
        grouped_pins,
        packages,
        {"rust-v1": {"maturin_build": {}}},
        "ws",
        cargo_backends = [],
    )
    env.expect.that_bool(no_hook == None).equals(True)

    # Versioned maturin_build + setuptools_rust_build + extras-only pin emit aliases, while setuptools_build is skipped.
    res = cargo_build_for_testing(
        grouped_pins,
        packages,
        {
            "c-pkg": {"setuptools_build": {}},
            "rust-v1@1.0": {"maturin_build": {}},
            "rust-v2": {"setuptools_rust_build": {}},
            "extra-rust": {"maturin_build": {}},
        },
        "ws",
    )
    env.expect.that_bool('name = "c_pkg"' in res).equals(False)
    env.expect.that_str(res).contains('name = "rust_v1"')
    env.expect.that_str(res).contains('actual = "@ws//_cargo:rust-v1@1.0"')
    env.expect.that_str(res).contains('name = "rust_v2"')
    env.expect.that_str(res).contains('actual = "@ws//_cargo:rust-v2@2.0"')
    env.expect.that_str(res).contains('name = "extra_rust"')
    env.expect.that_str(res).contains('actual = "@ws//_cargo:extra-rust@1.0"')

    # Wildcard "*" maturin_build override matches all sdist packages.
    wild = cargo_build_for_testing(
        grouped_pins,
        packages,
        {"*": {"maturin_build": {}}},
        "ws",
    )
    env.expect.that_str(wild).contains('name = "c_pkg"')
    env.expect.that_str(wild).contains('name = "rust_v1"')

    # Multi-branch pin where only one version has a cargo override falls back to no_match_error.
    partial_branch = cargo_build_for_testing(
        {
            "rust-v1": {
                "base_target": {"res_v1": "rust-v1@1.0", "res_v2": "rust-v1@2.0"},
                "extras": {},
            },
        },
        {
            "rust-v1@1.0": {"sdist_file": {"key": "r1_sdist"}},
            "rust-v1@2.0": {"sdist_file": {"key": "r2_sdist"}},
        },
        {"rust-v1@1.0": {"maturin_build": {}}},
        "ws",
    )
    env.expect.that_str(partial_branch).contains('"@ws//_lock:is_res_v1": "@ws//_cargo:rust-v1@1.0"')
    env.expect.that_str(partial_branch).contains('"@ws//_lock:is_res_v2": "@rules_pycross//pycross/private:no_match_error"')

    # Shared hook_fn across maturin_build and setuptools_rust_build runs once with merged overrides.
    invocations = []

    def _shared_hook(_packages_info, override_packages):
        invocations.append(sorted(override_packages.keys()))
        return [struct(dir = "_cargo", files = {"BUILD.bazel": "HEADER\n" + "\n".join(sorted(override_packages.keys()))})]

    files = run_package_repo_hooks_for_testing(
        {"maturin_build": _shared_hook, "setuptools_rust_build": _shared_hook},
        {},
        {
            "jiter": {"maturin_build": {"cargo_lock": '"//:jiter.lock"'}},
            "python-geohash": {"setuptools_rust_build": {"cargo_lock": '"//:geo.lock"'}},
        },
    )
    env.expect.that_int(len(invocations)).equals(1)
    env.expect.that_collection(invocations[0]).contains_exactly(["jiter", "python-geohash"]).in_order()
    env.expect.that_int(files["_cargo/BUILD.bazel"].count("HEADER")).equals(1)

def _test_cargo_build_filters_backends_and_wildcards(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cargo_build_filters_backends_and_wildcards_impl)

# buildifier: disable=unused-variable
def _test_modules_mapping_deps_selection_impl(env, target):
    """modules_mapping selects active resolution-marker forks and pinned variants while unioning unpinned variants."""
    packages = {
        "common@1.0": {"wheel_candidates": [{"filename": "common-1.0-py3-none-any.whl"}]},
        "numpy@1.26": {"wheel_candidates": [{"filename": "numpy-1.26-py3-none-any.whl"}]},
        "numpy@2.2": {"wheel_candidates": [{"filename": "numpy-2.2-py3-none-any.whl"}]},
        "torch@2.0+cpu": {"wheel_candidates": [{"filename": "torch-2.0+cpu-py3-none-any.whl"}]},
        "torch@2.0+gpu": {"wheel_candidates": [{"filename": "torch-2.0+gpu-py3-none-any.whl"}]},
    }
    pins = {
        "common": {"": "common@1.0", "extra_app_gpu": "common@1.0"},
        "numpy": {"res_py311": "numpy@1.26", "res_py312": "numpy@2.2"},
        "torch": {"extra_app_cpu": "torch@2.0+cpu", "extra_app_gpu": "torch@2.0+gpu"},
    }
    variant_info = collect_variants_for_testing([{
        "items": [
            {"package": "app", "kind": "extra", "name": "cpu", "flags": ["extra_cpu"]},
            {"package": "app", "kind": "extra", "name": "gpu", "flags": ["extra_gpu"]},
        ],
    }])
    s_cpu_gpu = "extra_app_cpu_extra_app_gpu"
    fallbacks = variant_fallbacks_for_testing({
        "extra_app_cpu": [s_cpu_gpu],
        "extra_app_gpu": [s_cpu_gpu],
    })

    # 1. Unpinned repo: resolution-marker forks are selected, unpinned conflict variants are unioned via _unselected_.
    unpinned = modules_mapping_deps_for_testing(
        pins,
        packages,
        "ws",
        variant_info = variant_info,
        no_variant_fallbacks = fallbacks,
    )
    unpinned_deps = "\n".join(unpinned.deps_lines)
    unpinned_extra = "\n".join(unpinned.extra_target_lines)
    env.expect.that_int(unpinned_deps.count('"@ws//_lock:common@1.0"')).equals(1)
    env.expect.that_str(unpinned_deps).contains('"@ws//_lock:is_res_py311": [\n            "@ws//_lock:numpy@1.26",')
    env.expect.that_str(unpinned_deps).contains('"@ws//_lock:is_res_py312": [\n            "@ws//_lock:numpy@2.2",')
    env.expect.that_bool(unpinned.needs_selects).equals(True)
    env.expect.that_str(unpinned_extra).contains('"@ws//_lock:is_extra_app_cpu"')
    env.expect.that_str(unpinned_extra).contains('"@ws//_lock:is_extra_app_gpu"')
    env.expect.that_str(unpinned_extra).contains('"@ws//_lock:_unselected_{}"'.format(s_cpu_gpu))

    # 2. Pinned repo: no _unselected_ unioning; only is_extra_app_* selects are emitted.
    pinned = modules_mapping_deps_for_testing(
        pins,
        packages,
        "ws",
        variant_info = variant_info,
        no_variant_fallbacks = variant_fallbacks_for_testing({
            "extra_app_cpu": [s_cpu_gpu],
            "extra_app_gpu": [s_cpu_gpu],
        }),
        pins_by_set = {s_cpu_gpu: "extra_app_gpu"},
        excluded = {"extra_app_cpu": True},
    )
    pinned_all = "\n".join(pinned.extra_target_lines + pinned.deps_lines)
    env.expect.that_bool("_unselected_" in pinned_all).equals(False)
    env.expect.that_str(pinned_all).contains('"@ws//_lock:is_extra_app_gpu": [\n            "@ws//_lock:torch@2.0+gpu",')

    # 3. Compound {variant, marker} on unpinned set preserves the marker filter when unselected.
    comp = modules_mapping_deps_for_testing(
        {"numpy": {"extra_app_gpu_res_py312": "numpy@2.2"}},
        packages,
        "ws",
        variant_info = variant_info,
        no_variant_fallbacks = variant_fallbacks_for_testing({
            "extra_app_gpu": [s_cpu_gpu],
            "extra_app_gpu_res_py312": [s_cpu_gpu],
        }),
        resolution_marker_exprs = {
            "extra_app_gpu_res_py312": {"variant": "extra_app_gpu", "marker": "res_py312"},
        },
    )
    comp_extra = "\n".join(comp.extra_target_lines)
    env.expect.that_str(comp_extra).contains('name = "_mm_unselected_extra_app_gpu_res_py312"')
    env.expect.that_str(comp_extra).contains("match_all = [")
    env.expect.that_str(comp_extra).contains('"@ws//_lock:is_res_py312"')

    # 4. Overlapping sets: one unpinned (S1=[a,b]), one defaulted to a (S2=[a,c]).
    #    `a` must NOT union on _unselected_S1 (would falsely fire when rival `c` is chosen).
    #    Also check overlapping unpinned sets register _unselected_all_* and platform-specific uses //__maybe:.
    overlap_info = collect_variants_for_testing([
        {"items": [
            {"package": "app", "kind": "extra", "name": "a", "flags": ["extra_a"]},
            {"package": "app", "kind": "extra", "name": "b", "flags": ["extra_b"]},
        ]},
        {
            "items": [
                {"package": "app", "kind": "extra", "name": "a", "flags": ["extra_a"]},
                {"package": "app", "kind": "extra", "name": "c", "flags": ["extra_c"]},
            ],
            "repo_default": "extra_app_a",
        },
    ])
    s1 = "extra_app_a_extra_app_b"
    s2 = "extra_app_a_extra_app_c"
    overlap_mm = modules_mapping_deps_for_testing(
        {
            "pkg_a": {"extra_app_a": "pkg-a@1.0"},
            "pkg_b": {"extra_app_b": "pkg-b@1.0"},
        },
        {
            "pkg-a@1.0": {"wheel_candidates": [{"filename": "pkg_a-1.0-py3-none-any.whl"}]},
            "pkg-b@1.0": {"wheel_candidates": [{"filename": "pkg_b-1.0-cp312-cp312-manylinux_2_17_x86_64.whl"}]},
        },
        "ws",
        variant_info = overlap_info,
        no_variant_fallbacks = variant_fallbacks_for_testing({
            "extra_app_a": [s1, s2],
            "extra_app_b": [s1],
        }),
    )
    overlap_deps = "\n".join(overlap_mm.deps_lines)
    env.expect.that_str(overlap_deps).contains('"@ws//_lock:is_extra_app_a": [\n            "@ws//_lock:pkg-a@1.0",')
    env.expect.that_bool("pkg_b_1_0" in overlap_mm.maybe_mapping_targets).equals(True)
    env.expect.that_str(overlap_deps).contains('"//__maybe:pkg_b_1_0"')

    # 5. _variants_build for overlapping sets S1=[a,b] (no default), S2=[a,c] (default=a):
    #    _selected_extra_app_a must require BOTH S1 and S2 unselected so selecting rival `b` doesn't fire is_extra_a.
    overlap_vbuild = variants_build_for_testing(overlap_info, "ws", "pypi")
    selected_a = overlap_vbuild.split('name = "_selected_extra_app_a"')[1].split("\n)")[0]
    env.expect.that_bool("_unselected_all_" in selected_a).equals(True)
    env.expect.that_bool('"@ws//_lock:_unselected_{}"'.format(s2) in selected_a).equals(False)
    env.expect.that_str(overlap_vbuild).contains('"@ws//_lock:_unselected_{}"'.format(s1))
    env.expect.that_str(overlap_vbuild).contains('"@ws//_lock:_unselected_{}"'.format(s2))

    # 6. overlapping_rivals_for_testing maps overlapping conflict sets to their shared qnames
    #    (including multi-item overlaps) and ignores disjoint sets.
    vset_s1 = {"qnames": ["a", "b"]}
    vset_s2 = {"qnames": ["a", "b", "c"]}
    vset_s3_disjoint = {"qnames": ["d", "e"]}
    rivals = overlapping_rivals_for_testing(vset_s2, [vset_s1, vset_s2, vset_s3_disjoint])
    env.expect.that_dict(rivals).contains_exactly({"a_b": ["a", "b"]})

def _test_modules_mapping_deps_selection(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_modules_mapping_deps_selection_impl)

# buildifier: disable=unused-variable
def _test_partial_fork_maybe_and_testonly_impl(env, target):
    """Variant-only/partial-fork pins route through :maybe in all_requirements and propagate testonly."""
    mock_rctx = struct(name = "my_repo")
    pins = {
        "tomli": {"res_py311": "tomli@2.0.1"},
        "triton[cuda]": {"extra_gpu": "triton[cuda]@3.0.0"},
    }
    packages = {
        "tomli@2.0.1": {"wheel_candidates": [{"filename": "tomli-2.0.1-py3-none-any.whl"}], "sdist_file": {"key": "t"}},
        "triton@3.0.0": {"wheel_candidates": [{"filename": "triton-3.0.0-py3-none-any.whl"}], "sdist_file": {"key": "tr"}},
        "triton[cuda]@3.0.0": {},
    }
    req_bzl = requirements_bzl_for_testing(mock_rctx, pins, packages)
    env.expect.that_str(req_bzl).contains('"@@my_repo//tomli:maybe"')
    env.expect.that_str(req_bzl).contains('"@@my_repo//triton:[cuda]_maybe"')

    # _pin_build emits :maybe even when maybe_available_keys is empty, and forwards testonly = True.
    res = pin_build_for_testing(
        target_name = "tomli",
        pin_target_dict = {"res_py311": "tomli@2.0.1"},
        workspace_repo = "ws",
        extras_dict = {"dev": {"res_py311": "tomli[dev]@2.0.1"}},
        testonly = True,
    ).build
    maybe_block = res.split('name = "maybe"')[1].split("\n)")[0]
    env.expect.that_str(maybe_block).contains('"@ws//_lock:is_res_py311": ":pkg"')
    env.expect.that_str(maybe_block).contains('"//conditions:default": "//:_empty_library"')
    env.expect.that_str(maybe_block).contains("testonly = True,")

    extra_maybe_block = res.split('name = "[dev]_maybe"')[1].split("\n)")[0]
    env.expect.that_str(extra_maybe_block).contains('"@ws//_lock:is_res_py311": ":[dev]"')
    env.expect.that_str(extra_maybe_block).contains("testonly = True,")

    # Single-branch untransitioned platform-specific testonly pin also carries testonly = True on :maybe.
    single_testonly = pin_build_for_testing(
        target_name = "pywin32",
        pin_target_dict = {"": "pywin32@312"},
        workspace_repo = "ws",
        maybe_available_keys = ["pywin32@312"],
        testonly = True,
    ).build
    single_maybe = single_testonly.split('name = "maybe"')[1].split("\n)")[0]
    env.expect.that_str(single_maybe).contains("testonly = True,")

    # Multi-branch untransitioned testonly pin with maybe_available_keys forwards testonly to per-branch helper.
    multi_testonly = pin_build_for_testing(
        target_name = "foo",
        pin_target_dict = {"res_1": "foo@1.0", "res_2": "foo@2.0"},
        workspace_repo = "ws",
        maybe_available_keys = ["foo@1.0"],
        testonly = True,
    ).build
    helper_block = multi_testonly.split('name = "_maybe_foo_1_0"')[1].split("\n)")[0]
    env.expect.that_str(helper_block).contains("testonly = True,")

    # Transitioned partial-fork pin emits :maybe in actual_build wrapped by transitioning proxy.
    trans_partial = pin_build_for_testing(
        target_name = "tomli",
        pin_target_dict = {"res_py311": "tomli@2.0.1"},
        workspace_repo = "ws",
        target_platform = "@my//platform:linux",
        testonly = True,
    )
    env.expect.that_str(trans_partial.build).contains('actual = "//__actual/tomli:maybe"')
    env.expect.that_str(trans_partial.actual_build).contains('name = "maybe"')
    env.expect.that_str(trans_partial.actual_build).contains('"@ws//_lock:is_res_py311": "//__actual/tomli:pkg"')

def _test_partial_fork_maybe_and_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_partial_fork_maybe_and_testonly_impl)

# buildifier: disable=unused-variable
def _test_requirement_extra_canon_and_extras_only_metadata_impl(env, target):
    """requirement() canonicalizes extras and pin_versions/_packages include extras-only pins."""
    mock_rctx = struct(name = "my_repo")
    req_bzl = requirements_bzl_for_testing(mock_rctx, {}, {})
    env.expect.that_str(req_bzl).contains('extra = pypackaging.utils.canonicalize_name(extra.rstrip("]"))')

    grouped_pins = {
        "uvicorn": {
            "base_target": None,
            "extras": {"standard": {"": "uvicorn[standard]@0.30.0"}},
        },
        "httpx": {
            "base_target": None,
            "extras": {
                "http2": {"extra_a": "httpx[http2]@0.26.0"},
                "socks": {"extra_b": "httpx[socks]@0.27.0"},
            },
        },
    }
    packages = {
        "uvicorn@0.30.0": {"sdist_file": {"key": "uv_sdist"}},
        "uvicorn[standard]@0.30.0": {},
        "httpx@0.26.0": {},
        "httpx@0.27.0": {},
    }
    pv = pin_versions_for_testing(grouped_pins)
    env.expect.that_str(pv["uvicorn"]).equals("0.30.0")
    env.expect.that_dict(pv["httpx"]).contains_exactly({"extra_a": "0.26.0", "extra_b": "0.27.0"})

    pkgs_bzl = packages_bzl_for_testing(grouped_pins, packages)
    uvicorn_block = pkgs_bzl.split('"uvicorn": struct(')[1].split("),")[0]
    env.expect.that_str(uvicorn_block).contains("has_sdist = True,")

def _test_requirement_extra_canon_and_extras_only_metadata(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_requirement_extra_canon_and_extras_only_metadata_impl)

# buildifier: disable=unused-variable
def _test_pin_build_emits_empty_brackets_when_aggregated_without_extras_impl(env, target):
    result = pin_build_for_testing(
        "foo",
        {"": "foo@1.0"},
        "ws__pkgs",
        has_aggregated_variant = True,
        extras_dict = {},
    )
    env.expect.that_str(result.build).contains('actual = "@ws__pkgs//_lock:foo[_all_]@1.0",')
    env.expect.that_str(result.build).contains('name = "[]",')
    env.expect.that_str(result.build).contains('actual = "@ws__pkgs//_lock:foo@1.0",')

    # Also check hidden-flag no-variant message uses readable item names instead of raw set_suffix.
    vinfo = collect_variants_for_testing([
        {
            "items": [
                {"kind": "extra", "package": "app-a", "name": "cpu"},
                {"kind": "extra", "package": "app-a", "name": "gpu"},
            ],
        },
    ])
    vbuild = variants_build_for_testing(vinfo, "ws__pkgs", "pypi", expose_variant_flags = False)
    env.expect.that_str(vbuild).contains("has no _variants flag for it (app-a[cpu], app-a[gpu])")

def _test_pin_build_emits_empty_brackets_when_aggregated_without_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pin_build_emits_empty_brackets_when_aggregated_without_extras_impl,
    )

def _test_render_transition_bzl_and_maybe_build_impl(env, _target):
    bzl = render_transition_bzl_for_testing(
        "pypi",
        ["--@rules_python//python/config_settings:python_version=3.12"],
        {},
        {"@ws//_lock:_pin_set": "extra_a"},
    )
    env.expect.that_str(bzl).contains('load("@rules_pycross//pycross/private:proxy.bzl", "make_file_proxy_rule", "make_library_proxy_rule")')
    env.expect.that_str(bzl).contains("pycross_transitioning_library_proxy = make_library_proxy_rule(cfg = _repo_transition)")
    env.expect.that_str(bzl).contains("pycross_transitioning_file_proxy = make_file_proxy_rule(cfg = _repo_transition)")

    maybe = render_maybe_build_for_testing(
        {"pywin32_312": ("pywin32@312", "@ws//_lock:pywin32@312")},
        {"pywin32@312": {"wheel_candidates": [{"filename": "pywin32-312-cp312-cp312-win_amd64.whl"}]}},
        "ws",
    )
    env.expect.that_str(maybe).contains('"//conditions:default": "//:_empty_library",')
    env.expect.that_bool("py_library(" not in maybe).equals(True)

    env.expect.that_str(url_filename("https://example.com/files/torch-2.5.0%2Bcu124-cp312-cp312-linux_x86_64.whl?token=abc#sha256=dead")).equals(
        "torch-2.5.0+cu124-cp312-cp312-linux_x86_64.whl",
    )

def _test_render_transition_bzl_and_maybe_build(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_render_transition_bzl_and_maybe_build_impl,
    )

def thin_package_repo_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_variants_build_shared_flag,
            _test_variants_build_repo_default,
            _test_variants_build_shared_flag_pinned,
            _test_variants_build_hidden_flags,
            _test_pin_build_member_availability_markers,
            _test_cargo_build_filters_backends_and_wildcards,
            _test_modules_mapping_deps_selection,
            _test_partial_fork_maybe_and_testonly,
            _test_requirement_extra_canon_and_extras_only_metadata,
            _test_pin_build_emits_empty_brackets_when_aggregated_without_extras,
            _test_render_transition_bzl_and_maybe_build,
            _test_transition_settings,
            _test_pin_build_overlapping_sets,
            _test_pin_build_no_transition,
            _test_pin_build_with_platform,
            _test_pin_build_transition_loads,
            _test_pin_build_extras_with_platform,
            _test_pin_build_sdist_with_platform,
            _test_pin_build_variants_with_platform,
            _test_pin_build_basic_structure,
            _test_pin_build_with_transition_bzl,
            _test_pin_build_transition_bzl_variants,
            _test_is_platform_specific,
            _test_requirements_bzl_maybe_aliases,
            _test_requirements_bzl_all_unconditional,
            _test_requirements_bzl_extra_pins,
            _test_requirements_bzl_root_marker_aliases,
            _test_pin_build_multi_branch_maybe,
            _test_requirements_bzl_extra_of_platform_specific,
            _test_flag_values,
            _test_transition_value_coercion,
            _test_requirements_bzl_testonly_split,
            _test_pin_build_aggregated_only_branches_with_extras,
            _test_pin_build_multi_branch_sdist,
            _test_cargo_build_multi_branch,
            _test_backend_tool_deps_labels,
            _test_pin_build_multi_branch_no_match_fallback,
            _test_pin_build_maybe_with_transition,
            _test_pin_build_no_variant_fallback,
        ],
    )
