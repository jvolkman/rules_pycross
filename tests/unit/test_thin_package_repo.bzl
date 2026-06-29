"""Tests for _pin_build from thin_package_repo.bzl"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:thin_package_repo.bzl", "pin_build_for_testing")

# ── Test: no platform → non-transitioning proxies ──────────────────

# buildifier: disable=unused-variable
def _test_pin_build_no_transition_impl(env, target):
    """Without target_platform, should use pycross_library_proxy / pycross_file_proxy."""
    res = pin_build_for_testing(
        target_name = "numpy",
        pin_target_dict = {"": "numpy@1.26.0"},
        package = {},
        workspace_repo = "my_workspace",
    )

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
        package = {},
        workspace_repo = "my_workspace",
        target_platform = "@my//platform:linux",
    )

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
        package = {},
        workspace_repo = "ws",
    )
    res_with_platform = pin_build_for_testing(
        target_name = "foo",
        pin_target_dict = {"": "foo@1.0"},
        package = {},
        workspace_repo = "ws",
        target_platform = "//:my_platform",
    )

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
        package = {},
        workspace_repo = "my_workspace",
        extras_dict = {"gpu": {"": "numpy[gpu]@1.26.0"}},
        target_platform = "@my//platform:linux",
    )

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
        package = {"sdist_file": {"key": "numpy_sdist"}},
        workspace_repo = "my_workspace",
        target_platform = "@my//platform:linux",
    )

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
    res = pin_build_for_testing(
        target_name = "numpy",
        pin_target_dict = {
            "cpu": "numpy@1.26.0",
            "gpu": "numpy@1.26.0+gpu",
        },
        package = {},
        workspace_repo = "my_workspace",
        has_aggregated_variant = True,
        extras_dict = {"extra1": {"cpu": "numpy[extra1]@1.26.0", "gpu": "numpy[extra1]@1.26.0+gpu"}},
        default_variants = {"cpu": True},
        target_platform = "@my//platform:linux",
    )

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

    # Extras with variants should also use select
    extra_section = res.split('name = "[extra1]"')[1].split(")")[0]
    env.expect.that_bool("select({" in extra_section).equals(True)

    # //conditions:default should be set to the default variant (cpu)
    env.expect.that_bool('"//conditions:default":' in res).equals(True)

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
        package = {},
        workspace_repo = "ws",
    )

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

# ── Test: transition_bzl → per-package uses non-transitioning rules ─

# buildifier: disable=unused-variable
def _test_pin_build_with_transition_bzl_impl(env, target):
    """When transition_bzl is set, per-package BUILD uses non-transitioning rules (transition applied at root)."""
    res = pin_build_for_testing(
        target_name = "numpy",
        pin_target_dict = {"": "numpy@1.26.0"},
        package = {"sdist_file": {"key": "numpy_sdist"}},
        workspace_repo = "my_workspace",
        extras_dict = {"gpu": {"": "numpy[gpu]@1.26.0"}},
        target_platform = "//:_internal_platform",
        transition_bzl = "//:_transition.bzl",
    )

    # Should load non-transitioning rules (transition is at root, not here)
    load_line = [line for line in res.split("\n") if line.startswith("load(")][0]
    env.expect.that_bool('"pycross_library_proxy"' in load_line).equals(True)
    env.expect.that_bool('"pycross_file_proxy"' in load_line).equals(True)
    env.expect.that_bool("transitioning" not in load_line).equals(True)

    # Should NOT have any platform = lines (non-transitioning rules don't have platform attr)
    env.expect.that_bool("platform =" not in res).equals(True)

    # Should still have the expected targets
    env.expect.that_bool('name = "pkg"' in res).equals(True)
    env.expect.that_bool('name = "wheel"' in res).equals(True)
    env.expect.that_bool('name = "dist_info"' in res).equals(True)
    env.expect.that_bool('name = "sdist"' in res).equals(True)
    env.expect.that_bool('name = "[gpu]"' in res).equals(True)

def _test_pin_build_with_transition_bzl(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pin_build_with_transition_bzl_impl)

# ── Test suite ─────────────────────────────────────────────────────

def thin_package_repo_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pin_build_no_transition,
            _test_pin_build_with_platform,
            _test_pin_build_transition_loads,
            _test_pin_build_extras_with_platform,
            _test_pin_build_sdist_with_platform,
            _test_pin_build_variants_with_platform,
            _test_pin_build_basic_structure,
            _test_pin_build_with_transition_bzl,
        ],
    )
