"""Tests for _pin_build from thin_package_repo.bzl"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:state_repo.bzl", "backend_tool_deps_labels", "run_package_repo_hooks")

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "coerce_transition_values", "is_platform_specific", "marker_evaluator_name", "split_setting_value", "url_filename")

# buildifier: disable=bzl-visibility
load("//pycross/private:variant_util.bzl", "excluded_variant_items")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:availability.bzl", "render_maybe_build")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:common.bzl", "effective_base_target_dict")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:metadata.bzl", "hook_subdir_build", "requirements_bzl")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:modules_mapping_deps.bzl", "modules_mapping_deps")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:pins.bzl", "append_root_aliases", "pin_build", "pin_repo_context", "pin_spec")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:selects.bzl", "variant_fallbacks")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:transition.bzl", "flag_values", "render_transition_bzl")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:variants.bzl", "collect_variants", "transition_settings", "variants_build")

def _pin_build(
        target_name,
        pin_target_dict,
        workspace_name,
        extras_dict = None,
        no_variant_fallbacks = None,
        target_platform = None,
        transition_bzl = None,
        maybe_available_keys = None,
        extras_maybe_keys = None,
        testonly = False,
        sdist_target_dict = None,
        packages = None,
        resolution_marker_exprs = None):
    return pin_build(
        pin_spec(
            target_name = target_name,
            pin_target_dict = pin_target_dict,
            extras_dict = extras_dict,
            maybe_available_keys = maybe_available_keys,
            extras_maybe_keys = extras_maybe_keys,
            testonly = testonly,
            sdist_target_dict = sdist_target_dict,
        ),
        pin_repo_context(
            workspace_name = workspace_name,
            no_variant_fallbacks = no_variant_fallbacks,
            target_platform = target_platform,
            transition_bzl = transition_bzl,
            packages = packages,
            resolution_marker_exprs = resolution_marker_exprs,
        ),
    )

# ── Test: no platform → non-transitioning proxies ──────────────────

# buildifier: disable=unused-variable
def _test_pin_build_no_transition_impl(env, target):
    """Without target_platform, should use pycross_thin_library_proxy / pycross_file_proxy."""
    res = _pin_build(
        target_name = "numpy",
        pin_target_dict = {"": "numpy"},
        workspace_name = "my_workspace",
    ).build

    # Should load the non-transitioning rules
    env.expect.that_bool("pycross_thin_library_proxy" in res).equals(True)
    env.expect.that_bool("pycross_file_proxy" in res).equals(True)
    env.expect.that_bool("pycross_library_proxy" not in res).equals(True)

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
    res = _pin_build(
        target_name = "numpy",
        pin_target_dict = {"": "numpy"},
        workspace_name = "my_workspace",
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
    res_no_platform = _pin_build(
        target_name = "foo",
        pin_target_dict = {"": "foo"},
        workspace_name = "ws",
    ).build
    res_with_platform = _pin_build(
        target_name = "foo",
        pin_target_dict = {"": "foo"},
        workspace_name = "ws",
        target_platform = "//:my_platform",
    ).build

    # Without platform: load should have non-transitioning
    load_no = [line for line in res_no_platform.split("\n") if line.startswith("load(")][0]
    env.expect.that_bool('"pycross_thin_library_proxy"' in load_no).equals(True)
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
    res = _pin_build(
        target_name = "numpy",
        pin_target_dict = {"": "numpy"},
        workspace_name = "my_workspace",
        extras_dict = {"gpu": {"": "numpy[gpu]"}},
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
    res = _pin_build(
        target_name = "numpy",
        pin_target_dict = {"": "numpy"},
        sdist_target_dict = {"": "numpy"},
        workspace_name = "my_workspace",
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
    """Combines variants (direct extras + non-trivial pin_target_dict) with platform transition."""
    res_struct = _pin_build(
        target_name = "numpy",
        pin_target_dict = {
            "cpu": "numpy@s0",
            "gpu": "numpy@s1",
        },
        workspace_name = "my_workspace",
        extras_dict = {"extra1": {"cpu": "numpy[extra1]@s0", "gpu": "numpy[extra1]@s1"}},
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

    # Must NOT reference workspace-wide [_all_] aggregates; each version slot
    # aggregates its own direct extra in __actual.
    env.expect.that_bool("[_all_]@" in res).equals(False)
    actual = res_struct.actual_build or ""
    env.expect.that_str(actual).contains('"@my_workspace__pkg_numpy//:[extra1]_s0"')
    env.expect.that_str(actual).contains('"@my_workspace__pkg_numpy//:[extra1]_s1"')
    env.expect.that_str(actual).contains('name = "base"')

    # With direct extras, the [] base target uses lib_rule (not alias)
    env.expect.that_bool('name = "[]"' in res).equals(True)

    # Extras with variants should also use select in actual_build
    extra_section = actual.split('name = "extra_extra1"')[1].split(")")[0]
    env.expect.that_bool("select({" in extra_section).equals(True)

    # Variant defaults come from the repo's transition, not from //conditions:default.
    env.expect.that_bool('"//conditions:default": ":numpy' in res).equals(False)

def _test_pin_build_variants_with_platform(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_variants_with_platform_impl)

# ── Test: no platform, no sdist → minimal output ──────────────────

# buildifier: disable=unused-variable
def _test_pin_build_basic_structure_impl(env, target):
    """Basic structure: alias, pkg proxy, wheel proxy, dist_info proxy, data alias."""
    res = _pin_build(
        target_name = "requests",
        pin_target_dict = {"": "requests"},
        workspace_name = "ws",
    ).build

    # Should have the top-level alias
    env.expect.that_bool('name = "requests"' in res).equals(True)
    env.expect.that_bool('actual = ":pkg"' in res).equals(True)

    # Should have pkg proxy pointing to spoke target
    env.expect.that_bool('name = "pkg"' in res).equals(True)
    env.expect.that_bool('"@ws__pkg_requests//:pkg"' in res).equals(True)

    # Should have wheel proxy pointing to spoke wheel target
    env.expect.that_bool('name = "wheel"' in res).equals(True)
    env.expect.that_bool('"@ws__pkg_requests//:wheel"' in res).equals(True)

    # Should have dist_info proxy
    env.expect.that_bool('name = "dist_info"' in res).equals(True)
    env.expect.that_bool('"@ws__pkg_requests//:dist_info"' in res).equals(True)

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
    result = _pin_build(
        target_name = "numpy",
        pin_target_dict = {"": "numpy"},
        sdist_target_dict = {"": "numpy"},
        workspace_name = "my_workspace",
        extras_dict = {"gpu": {"": "numpy[gpu]"}},
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

    # Direct extras live on a post-transition pycross_library_proxy inside __actual.
    env.expect.that_bool(result.actual_build != None).equals(True)
    env.expect.that_str(result.actual_build).contains('actual = "@my_workspace__pkg_numpy//:pkg"')
    env.expect.that_str(result.actual_build).contains('"@my_workspace__pkg_numpy//:[gpu]"')

    # Without extras, single-entry target dicts emit no __actual package.
    plain_result = _pin_build(
        target_name = "numpy",
        pin_target_dict = {"": "numpy"},
        workspace_name = "my_workspace",
        target_platform = "//:_internal_platform",
        transition_bzl = "//:_transition.bzl",
    )
    env.expect.that_bool(plain_result.actual_build == None).equals(True)

def _test_pin_build_with_transition_bzl(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_with_transition_bzl_impl)

# ── Test: transition_bzl with variants → intermediate select aliases ─

# buildifier: disable=unused-variable
def _test_pin_build_transition_bzl_variants_impl(env, target):
    """When transition_bzl is set and pins have variants, intermediate alias targets are emitted for select()."""
    result = _pin_build(
        target_name = "numpy",
        pin_target_dict = {
            "cpu": "numpy@s0",
            "gpu": "numpy@s1",
        },
        workspace_name = "my_workspace",
        extras_dict = {"extra1": {"cpu": "numpy[extra1]@s0", "gpu": "numpy[extra1]@s1"}},
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
    env.expect.that_bool('name = "base"' in actual).equals(True)
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
    res = requirements_bzl(mock_rctx, pins, packages)

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
    env.expect.that_bool(is_platform_specific({
        "wheel_candidates": [{"filename": "pkg-1.0-cp310-win_amd64.whl"}],
    })).equals(True)

    # Package with universal py3-none-any (or py2.py3-none-any, or with build tag)
    # wheel and no availability_markers → NOT platform-specific even without sdist
    env.expect.that_bool(is_platform_specific({
        "wheel_candidates": [{"filename": "pkg-1.0-py3-none-any.whl"}],
    })).equals(False)
    env.expect.that_bool(is_platform_specific({
        "wheel_candidates": [{"filename": "pkg-1.0-py2.py3-none-any.whl"}],
    })).equals(False)
    env.expect.that_bool(is_platform_specific({
        "wheel_candidates": [{"filename": "pkg-1.0-1-py3-none-any.whl"}],
    })).equals(False)

    # Malformed 7-part filename does not take the universal fast path
    env.expect.that_bool(is_platform_specific({
        "wheel_candidates": [{"filename": "bad-pkg-1.0-1-py3-none-any.whl"}],
    })).equals(True)

    # Universal wheel WITH availability_markers → still platform-specific
    env.expect.that_bool(is_platform_specific({
        "wheel_candidates": [{"filename": "pkg-1.0-py3-none-any.whl"}],
        "availability_markers": ["sys_platform != 'win32'"],
    })).equals(True)

    # Version-constrained pure wheel (py311-none-any) → platform-specific
    env.expect.that_bool(is_platform_specific({
        "wheel_candidates": [{"filename": "pkg-1.0-py311-none-any.whl"}],
    })).equals(True)

    # Package with wheels AND sdist → NOT platform-specific
    env.expect.that_bool(is_platform_specific({
        "wheel_candidates": [{"filename": "pkg-1.0-cp310-win_amd64.whl"}],
        "sdist_file": {"key": "sdist_key"},
    })).equals(False)

    # Package with wheels AND build_target → NOT platform-specific
    env.expect.that_bool(is_platform_specific({
        "wheel_candidates": [{"filename": "pkg-1.0-cp310-win_amd64.whl"}],
        "build_target": "@some//:target",
    })).equals(False)

    # Package with no wheel_candidates (extras wrapper) → NOT platform-specific
    env.expect.that_bool(is_platform_specific({})).equals(False)

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
    res = requirements_bzl(mock_rctx, pins, packages)

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
    res = requirements_bzl(mock_rctx, pins, packages)

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
    res = requirements_bzl(mock_rctx, pins, packages)

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
    res_exprs = {
        "res_foo_s0": "python_version < '3.12'",
        "res_foo_s1": "python_version >= '3.12'",
    }
    res = _pin_build(
        target_name = "foo",
        pin_target_dict = {
            "res_foo_s0": "foo@s0",
            "res_foo_s1": "foo@s1",
        },
        workspace_name = "ws",
        extras_dict = {
            "bar": {
                "res_foo_s0": "foo[bar]@s0",
                "res_foo_s1": "foo[bar]@s1",
            },
        },
        maybe_available_keys = ["foo@s0"],
        extras_maybe_keys = {"bar": ["foo[bar]@s0", "foo[bar]@s1"]},
        resolution_marker_exprs = res_exprs,
    ).build

    # Base maybe: foo@s0 is platform-specific (uses helper _maybe_foo_s0),
    # while foo@s1 is unconditional (maps directly to :pkg).
    env.expect.that_bool('name = "_maybe_foo_s0"' in res).equals(True)
    env.expect.that_bool('"@ws__pkg_foo//:_wheel_available_s0": ":pkg"' in res).equals(True)
    env.expect.that_bool('"//_markers:is_res_foo_s0": ":_maybe_foo_s0"' in res).equals(True)
    env.expect.that_bool('"//_markers:is_res_foo_s1": ":pkg"' in res).equals(True)

    # Extra maybe: both foo[bar]@s0 and foo[bar]@s1 are platform-specific.
    env.expect.that_bool('name = "_maybe_extra_bar_foo_bar__s0"' in res).equals(True)
    env.expect.that_bool('name = "_maybe_extra_bar_foo_bar__s1"' in res).equals(True)
    env.expect.that_bool('"//_markers:is_res_foo_s0": ":_maybe_extra_bar_foo_bar__s0"' in res).equals(True)
    env.expect.that_bool('"//_markers:is_res_foo_s1": ":_maybe_extra_bar_foo_bar__s1"' in res).equals(True)

def _test_pin_build_multi_branch_maybe(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_multi_branch_maybe_impl)

# buildifier: disable=unused-variable
def _test_flag_values_impl(env, target):
    """Repeated flags collect values in order; a bare flag means True; no comma splitting."""
    res = flag_values([
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
    res = requirements_bzl(mock_rctx, pins, packages)
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
    res = requirements_bzl(mock_rctx, pins, packages, {"pytest": True})
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
    """Multi-version pin aggregates direct extras only on fork branches that match their base slot."""
    res_exprs = {
        "res_foo_s0": "python_version < '3.12'",
        "res_foo_s1": "python_version >= '3.12'",
    }
    res = _pin_build(
        target_name = "foo",
        pin_target_dict = {
            "res_foo_s0": "foo@s0",
            "res_foo_s1": "foo@s1",
        },
        workspace_name = "ws",
        extras_dict = {"opt": {"res_foo_s0": "foo[opt]@s0"}},
        resolution_marker_exprs = res_exprs,
    ).build
    env.expect.that_str(res).contains('name = "_pkg_foo_s0",')
    env.expect.that_str(res).contains('"@ws__pkg_foo//:[opt]_s0",')
    env.expect.that_str(res).contains('"//_markers:is_res_foo_s0": ":_pkg_foo_s0"')
    env.expect.that_str(res).contains('"//_markers:is_res_foo_s1": "@ws__pkg_foo//:pkg_s1"')
    env.expect.that_bool("[_all_]" in res).equals(False)

def _test_pin_build_aggregated_only_branches_with_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_aggregated_only_branches_with_extras_impl)

# ── Test: multi-branch sdist ───────────────────────────────────────

# buildifier: disable=unused-variable
def _test_pin_build_multi_branch_sdist_impl(env, target):
    """When only a non-first branch has an sdist, :sdist still reflects it."""
    res_exprs = {
        "res_foo_s0": "python_version < '3.12'",
        "res_foo_s1": "python_version >= '3.12'",
    }
    pin_target_dict = {
        "res_foo_s0": "foo@s0",
        "res_foo_s1": "foo@s1",
    }
    res = _pin_build(
        target_name = "foo",
        pin_target_dict = pin_target_dict,
        workspace_name = "ws",
        sdist_target_dict = {"res_foo_s1": "foo@s1"},
        resolution_marker_exprs = res_exprs,
    ).build

    env.expect.that_bool('name = "sdist"' in res).equals(True)
    env.expect.that_bool('"//_markers:is_res_foo_s0": "@rules_pycross//pycross/private:no_match_error"' in res).equals(True)
    env.expect.that_bool('"//_markers:is_res_foo_s1": "@ws__pkg_foo//:sdist_s1"' in res).equals(True)
    env.expect.that_bool('"//conditions:default": "@rules_pycross//pycross/private:no_match_error"' in res).equals(True)
    env.expect.that_bool('"@ws__pkg_foo//:sdist_s0"' not in res).equals(True)

def _test_pin_build_multi_branch_sdist(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_multi_branch_sdist_impl)

# ── Test: multi-branch _cargo/BUILD.bazel ──────────────────────────

# buildifier: disable=unused-variable
def _test_cargo_build_multi_branch_impl(env, target):
    """hook_subdir_build uses target_select across branches with hook_subdirs and falls back to no_match_error."""
    res_exprs = {
        "res_jiter_s0": "python_version < '3.12'",
        "res_jiter_s1": "python_version >= '3.12'",
        "res_partial_s0": "python_version < '3.12'",
        "res_partial_s1": "python_version >= '3.12'",
    }
    grouped_pins = {
        "jiter": {
            "base_target": {
                "res_jiter_s0": "jiter@s0",
                "res_jiter_s1": "jiter@s1",
            },
            "extras": {},
        },
        "partial": {
            "base_target": {
                "res_partial_s0": "partial@s0",
                "res_partial_s1": "partial@s1",
            },
            "extras": {},
        },
    }
    packages = {
        "jiter@s0": {"sdist_file": True, "hook_subdirs": ["_cargo"]},
        "jiter@s1": {"sdist_file": True, "hook_subdirs": ["_cargo"]},
        "partial@s0": {},
        "partial@s1": {"sdist_file": True, "hook_subdirs": ["_cargo"]},
    }
    cargo_result = hook_subdir_build(
        grouped_pins,
        packages,
        "ws",
        subdir = "_cargo",
        resolution_marker_exprs = res_exprs,
    )
    env.expect.that_bool(cargo_result != None).equals(True)
    cargo_bzl = cargo_result.build
    env.expect.that_bool("select({" in cargo_bzl).equals(True)
    env.expect.that_bool('"//_markers:is_res_jiter_s0": "@ws__pkg_jiter//_cargo:pkg_s0"' in cargo_bzl).equals(True)
    env.expect.that_bool('"//_markers:is_res_jiter_s1": "@ws__pkg_jiter//_cargo:pkg_s1"' in cargo_bzl).equals(True)
    env.expect.that_bool('"//_markers:is_res_partial_s0": "@rules_pycross//pycross/private:no_match_error"' in cargo_bzl).equals(True)
    env.expect.that_bool('"//_markers:is_res_partial_s1": "@ws__pkg_partial//_cargo:pkg_s1"' in cargo_bzl).equals(True)
    env.expect.that_bool('"//conditions:default": "@rules_pycross//pycross/private:no_match_error"' in cargo_bzl).equals(True)

def _test_cargo_build_multi_branch(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cargo_build_multi_branch_impl)

# ── Test: backend_tool_deps_labels ─────────────────────────────────

# buildifier: disable=unused-variable
def _test_backend_tool_deps_labels_impl(env, target):
    """backend_tool_deps_labels resolves canonical base packages to @<build_repo>//<pkg>:pkg labels."""
    known_base_packages = ["setuptools", "scikit-build-core"]
    labels = backend_tool_deps_labels(
        ["setuptools", "scikit-build-core", "wheel", "flit-core"],
        known_base_packages,
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
    res_exprs = {
        "res_setuptools_s0": "python_version < '3.12'",
        "res_setuptools_s1": "python_version >= '3.12'",
    }
    res = _pin_build(
        target_name = "setuptools",
        pin_target_dict = {
            "res_setuptools_s0": "setuptools@s0",
            "res_setuptools_s1": "setuptools@s1",
        },
        workspace_name = "ws",
        resolution_marker_exprs = res_exprs,
    ).build

    pkg_section = res.split('name = "pkg"')[1].split(")")[0]
    env.expect.that_bool('"//_markers:is_res_setuptools_s0": "@ws__pkg_setuptools//:pkg_s0"' in pkg_section).equals(True)
    env.expect.that_bool('"//_markers:is_res_setuptools_s1": "@ws__pkg_setuptools//:pkg_s1"' in pkg_section).equals(True)
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
    single = _pin_build(
        target_name = "pywin32",
        pin_target_dict = {"": "pywin32"},
        workspace_name = "ws",
        target_platform = "@my//platform:linux",
        maybe_available_keys = ["pywin32"],
    )
    env.expect.that_bool("select({" not in single.build).equals(True)
    env.expect.that_bool('name = "maybe"' in single.build).equals(True)
    env.expect.that_bool('actual = "//__actual/pywin32:maybe"' in single.build).equals(True)
    env.expect.that_bool(single.actual_build != None).equals(True)
    env.expect.that_bool('name = "maybe"' in single.actual_build).equals(True)
    env.expect.that_bool('"@ws__pkg_pywin32//:_wheel_available": "@ws__pkg_pywin32//:pkg"' in single.actual_build).equals(True)

    # 2. Multi-branch pin and extra with transition_bzl + target_platform + testonly
    res_exprs = {
        "res_foo_s0": "python_version < '3.12'",
        "res_foo_s1": "python_version >= '3.12'",
    }
    multi = _pin_build(
        target_name = "foo",
        pin_target_dict = {
            "res_foo_s0": "foo@s0",
            "res_foo_s1": "foo@s1",
        },
        workspace_name = "ws",
        extras_dict = {
            "bar": {
                "res_foo_s0": "foo[bar]@s0",
                "res_foo_s1": "foo[bar]@s1",
            },
        },
        target_platform = "//:_internal_platform",
        transition_bzl = "//:_transition.bzl",
        maybe_available_keys = ["foo@s0"],
        extras_maybe_keys = {"bar": ["foo[bar]@s0", "foo[bar]@s1"]},
        testonly = True,
        resolution_marker_exprs = res_exprs,
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

    env.expect.that_bool('name = "_maybe_foo_s0"' in multi.actual_build).equals(True)
    env.expect.that_bool('"@ws__pkg_foo//:_wheel_available_s0": "//__actual/foo:pkg"' in multi.actual_build).equals(True)
    env.expect.that_bool('"//_markers:is_res_foo_s0": ":_maybe_foo_s0"' in multi.actual_build).equals(True)
    env.expect.that_bool('"//_markers:is_res_foo_s1": "//__actual/foo:pkg"' in multi.actual_build).equals(True)

    env.expect.that_bool('name = "_maybe_extra_bar_foo_bar__s0"' in multi.actual_build).equals(True)
    env.expect.that_bool('name = "_maybe_extra_bar_foo_bar__s1"' in multi.actual_build).equals(True)
    env.expect.that_bool('"@ws__pkg_foo//:_wheel_available_[bar]_s0": "//__actual/foo:extra_bar"' in multi.actual_build).equals(True)
    env.expect.that_bool('name = "extra_bar_maybe"' in multi.actual_build).equals(True)

def _test_pin_build_maybe_with_transition(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_maybe_with_transition_impl)

# ── Test: unselected variant fallback uses _no_variant_<set> ───────

# buildifier: disable=unused-variable
def _test_pin_build_no_variant_fallback_impl(env, target):
    """Variant pins without a default variant emit _unselected_<set> -> _no_variant_<set> and preserve //conditions:default."""
    no_variant_fallbacks = variant_fallbacks({
        "extra_variant-a": ["extra_variant-a_extra_variant-b"],
        "extra_variant-b": ["extra_variant-a_extra_variant-b"],
    })
    res = _pin_build(
        target_name = "typing_extensions",
        pin_target_dict = {
            "extra_variant-a": "typing-extensions@s0",
            "extra_variant-b": "typing-extensions@s1",
        },
        workspace_name = "ws",
        no_variant_fallbacks = no_variant_fallbacks,
        maybe_available_keys = ["typing-extensions@s0"],
    ).build

    pkg_section = res.split('name = "pkg"')[1].split(")")[0]
    env.expect.that_bool('"@ws__state//:is_extra_variant-a": "@ws__pkg_typing_extensions//:pkg_s0"' in pkg_section).equals(True)
    env.expect.that_bool('"@ws__state//:is_extra_variant-b": "@ws__pkg_typing_extensions//:pkg_s1"' in pkg_section).equals(True)
    env.expect.that_bool('"@ws__state//:_unselected_extra_variant-a_extra_variant-b": "//_variants:_no_variant_extra_variant-a_extra_variant-b"' in pkg_section).equals(True)
    env.expect.that_bool('"//conditions:default": "@rules_pycross//pycross/private:no_match_error"' in pkg_section).equals(True)

    maybe_section = res.split('name = "maybe"')[1].split(")")[0]
    env.expect.that_bool('"@ws__state//:_unselected_extra_variant-a_extra_variant-b": "//_variants:_no_variant_extra_variant-a_extra_variant-b"' in maybe_section).equals(True)
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
    info = collect_variants(_SHARED_TEST_VARIANTS)
    env.expect.that_dict(info.flags).contains_exactly({
        "group_test": ["group_app-a_test", "group_app-b_test"],
        "group_app-a_test": ["group_app-a_test"],
        "group_app-b_test": ["group_app-b_test"],
    })
    build = variants_build(info, "ws__state", "lock_all")
    group_test = build.split('name = "is_group_test"')[1].split(")")[0]
    env.expect.that_bool("match_all" in group_test).equals(True)
    env.expect.that_bool('"@ws__state//:is_group_app-a_test"' in group_test).equals(True)
    env.expect.that_bool('"@ws__state//:is_group_app-b_test"' in group_test).equals(True)
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
    info = collect_variants([{
        "items": [
            {"package": "my-app", "kind": "group", "name": "a", "flags": ["group_a", "group_my-app_a"]},
            {"package": "my-app", "kind": "group", "name": "b", "flags": ["group_b", "group_my-app_b"]},
        ],
        "repo_default": "group_my-app_a",
    }])
    build = variants_build(info, "ws__state", "pypi")
    unselected = '"@ws__state//:_unselected_group_my-app_a_group_my-app_b"'
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
    build = variants_build(collect_variants(variants), "ws__state", "lock_all")
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
    fallbacks = variant_fallbacks({"extra_cpu": [s0, s1], "extra_gpu": [s0]})
    pin_res = _pin_build(
        target_name = "iniconfig",
        pin_target_dict = {"extra_cpu": "iniconfig@s0", "extra_gpu": "iniconfig@s1"},
        workspace_name = "ws",
        no_variant_fallbacks = fallbacks,
    )
    res = pin_res.build
    env.expect.that_int(len(pin_res.unselected_groups)).equals(1)
    group = pin_res.unselected_groups.keys()[0]
    env.expect.that_collection(pin_res.unselected_groups[group]).contains_exactly([s0, s1]).in_order()

    # The error names the set that covers both branches.
    pkg_section = res.split('name = "pkg"')[1].split(")")[0]
    env.expect.that_str(pkg_section).contains('"//_variants:{}": "//_variants:_no_variant_{}"'.format(group, s0))
    env.expect.that_bool("@ws__state//:_unselected_" in pkg_section).equals(False)

    build = variants_build(
        collect_variants([
            {"items": [{"package": "app", "kind": "extra", "name": "cpu"}, {"package": "app", "kind": "extra", "name": "gpu"}]},
            {"items": [{"package": "app", "kind": "extra", "name": "cpu"}, {"package": "app", "kind": "group", "name": "gpu-test"}]},
        ]),
        "ws__state",
        "pypi",
        unselected_groups = pin_res.unselected_groups,
    )
    group_section = build.split('name = "{}"'.format(group))[1].split(")")[0]
    env.expect.that_str(group_section).contains("match_all")
    env.expect.that_str(group_section).contains('"@ws__state//:_unselected_{}"'.format(s0))
    env.expect.that_str(group_section).contains('"@ws__state//:_unselected_{}"'.format(s1))

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
    return collect_variants(variants)

# buildifier: disable=unused-variable
def _test_transition_settings_impl(env, target):
    """A transitioned repo limits unpinned sets to usable items and drops rival defaults."""

    def settings(info, variant_pins = {}, has_other_flags = False):
        return transition_settings(info, variant_pins, "repo", has_other_flags).state_overrides

    # Auto-pinned to gpu. cpu (its rival) is all it requests from the second set,
    # and it requests nothing from the third.
    info = _overlapping_variant_info({0: ["extra_app_gpu"], 1: []}, pin = {0: "extra_app_gpu"})
    env.expect.that_dict(settings(info)).contains_exactly({
        "p:" + _S0: "extra_app_gpu",
        "u:" + _S1: "",
        "u:" + _S2: "",
    })

    # A flag pins gpu; the repo also requests cpu and gpu-test. Only gpu-test
    # stays usable in the second set, and its cpu default is dropped.
    info = _overlapping_variant_info(
        {0: ["extra_app_cpu", "extra_app_gpu"], 1: ["extra_app_cpu", "group_app_gpu-test"], 2: ["extra_app_x", "extra_app_y"]},
        default = {1: "extra_app_cpu"},
    )
    env.expect.that_dict(settings(info, variant_pins = {_S0: "extra_app_gpu"}, has_other_flags = True)).contains_exactly({
        "p:" + _S0: "extra_app_gpu",
        "u:" + _S1: "group_app_gpu-test",
    })

    # A repo with no transition sets nothing.
    info = _overlapping_variant_info({0: ["extra_app_cpu", "extra_app_gpu"]})
    env.expect.that_dict(settings(info)).contains_exactly({})

    # Outside the transition, `is_<flag>` follows the flag pin, not the rival default.
    info = _overlapping_variant_info({0: ["extra_app_cpu", "extra_app_gpu"], 1: ["extra_app_cpu"]}, default = {1: "extra_app_cpu"})
    result = transition_settings(info, {_S0: "extra_app_gpu"}, "repo", True)
    env.expect.that_dict(result.defaults_by_set).contains_exactly({})
    build = variants_build(
        info,
        "ws",
        "repo",
        pins_by_set = result.pins_by_set,
        defaults_by_set = result.defaults_by_set,
        excluded = result.excluded,
    )
    env.expect.that_str(build).contains('name = "_selected_extra_app_gpu"')
    env.expect.that_bool('name = "_selected_extra_app_cpu"' in build).equals(False)

    # Non-excluded default is returned in defaults_by_set.
    default_info = _overlapping_variant_info(
        {0: ["extra_app_cpu", "extra_app_gpu"], 2: ["extra_app_x", "extra_app_y"]},
        default = {0: "extra_app_cpu", 2: "extra_app_x"},
    )
    default_result = transition_settings(default_info, {}, "repo", False)
    env.expect.that_dict(default_result.defaults_by_set).contains_exactly({
        _S0: "extra_app_cpu",
        _S2: "extra_app_x",
    })

def _test_transition_settings(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_transition_settings_impl)

def _test_variants_build_hidden_flags_impl(env, _target):
    """Auto-generated __build repos omit _variants flags while keeping _no_variant_ targets."""
    info = collect_variants([{
        "items": [
            {"package": "app", "kind": "extra", "name": "cpu", "flags": ["extra_cpu"]},
            {"package": "app", "kind": "extra", "name": "gpu", "flags": ["extra_gpu"]},
        ],
        "repo_default": "extra_app_cpu",
    }])
    build = variants_build(info, "ws__state", "ws__build", expose_variant_flags = False)
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

    # 1. Wheel-only package without member markers references spoke _wheel_available.
    wheel_only = _pin_build(
        target_name = "native_pkg",
        pin_target_dict = {"": "native-pkg"},
        workspace_name = "ws",
        maybe_available_keys = ["native-pkg"],
        packages = {
            "native-pkg": {
                "wheel_platform_specific": True,
            },
        },
    ).build
    env.expect.that_str(wheel_only).contains('"@ws__pkg_native_pkg//:_wheel_available": ":pkg"')
    env.expect.that_bool("selects.config_setting_group(" in wheel_only).equals(False)

    # 2. Pure-Python package with 1 member marker uses member-local //_markers evaluator directly.
    marked = _pin_build(
        target_name = "linux_only",
        pin_target_dict = {"": "linux-only"},
        workspace_name = "ws",
        maybe_available_keys = ["linux-only"],
        packages = {
            "linux-only": {
                "availability_markers": ["sys_platform == 'linux'"],
            },
        },
    ).build
    env.expect.that_str(marked).contains('"//_markers:{}_match": ":pkg"'.format(linux_eval))
    env.expect.that_bool("_available_linux-only" in marked).equals(False)

    # 3. Wheel-only package with 2 member markers + extra with its own marker combines with match_any + match_all.
    combined = _pin_build(
        target_name = "combo",
        pin_target_dict = {"": "combo"},
        workspace_name = "ws",
        extras_dict = {"ext": {"": "combo[ext]"}},
        maybe_available_keys = ["combo"],
        extras_maybe_keys = {"ext": ["combo[ext]"]},
        target_platform = "@my//platform:linux",
        packages = {
            "combo": {
                "wheel_platform_specific": True,
                "availability_markers": ["sys_platform == 'linux'", "sys_platform == 'darwin'"],
            },
            "combo[ext]": {
                "availability_markers": ["sys_platform == 'linux'"],
            },
        },
    )
    env.expect.that_str(combined.actual_build).contains('load("@bazel_skylib//lib:selects.bzl", "selects")')
    env.expect.that_str(combined.actual_build).contains('"@ws__pkg_combo//:_wheel_available"')
    env.expect.that_str(combined.actual_build).contains('"//_markers:{}_match"'.format(linux_eval))
    env.expect.that_str(combined.actual_build).contains('"//_markers:{}_match"'.format(darwin_eval))
    env.expect.that_str(combined.actual_build).contains("match_any = [")
    env.expect.that_str(combined.actual_build).contains("match_all = [")

    # 4. Non-transitioned multi-marker pin loads selects before package().
    untransitioned = _pin_build(
        target_name = "combo",
        pin_target_dict = {"": "combo"},
        workspace_name = "ws",
        extras_dict = {"ext": {"": "combo[ext]"}},
        maybe_available_keys = ["combo"],
        extras_maybe_keys = {"ext": ["combo[ext]"]},
        packages = {
            "combo": {
                "wheel_platform_specific": True,
                "availability_markers": ["sys_platform == 'linux'", "sys_platform == 'darwin'"],
            },
            "combo[ext]": {},
        },
    ).build
    selects_idx = untransitioned.find('load("@bazel_skylib//lib:selects.bzl", "selects")')
    pkg_idx = untransitioned.find("package(")
    env.expect.that_bool(selects_idx > 0 and selects_idx < pkg_idx).equals(True)
    env.expect.that_str(untransitioned).contains('"@ws__pkg_combo//:_wheel_available"')

def _test_pin_build_member_availability_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_member_availability_markers_impl)

# buildifier: disable=unused-variable
def _test_cargo_build_filters_backends_and_wildcards_impl(env, target):
    """hook_subdir_build emits version-free aliases from precomputed hook_subdirs and deduplicates shared hooks."""
    grouped_pins = {
        "c-pkg": {"base_target": {"": "c-pkg"}, "extras": {}},
        "rust-v1": {"base_target": {"": "rust-v1"}, "extras": {}},
        "rust-v2": {"base_target": {"": "rust-v2"}, "extras": {}},
        "extra-rust": {"base_target": {}, "extras": {"all": {"": "extra-rust[all]"}}},
    }

    # Packages without hook_subdirs produce no _cargo/BUILD.bazel.
    non_cargo = hook_subdir_build(
        grouped_pins,
        {
            "c-pkg": {"sdist_file": True},
            "rust-v1": {"sdist_file": True},
        },
        "ws",
        subdir = "_cargo",
    )
    env.expect.that_bool(non_cargo == None).equals(True)

    # Packages with matching hook_subdirs (including extras-only pins) emit version-free spoke aliases.
    res = hook_subdir_build(
        grouped_pins,
        {
            "c-pkg": {"sdist_file": True},
            "rust-v1": {"sdist_file": True, "hook_subdirs": ["_cargo"]},
            "rust-v2": {"sdist_file": True, "hook_subdirs": ["_cargo"]},
            "extra-rust": {"sdist_file": True, "hook_subdirs": ["_cargo"]},
            "extra-rust[all]": {},
        },
        "ws",
        subdir = "_cargo",
    ).build
    env.expect.that_bool('name = "c_pkg"' in res).equals(False)
    env.expect.that_str(res).contains('name = "rust_v1"')
    env.expect.that_str(res).contains('actual = "@ws__pkg_rust_v1//_cargo:pkg"')
    env.expect.that_str(res).contains('name = "rust_v2"')
    env.expect.that_str(res).contains('actual = "@ws__pkg_rust_v2//_cargo:pkg"')
    env.expect.that_str(res).contains('name = "extra_rust"')
    env.expect.that_str(res).contains('actual = "@ws__pkg_extra_rust//_cargo:pkg"')

    # Third-party backend registering a custom package_repo_hook_subdir gets aliases under that subdir.
    custom_subdir = hook_subdir_build(
        grouped_pins,
        {"rust-v1": {"sdist_file": True, "hook_subdirs": ["_custom_cargo"]}},
        "ws",
        subdir = "_custom_cargo",
    ).build
    env.expect.that_str(custom_subdir).contains('name = "rust_v1"')
    env.expect.that_str(custom_subdir).contains('actual = "@ws__pkg_rust_v1//_custom_cargo:pkg"')

    # Multi-branch pin where only one slot has a cargo override falls back to no_match_error.
    partial_branch = hook_subdir_build(
        {
            "rust-v1": {
                "base_target": {"res_v1": "rust-v1@s0", "res_v2": "rust-v1@s1"},
                "extras": {},
            },
        },
        {
            "rust-v1@s0": {"sdist_file": True, "hook_subdirs": ["_cargo"]},
            "rust-v1@s1": {"sdist_file": True},
        },
        "ws",
        subdir = "_cargo",
        resolution_marker_exprs = {"res_v1": "sys_platform == 'linux'", "res_v2": "sys_platform == 'darwin'"},
    ).build
    env.expect.that_str(partial_branch).contains('"//_markers:is_res_v1": "@ws__pkg_rust_v1//_cargo:pkg_s0"')
    env.expect.that_str(partial_branch).contains('"//_markers:is_res_v2": "@rules_pycross//pycross/private:no_match_error"')

    # Shared hook_fn across maturin_build and setuptools_rust_build runs once with merged overrides.
    invocations = []

    def _shared_hook(_packages_info, override_packages):
        invocations.append(sorted(override_packages.keys()))
        return [struct(dir = "_cargo", files = {"BUILD.bazel": "HEADER\n" + "\n".join(sorted(override_packages.keys()))})]

    files = run_package_repo_hooks(
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
        "common": {},
        "numpy@s0": {},
        "numpy@s1": {},
        "torch@s0": {},
        "torch@s1": {},
    }
    pins = {
        "common": {"": "common", "extra_app_gpu": "common"},
        "numpy": {"res_py311": "numpy@s0", "res_py312": "numpy@s1"},
        "torch": {"extra_app_cpu": "torch@s0", "extra_app_gpu": "torch@s1"},
    }
    res_exprs = {
        "res_py311": "python_version < '3.12'",
        "res_py312": "python_version >= '3.12'",
    }
    variant_info = collect_variants([{
        "items": [
            {"package": "app", "kind": "extra", "name": "cpu", "flags": ["extra_cpu"]},
            {"package": "app", "kind": "extra", "name": "gpu", "flags": ["extra_gpu"]},
        ],
    }])
    s_cpu_gpu = "extra_app_cpu_extra_app_gpu"
    fallbacks = variant_fallbacks({
        "extra_app_cpu": [s_cpu_gpu],
        "extra_app_gpu": [s_cpu_gpu],
    })

    # 1. Unpinned repo: resolution-marker forks are selected, unpinned conflict variants are unioned via _unselected_.
    unpinned = modules_mapping_deps(
        pins,
        packages,
        "ws",
        variant_info = variant_info,
        no_variant_fallbacks = fallbacks,
        resolution_marker_exprs = res_exprs,
    )
    unpinned_deps = "\n".join(unpinned.deps_lines)
    unpinned_extra = "\n".join(unpinned.extra_target_lines)
    env.expect.that_int(unpinned_deps.count('"@ws__pkg_common//:_raw"')).equals(1)
    env.expect.that_str(unpinned_deps).contains('"//_markers:is_res_py311": [\n            "@ws__pkg_numpy//:_raw_s0",')
    env.expect.that_str(unpinned_deps).contains('"//_markers:is_res_py312": [\n            "@ws__pkg_numpy//:_raw_s1",')
    env.expect.that_bool(unpinned.needs_selects).equals(True)
    env.expect.that_str(unpinned_extra).contains('"@ws__state//:is_extra_app_cpu"')
    env.expect.that_str(unpinned_extra).contains('"@ws__state//:is_extra_app_gpu"')
    env.expect.that_str(unpinned_extra).contains('"@ws__state//:_unselected_{}"'.format(s_cpu_gpu))

    # 2. Pinned repo: no _unselected_ unioning; only is_extra_app_* selects are emitted.
    pinned = modules_mapping_deps(
        pins,
        packages,
        "ws",
        variant_info = variant_info,
        no_variant_fallbacks = variant_fallbacks({
            "extra_app_cpu": [s_cpu_gpu],
            "extra_app_gpu": [s_cpu_gpu],
        }),
        pins_by_set = {s_cpu_gpu: "extra_app_gpu"},
        excluded = {"extra_app_cpu": True},
        resolution_marker_exprs = res_exprs,
    )
    pinned_all = "\n".join(pinned.extra_target_lines + pinned.deps_lines)
    env.expect.that_bool("_unselected_" in pinned_all).equals(False)
    env.expect.that_str(pinned_all).contains('"@ws__state//:is_extra_app_gpu": [\n            "@ws__pkg_torch//:_raw_s1",')

    # 3. Compound {variant, marker} on unpinned set preserves the marker filter when unselected.
    comp = modules_mapping_deps(
        {"numpy": {"extra_app_gpu_res_py312": "numpy@s1"}},
        packages,
        "ws",
        variant_info = variant_info,
        no_variant_fallbacks = variant_fallbacks({
            "extra_app_gpu": [s_cpu_gpu],
            "extra_app_gpu_res_py312": [s_cpu_gpu],
        }),
        resolution_marker_exprs = {
            "res_py312": "python_version >= '3.12'",
            "extra_app_gpu_res_py312": {"variant": "extra_app_gpu", "marker": "res_py312"},
        },
    )
    comp_extra = "\n".join(comp.extra_target_lines)
    env.expect.that_str(comp_extra).contains('name = "_mm_unselected_extra_app_gpu_res_py312"')
    env.expect.that_str(comp_extra).contains("match_all = [")
    env.expect.that_str(comp_extra).contains('"//_markers:is_res_py312"')

    # 4. Overlapping sets: one unpinned (S1=[a,b]), one defaulted to a (S2=[a,c]).
    #    `a` must NOT union on _unselected_S1 (would falsely fire when rival `c` is chosen).
    #    Also check overlapping unpinned sets register _unselected_all_* and platform-specific uses //__maybe:.
    overlap_info = collect_variants([
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
    overlap_mm = modules_mapping_deps(
        {
            "pkg_a": {"extra_app_a": "pkg-a"},
            "pkg_b": {"extra_app_b": "pkg-b"},
        },
        {
            "pkg-a": {},
            "pkg-b": {"wheel_platform_specific": True},
        },
        "ws",
        variant_info = overlap_info,
        no_variant_fallbacks = variant_fallbacks({
            "extra_app_a": [s1, s2],
            "extra_app_b": [s1],
        }),
    )
    overlap_deps = "\n".join(overlap_mm.deps_lines)
    env.expect.that_str(overlap_deps).contains('"@ws__state//:is_extra_app_a": [\n            "@ws__pkg_pkg_a//:_raw",')
    env.expect.that_bool("pkg_b" in overlap_mm.maybe_mapping_targets).equals(True)
    env.expect.that_str(overlap_deps).contains('"//__maybe:pkg_b"')

    # 5. _variants_build for overlapping sets S1=[a,b] (no default), S2=[a,c] (default=a):
    #    _selected_extra_app_a must require BOTH S1 and S2 unselected so selecting rival `b` doesn't fire is_extra_a.
    overlap_vbuild = variants_build(overlap_info, "ws__state", "pypi")
    selected_a = overlap_vbuild.split('name = "_selected_extra_app_a"')[1].split("\n)")[0]
    env.expect.that_bool("_unselected_all_" in selected_a).equals(True)
    env.expect.that_bool('"@ws__state//:_unselected_{}"'.format(s2) in selected_a).equals(False)
    env.expect.that_str(overlap_vbuild).contains('"@ws__state//:_unselected_{}"'.format(s1))
    env.expect.that_str(overlap_vbuild).contains('"@ws__state//:_unselected_{}"'.format(s2))

    # 6. excluded_variant_items returns rivals across overlapping conflict sets and ignores disjoint sets.
    env.expect.that_dict(
        excluded_variant_items([["a", "b"], ["a", "b", "c"], ["d", "e"]], ["a"]),
    ).contains_exactly({"b": True, "c": True})

def _test_modules_mapping_deps_selection(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_modules_mapping_deps_selection_impl)

# buildifier: disable=unused-variable
def _test_partial_fork_maybe_and_testonly_impl(env, target):
    """Variant-only/partial-fork pins route through :maybe in all_requirements and propagate testonly."""
    mock_rctx = struct(name = "my_repo")
    pins = {
        "tomli": {"res_py311": "tomli"},
        "triton[cuda]": {"extra_gpu": "triton[cuda]"},
    }
    packages = {
        "tomli": {"sdist_file": True},
        "triton": {"sdist_file": True},
        "triton[cuda]": {},
    }
    req_bzl = requirements_bzl(mock_rctx, pins, packages)
    env.expect.that_str(req_bzl).contains('"@@my_repo//tomli:maybe"')
    env.expect.that_str(req_bzl).contains('"@@my_repo//triton:[cuda]_maybe"')

    res_exprs = {"res_py311": "python_version < '3.11'"}

    # _pin_build emits :maybe even when maybe_available_keys is empty; untransitioned
    # :maybe targets are alias() rules (Bazel ignores testonly on alias(), inheriting
    # testonly from :pkg / :[extra]), so they omit redundant testonly = True.
    res = _pin_build(
        target_name = "tomli",
        pin_target_dict = {"res_py311": "tomli"},
        workspace_name = "ws",
        extras_dict = {"dev": {"res_py311": "tomli[dev]"}},
        testonly = True,
        resolution_marker_exprs = res_exprs,
    ).build
    maybe_block = res.split('name = "maybe"')[1].split("\n)")[0]
    env.expect.that_str(maybe_block).contains('"//_markers:is_res_py311": ":pkg"')
    env.expect.that_str(maybe_block).contains('"//conditions:default": "//:_empty_library"')
    env.expect.that_bool("testonly = True," in maybe_block).equals(False)

    extra_maybe_block = res.split('name = "[dev]_maybe"')[1].split("\n)")[0]
    env.expect.that_str(extra_maybe_block).contains('"//_markers:is_res_py311": ":[dev]"')
    env.expect.that_bool("testonly = True," in extra_maybe_block).equals(False)

    # Transitioned partial-fork pin emits :maybe in actual_build wrapped by transitioning proxy (with testonly = True).
    trans_partial = _pin_build(
        target_name = "tomli",
        pin_target_dict = {"res_py311": "tomli"},
        workspace_name = "ws",
        target_platform = "@my//platform:linux",
        testonly = True,
        resolution_marker_exprs = res_exprs,
    )
    env.expect.that_str(trans_partial.build).contains('actual = "//__actual/tomli:maybe"')
    trans_maybe_block = trans_partial.build.split('name = "maybe"')[1].split("\n)")[0]
    env.expect.that_str(trans_maybe_block).contains("testonly = True,")
    env.expect.that_str(trans_partial.actual_build).contains('name = "maybe"')
    env.expect.that_str(trans_partial.actual_build).contains('"//_markers:is_res_py311": "//__actual/tomli:pkg"')

def _test_partial_fork_maybe_and_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_partial_fork_maybe_and_testonly_impl)

# buildifier: disable=unused-variable
def _test_requirement_extra_canon_impl(env, target):
    """requirement() canonicalizes extras."""
    mock_rctx = struct(name = "my_repo")
    req_bzl = requirements_bzl(mock_rctx, {}, {})
    env.expect.that_str(req_bzl).contains('extra = pypackaging.utils.canonicalize_name(extra.rstrip("]"))')

def _test_requirement_extra_canon(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_requirement_extra_canon_impl)

# buildifier: disable=unused-variable
def _test_pin_build_emits_empty_brackets_when_aggregated_without_extras_impl(env, target):
    # Direct extras emit pycross_library_proxy on :pkg and a base-only :[] target.
    with_extra = _pin_build(
        "foo",
        {"": "foo"},
        "ws",
        extras_dict = {"opt": {"": "foo[opt]"}},
    )
    env.expect.that_str(with_extra.build).contains("pycross_library_proxy(")
    env.expect.that_str(with_extra.build).contains('actual = "@ws__pkg_foo//:pkg",')
    env.expect.that_str(with_extra.build).contains('"@ws__pkg_foo//:[opt]",')
    env.expect.that_str(with_extra.build).contains('name = "[]",')
    env.expect.that_str(with_extra.build).contains("pycross_thin_library_proxy(")
    env.expect.that_bool("[_all_]" in with_extra.build).equals(False)

    # Without direct extras, :pkg stays a lean pycross_thin_library_proxy and :[] is omitted.
    bare = _pin_build(
        "foo",
        {"": "foo"},
        "ws",
        extras_dict = {},
    )
    env.expect.that_bool("pycross_library_proxy(" in bare.build).equals(False)
    env.expect.that_bool('name = "[]"' in bare.build).equals(False)

    # Also check hidden-flag no-variant message uses readable item names instead of raw set_suffix.
    vinfo = collect_variants([
        {
            "items": [
                {"kind": "extra", "package": "app-a", "name": "cpu"},
                {"kind": "extra", "package": "app-a", "name": "gpu"},
            ],
        },
    ])
    vbuild = variants_build(vinfo, "ws__state", "pypi", expose_variant_flags = False)
    env.expect.that_str(vbuild).contains("has no _variants flag for it (app-a[cpu], app-a[gpu])")

def _test_pin_build_emits_empty_brackets_when_aggregated_without_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pin_build_emits_empty_brackets_when_aggregated_without_extras_impl,
    )

def _test_render_transition_bzl_and_maybe_build_impl(env, _target):
    bzl = render_transition_bzl(
        "pypi",
        ["--@rules_python//python/config_settings:python_version=3.12"],
        {},
        variant_state_label = "@ws__state//:_state",
        variant_state_overrides = {"p:set": "extra_a"},
    )
    env.expect.that_str(bzl).contains('load("@rules_pycross//pycross/private:proxy.bzl", "make_file_proxy_rule", "make_library_proxy_rule")')
    env.expect.that_str(bzl).contains('load("@rules_pycross//pycross/private:util.bzl", "coerce_transition_values")')
    env.expect.that_str(bzl).contains('load("@rules_pycross//pycross/private:variant_util.bzl", "merge_variant_state")')
    env.expect.that_str(bzl).contains("merge_variant_state(settings[_VARIANT_STATE_LABEL], _VARIANT_STATE_OVERRIDES)")
    env.expect.that_str(bzl).contains("pycross_transitioning_library_proxy = make_library_proxy_rule(cfg = _repo_transition, supports_deps = False)")
    env.expect.that_str(bzl).contains("pycross_transitioning_file_proxy = make_file_proxy_rule(cfg = _repo_transition)")
    env.expect.that_bool("_SETTING_VALUES" in bzl).equals(False)
    env.expect.that_bool("split_setting_value" in bzl).equals(False)

    # Variant-state-only transition omits _FLAG_VALUES, _SETTING_VALUES, and util.bzl load.
    state_only = render_transition_bzl(
        "pypi",
        [],
        {},
        variant_state_label = "@ws__state//:_state",
        variant_state_overrides = {"d:set": "extra_a"},
    )
    env.expect.that_bool(":util.bzl" in state_only).equals(False)
    env.expect.that_bool("_FLAG_VALUES" in state_only).equals(False)
    env.expect.that_bool("_SETTING_VALUES" in state_only).equals(False)
    env.expect.that_str(state_only).contains('load("@rules_pycross//pycross/private:variant_util.bzl", "merge_variant_state")')

    # Settings-only transition emits _SETTING_VALUES + split_setting_value and omits _FLAG_VALUES/duplicate guard/variant_util.
    settings_only = render_transition_bzl("pypi", [], {"@@//pkg:x": "v"})
    env.expect.that_str(settings_only).contains('load("@rules_pycross//pycross/private:util.bzl", "coerce_transition_values", "split_setting_value")')
    env.expect.that_str(settings_only).contains("_SETTING_VALUES = {")
    env.expect.that_str(settings_only).contains("    result = {}")
    env.expect.that_bool("_FLAG_VALUES" in settings_only).equals(False)
    env.expect.that_bool("_CANONICAL_FLAG_LABELS" in settings_only).equals(False)
    env.expect.that_bool("variant_util.bzl" in settings_only).equals(False)

    # Both flags and settings emit both dicts, both util helpers, and the duplicate guard.
    both = render_transition_bzl(
        "pypi",
        ["--@rules_python//python/config_settings:python_version=3.12"],
        {"@@//pkg:custom": "val"},
    )
    env.expect.that_str(both).contains('load("@rules_pycross//pycross/private:util.bzl", "coerce_transition_values", "split_setting_value")')
    env.expect.that_bool("variant_util.bzl" in both).equals(False)
    env.expect.that_str(both).contains("_FLAG_VALUES = {")
    env.expect.that_str(both).contains("_SETTING_VALUES = {")
    env.expect.that_str(both).contains("_CANONICAL_FLAG_LABELS = {")

    maybe = render_maybe_build(
        {"pywin32": ("pywin32", "@ws__pkg_pywin32//:_raw")},
        {"pywin32": {"wheel_platform_specific": True}},
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

# buildifier: disable=unused-variable
def _test_effective_base_target_dict_all_shapes_impl(env, target):
    """effective_base_target_dict handles extras-only, Airflow, disjoint, and cross-version extra shapes."""

    # 1. Extras-only pin derives base key from extras.
    env.expect.that_dict(effective_base_target_dict({
        "base_target": None,
        "extras": {"opt": {"": "only[opt]@1.0"}},
    })).contains_exactly({"": "only@1.0"})

    # 2. Airflow shape (unconditional base + variant-gated extra on same version) avoids redundant select().
    env.expect.that_dict(effective_base_target_dict({
        "base_target": {"": "pkg@1.0"},
        "extras": {"openai": {"is_openai": "pkg[openai]@1.0"}},
    })).contains_exactly({"": "pkg@1.0"})

    # 3. Disjoint constraints include both base and extra constraints.
    env.expect.that_dict(effective_base_target_dict({
        "base_target": {"is_a": "pkg@1.0"},
        "extras": {"opt": {"is_b": "pkg[opt]@1.0"}},
    })).contains_exactly({"is_a": "pkg@1.0", "is_b": "pkg@1.0"})

    # 4. Different base version on extra adds that constraint without dropping default.
    env.expect.that_dict(effective_base_target_dict({
        "base_target": {"": "pkg@2.0"},
        "extras": {"opt": {"is_a": "pkg[opt]@1.0"}},
    })).contains_exactly({"": "pkg@2.0", "is_a": "pkg@1.0"})

    # 5. Extras-only pin with unconditional + variant-gated extras avoids redundant select().
    env.expect.that_dict(effective_base_target_dict({
        "base_target": None,
        "extras": {
            "a": {"": "pkg[a]@1.0"},
            "b": {"is_b": "pkg[b]@1.0"},
        },
    })).contains_exactly({"": "pkg@1.0"})

    # 6. Forked resolution-marker base + compound or plain variant-gated extras does not
    #    inject colliding variant/compound keys into the base target dict.
    fork_res_exprs = {
        "res_py_lt_310": "python_version < '3.10'",
        "res_py_ge_310": "python_version >= '3.10'",
        "extra_alpha_res_py_lt_310": {"variant": "extra_alpha", "marker": "res_py_lt_310"},
        "extra_alpha_res_py_ge_310": {"variant": "extra_alpha", "marker": "res_py_ge_310"},
    }
    fork_variants = {
        "extra_alpha": ["alpha_beta"],
        "extra_alpha_res_py_lt_310": ["alpha_beta"],
        "extra_alpha_res_py_ge_310": ["alpha_beta"],
    }
    env.expect.that_dict(effective_base_target_dict(
        {
            "base_target": {"res_py_lt_310": "foo@1", "res_py_ge_310": "foo@2"},
            "extras": {
                "opt": {
                    "extra_alpha_res_py_lt_310": "foo[opt]@1",
                    "extra_alpha_res_py_ge_310": "foo[opt]@2",
                },
            },
        },
        resolution_marker_exprs = fork_res_exprs,
        variant_constraints = fork_variants,
    )).contains_exactly({"res_py_lt_310": "foo@1", "res_py_ge_310": "foo@2"})

    env.expect.that_dict(effective_base_target_dict(
        {
            "base_target": {"res_py_lt_310": "foo@1", "res_py_ge_310": "foo@2"},
            "extras": {"opt": {"extra_alpha": "foo[opt]@2"}},
        },
        resolution_marker_exprs = fork_res_exprs,
        variant_constraints = fork_variants,
    )).contains_exactly({"res_py_lt_310": "foo@1", "res_py_ge_310": "foo@2"})

def _test_effective_base_target_dict_all_shapes(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_effective_base_target_dict_all_shapes_impl)

# buildifier: disable=unused-variable
def _test_pin_build_direct_extras_aggregation_shapes_impl(env, target):
    """Direct extras aggregation covers variant gating, multi-version safety, disjoint constraints, markers, and dedup."""

    # Shape A: ungated base + variant-gated direct extra under transition -> post-transition
    # empty-default select() in __actual/wrapper:pkg (no no_match_error or _no_variant on pkg).
    fallbacks = variant_fallbacks({"extra_alpha": ["alpha_beta"]})
    shape_a = _pin_build(
        target_name = "wrapper",
        pin_target_dict = {"": "wrapper"},
        extras_dict = {"v1": {"extra_alpha": "wrapper[v1]"}},
        workspace_name = "ws",
        no_variant_fallbacks = fallbacks,
        transition_bzl = "//:_transition.bzl",
    )
    env.expect.that_str(shape_a.build).contains('actual = "//__actual/wrapper:pkg",')
    env.expect.that_str(shape_a.actual_build).contains('load("@rules_pycross//pycross/private:proxy.bzl", "pycross_library_proxy")')
    pkg_block_a = shape_a.actual_build.split('name = "pkg"')[1].split("\n)")[0]
    env.expect.that_str(pkg_block_a).contains('actual = "@ws__pkg_wrapper//:pkg",')
    env.expect.that_str(pkg_block_a).contains('"@ws__state//:is_extra_alpha": [')
    env.expect.that_str(pkg_block_a).contains('"@ws__pkg_wrapper//:[v1]",')
    env.expect.that_str(pkg_block_a).contains('"//conditions:default": [],')
    env.expect.that_bool("no_match_error" in pkg_block_a).equals(False)
    env.expect.that_bool("_no_variant_" in pkg_block_a).equals(False)
    env.expect.that_bool('":[v1]"' in pkg_block_a).equals(False)

    # Shape B: multi-version mixed pin ({cpu: foo@s0, gpu: foo@s1, "": foo@s1}) +
    # foo[opt]: {cpu: foo[opt]@s0, "": foo[opt]@s0} -> gpu and "" get bare foo@s1, ONLY cpu gets foo[opt]@s0.
    shape_b = _pin_build(
        target_name = "foo",
        pin_target_dict = {"cpu": "foo@s0", "gpu": "foo@s1", "": "foo@s1"},
        extras_dict = {"opt": {"cpu": "foo[opt]@s0", "": "foo[opt]@s0"}},
        workspace_name = "ws",
    )
    env.expect.that_str(shape_b.build).contains('name = "_pkg_foo_s0",')
    pkg_foo_1_block = shape_b.build.split('name = "_pkg_foo_s0"')[1].split("\n)")[0]
    env.expect.that_str(pkg_foo_1_block).contains('actual = "@ws__pkg_foo//:pkg_s0",')
    env.expect.that_str(pkg_foo_1_block).contains('"@ws__pkg_foo//:[opt]_s0",')
    pkg_block_b = shape_b.build.split('name = "pkg"')[1].split("\n)")[0]
    env.expect.that_str(pkg_block_b).contains('"@ws__state//:is_cpu": ":_pkg_foo_s0",')
    env.expect.that_str(pkg_block_b).contains('"@ws__state//:is_gpu": "@ws__pkg_foo//:pkg_s1",')
    env.expect.that_str(pkg_block_b).contains('"//conditions:default": "@ws__pkg_foo//:pkg_s1",')
    env.expect.that_bool("[opt]" in pkg_block_b).equals(False)
    env.expect.that_bool("_pkg_foo_s1" in shape_b.build).equals(False)

    # Shape C: disjoint constraints (base under is_a, extra under is_b).
    disjoint_base = effective_base_target_dict({
        "base_target": {"is_a": "foo"},
        "extras": {"opt": {"is_b": "foo[opt]"}},
    })
    shape_c = _pin_build(
        target_name = "foo",
        pin_target_dict = disjoint_base,
        extras_dict = {"opt": {"is_b": "foo[opt]"}},
        workspace_name = "ws",
    )
    pkg_block_c = shape_c.build.split('name = "pkg"')[1].split("\n)")[0]
    env.expect.that_str(pkg_block_c).contains('"@ws__state//:is_is_a": "@ws__pkg_foo//:pkg",')
    env.expect.that_str(pkg_block_c).contains('"@ws__state//:is_is_b": "@ws__pkg_foo//:pkg",')
    env.expect.that_str(pkg_block_c).contains('"@ws__state//:is_is_b": [')
    env.expect.that_str(pkg_block_c).contains('"@ws__pkg_foo//:[opt]",')
    env.expect.that_str(pkg_block_c).contains('"//conditions:default": [],')

    # Shape D: direct extra with availability_markers (single marker, variant + marker match_all, multi-marker match_any).
    ev_win = marker_evaluator_name("sys_platform == 'win32'", "")
    ev_linux = marker_evaluator_name("sys_platform == 'linux'", "")
    ev_darwin = marker_evaluator_name("sys_platform == 'darwin'", "")
    shape_d = _pin_build(
        target_name = "foo",
        pin_target_dict = {"": "foo"},
        extras_dict = {
            "win": {"": "foo[win]"},
            "var_win": {"extra_a": "foo[var-win]"},
            "unix": {"": "foo[unix]"},
        },
        workspace_name = "ws",
        packages = {
            "foo": {},
            "foo[win]": {"availability_markers": ["sys_platform == 'win32'"]},
            "foo[var-win]": {"availability_markers": ["sys_platform == 'win32'"]},
            "foo[unix]": {"availability_markers": ["sys_platform == 'linux'", "sys_platform == 'darwin'"]},
        },
    )
    env.expect.that_str(shape_d.build).contains('load("@bazel_skylib//lib:selects.bzl", "selects")')
    env.expect.that_str(shape_d.build).contains('"//_markers:{}_match": ['.format(ev_win))
    env.expect.that_str(shape_d.build).contains("match_all = [")
    env.expect.that_str(shape_d.build).contains('"@ws__state//:is_extra_a",')
    env.expect.that_str(shape_d.build).contains('"//_markers:{}_match",'.format(ev_win))
    env.expect.that_str(shape_d.build).contains('name = "_extra_avail_foo_unix_",')
    env.expect.that_str(shape_d.build).contains("match_any = [")
    env.expect.that_str(shape_d.build).contains('"//_markers:{}_match",'.format(ev_linux))
    env.expect.that_str(shape_d.build).contains('"//_markers:{}_match",'.format(ev_darwin))

    # Multi-constraint same extra emits match_any without duplicate labels in deps.
    multi_c = _pin_build(
        target_name = "foo",
        pin_target_dict = {"": "foo"},
        extras_dict = {"opt": {"is_a": "foo[opt]", "is_b": "foo[opt]"}},
        workspace_name = "ws",
    )
    env.expect.that_str(multi_c.build).contains('load("@bazel_skylib//lib:selects.bzl", "selects")')
    env.expect.that_str(multi_c.build).contains("match_any = [")
    pkg_block_mc = multi_c.build.split('name = "pkg"')[1].split("\n)")[0]
    env.expect.that_int(pkg_block_mc.count('"@ws__pkg_foo//:[opt]"')).equals(1)

    # append_root_aliases emits pkg[] iff group["extras"] is non-empty.
    root_lines = []
    append_root_aliases(
        root_lines,
        {
            "bare": {"base_target": {"": "bare"}, "extras": {}},
            "with-extra": {"base_target": {"": "with-extra"}, "extras": {"opt": {"": "with-extra[opt]"}}},
        },
    )
    root_text = "\n".join(root_lines)
    env.expect.that_bool('name = "bare[]"' in root_text).equals(False)
    env.expect.that_bool('name = "with-extra[]"' in root_text).equals(True)

    # Forked base + compound variant-gated extra: no _unselected_ or extra_alpha_* in
    # pkg/wheel/[] selects, and each slot branch gets its own conditional extra dep.
    fork_res_exprs = {
        "res_py_lt_310": "python_version < '3.10'",
        "res_py_ge_310": "python_version >= '3.10'",
        "extra_alpha_res_py_lt_310": {"variant": "extra_alpha", "marker": "res_py_lt_310"},
        "extra_alpha_res_py_ge_310": {"variant": "extra_alpha", "marker": "res_py_ge_310"},
    }
    fork_fallbacks = variant_fallbacks({
        "extra_alpha": ["alpha_beta"],
        "extra_alpha_res_py_lt_310": ["alpha_beta"],
        "extra_alpha_res_py_ge_310": ["alpha_beta"],
    })
    fork_compound_base = effective_base_target_dict(
        {
            "base_target": {"res_py_lt_310": "foo@s0", "res_py_ge_310": "foo@s1"},
            "extras": {
                "opt": {
                    "extra_alpha_res_py_lt_310": "foo[opt]@s0",
                    "extra_alpha_res_py_ge_310": "foo[opt]@s1",
                },
            },
        },
        resolution_marker_exprs = fork_res_exprs,
        variant_constraints = fork_fallbacks.sets,
    )
    fork_compound = _pin_build(
        target_name = "foo",
        pin_target_dict = fork_compound_base,
        extras_dict = {
            "opt": {
                "extra_alpha_res_py_lt_310": "foo[opt]@s0",
                "extra_alpha_res_py_ge_310": "foo[opt]@s1",
            },
        },
        workspace_name = "ws",
        no_variant_fallbacks = fork_fallbacks,
        resolution_marker_exprs = fork_res_exprs,
    )
    for target_hdr in ('name = "pkg"', 'name = "wheel"', 'name = "[]"'):
        block = fork_compound.build.split(target_hdr)[1].split("\n)")[0]
        env.expect.that_bool("_unselected_" in block).equals(False)
        env.expect.that_bool("extra_alpha" in block).equals(False)
    fc_pkg_1 = fork_compound.build.split('name = "_pkg_foo_s0"')[1].split("\n)")[0]
    env.expect.that_str(fc_pkg_1).contains('"//_markers:is_extra_alpha_res_py_lt_310": [')
    env.expect.that_str(fc_pkg_1).contains('"@ws__pkg_foo//:[opt]_s0",')
    env.expect.that_str(fc_pkg_1).contains('"//conditions:default": [],')
    fc_pkg_2 = fork_compound.build.split('name = "_pkg_foo_s1"')[1].split("\n)")[0]
    env.expect.that_str(fc_pkg_2).contains('"//_markers:is_extra_alpha_res_py_ge_310": [')
    env.expect.that_str(fc_pkg_2).contains('"@ws__pkg_foo//:[opt]_s1",')
    env.expect.that_str(fc_pkg_2).contains('"//conditions:default": [],')

    # Forked base + plain variant extra attaches only to the matching slot branch.
    fork_plain_base = effective_base_target_dict(
        {
            "base_target": {"res_py_lt_310": "foo@s0", "res_py_ge_310": "foo@s1"},
            "extras": {"opt": {"extra_alpha": "foo[opt]@s1"}},
        },
        resolution_marker_exprs = fork_res_exprs,
        variant_constraints = fork_fallbacks.sets,
    )
    fork_plain = _pin_build(
        target_name = "foo",
        pin_target_dict = fork_plain_base,
        extras_dict = {"opt": {"extra_alpha": "foo[opt]@s1"}},
        workspace_name = "ws",
        no_variant_fallbacks = fork_fallbacks,
        resolution_marker_exprs = fork_res_exprs,
    )
    fp_pkg = fork_plain.build.split('name = "pkg"')[1].split("\n)")[0]
    env.expect.that_bool("_unselected_" in fp_pkg).equals(False)
    env.expect.that_bool("extra_alpha" in fp_pkg).equals(False)
    env.expect.that_str(fp_pkg).contains('"//_markers:is_res_py_lt_310": "@ws__pkg_foo//:pkg_s0",')
    env.expect.that_str(fp_pkg).contains('"//_markers:is_res_py_ge_310": ":_pkg_foo_s1",')
    fp_pkg_2 = fork_plain.build.split('name = "_pkg_foo_s1"')[1].split("\n)")[0]
    env.expect.that_str(fp_pkg_2).contains('"@ws__state//:is_extra_alpha": [')
    env.expect.that_str(fp_pkg_2).contains('"@ws__pkg_foo//:[opt]_s1",')

    # Multi-version pin with orthogonal extra on non-default + default branches shares _pkg_foo_s1.
    ortho = _pin_build(
        target_name = "foo",
        pin_target_dict = {"cpu": "foo@s0", "gpu": "foo@s1", "": "foo@s1"},
        extras_dict = {"opt": {"extra_x": "foo[opt]@s1"}},
        workspace_name = "ws",
    )
    ortho_pkg = ortho.build.split('name = "pkg"')[1].split("\n)")[0]
    env.expect.that_str(ortho_pkg).contains('"@ws__state//:is_cpu": "@ws__pkg_foo//:pkg_s0",')
    env.expect.that_str(ortho_pkg).contains('"@ws__state//:is_gpu": ":_pkg_foo_s1",')
    env.expect.that_str(ortho_pkg).contains('"//conditions:default": ":_pkg_foo_s1",')
    env.expect.that_int(ortho.build.count('name = "_pkg_foo_s1"')).equals(1)
    ortho_pkg_2 = ortho.build.split('name = "_pkg_foo_s1"')[1].split("\n)")[0]
    env.expect.that_str(ortho_pkg_2).contains('"@ws__state//:is_extra_x": [')
    env.expect.that_str(ortho_pkg_2).contains('"@ws__pkg_foo//:[opt]_s1",')

    # Multi-version testonly pin propagates testonly = True to _pkg_* and :[] with and without transition.
    for trans_bzl in (None, "//:_transition.bzl"):
        to_res = _pin_build(
            target_name = "foo",
            pin_target_dict = {"cpu": "foo@s0", "gpu": "foo@s1"},
            extras_dict = {"opt": {"cpu": "foo[opt]@s0", "gpu": "foo[opt]@s1"}},
            workspace_name = "ws",
            transition_bzl = trans_bzl,
            testonly = True,
        )
        helper_src = to_res.actual_build if trans_bzl else to_res.build
        env.expect.that_str(helper_src.split('name = "_pkg_foo_s0"')[1].split("\n)")[0]).contains("testonly = True,")
        env.expect.that_str(helper_src.split('name = "_pkg_foo_s1"')[1].split("\n)")[0]).contains("testonly = True,")
        env.expect.that_str(to_res.build.split('name = "[]"')[1].split("\n)")[0]).contains("testonly = True,")

def _test_pin_build_direct_extras_aggregation_shapes(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_direct_extras_aggregation_shapes_impl)

def thin_package_repo_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_effective_base_target_dict_all_shapes,
            _test_pin_build_direct_extras_aggregation_shapes,
            _test_variants_build_shared_flag,
            _test_variants_build_repo_default,
            _test_variants_build_shared_flag_pinned,
            _test_variants_build_hidden_flags,
            _test_pin_build_member_availability_markers,
            _test_cargo_build_filters_backends_and_wildcards,
            _test_modules_mapping_deps_selection,
            _test_partial_fork_maybe_and_testonly,
            _test_requirement_extra_canon,
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
