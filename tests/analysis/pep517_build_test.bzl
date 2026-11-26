"""Tests for pep517_build"""

load("@rules_python//python:defs.bzl", "PyInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:providers.bzl", "PycrossPackageInfo")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/actions:pep517_action.bzl", "validate_build_requires")

# buildifier: disable=bzl-visibility
load("//pycross/private/build/rules:pep517_build.bzl", "pep517_build")

def _mock_pkg_impl(ctx):
    return [
        PycrossPackageInfo(package_name = ctx.attr.package_name, package_version = "1.0"),
        DefaultInfo(),
        PyInfo(has_py2_only_sources = False, has_py3_only_sources = True, transitive_sources = depset([])),
    ]

_mock_pkg = rule(
    implementation = _mock_pkg_impl,
    attrs = {"package_name": attr.string()},
)

def _mock_sdist_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".tar.gz")
    ctx.actions.write(out, "dummy")
    return [DefaultInfo(files = depset([out]))]

_mock_sdist = rule(implementation = _mock_sdist_impl)

def _test_pep517_build_valid_deps(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(_mock_pkg, name = name + "_hatchling", package_name = "hatchling")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        required_build_packages = ["hatchling"],
        build_requires = ["hatchling>=1.0"],
        build_deps = [name + "_hatchling"],
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_pep517_build_valid_deps_impl)

# buildifier: disable=unused-variable
def _test_pep517_build_valid_deps_impl(env, target):
    pass

def _test_pep517_build_invalid_deps(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        required_build_packages = ["hatchling"],
        build_deps = [],
        whldir_name = "pkg-1.0.whldir",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pep517_build_invalid_deps_impl,
    )

def _test_pep517_build_invalid_deps_impl(env, target):
    wheel_dir = target[DefaultInfo].files.to_list()[0]
    env.expect.that_bool(wheel_dir.is_directory).equals(True)
    env.expect.that_str(wheel_dir.basename).equals("pkg-1.0.whldir")
    env.expect.that_target(target).output_group("raw_wheel").contains_exactly([wheel_dir.short_path])

    action = env.expect.that_target(target).action_generating(wheel_dir.short_path)
    action.mnemonic().equals("PycrossSdistBuildConfigError")
    action.env().contains_exactly({
        "PYCROSS_ERROR": "Cannot build {}_sdist.tar.gz from source:\n".format(target.label.name.removesuffix("_subject")) +
                         "Missing required build-system packages: hatchling. " +
                         "These are listed in build-system.requires but are not present in build_deps. " +
                         "Make sure they are included in your lockfile.",
    })

    # The real build should not be registered.
    env.expect.that_bool(
        any([a.mnemonic == "PycrossPep517Build" for a in target.actions]),
    ).equals(False)

def _test_pep517_build_basic(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        config_settings = {"--build-option": ["--pure"]},
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_pep517_build_basic_impl)

def _main_config(target):
    actions = [a for a in target.actions if a.mnemonic == "FileWrite" and any([o.basename.endswith("_config.json") for o in a.outputs.to_list()])]
    if len(actions) != 1:
        fail("Expected 1 main config FileWrite action, got {}".format(len(actions)))
    return json.decode(actions[0].content)

# buildifier: disable=unused-variable
def _test_pep517_build_basic_impl(env, target):
    env.expect.that_target(target).has_provider(DefaultInfo)
    env.expect.that_target(target).has_provider(OutputGroupInfo)

    wheel_dir = target[DefaultInfo].files.to_list()[0]
    env.expect.that_bool(wheel_dir.is_directory).equals(True)

    # config_settings are inlined into the main config JSON (no separate config_settings.json action).
    cs_actions = [a for a in target.actions if a.mnemonic == "FileWrite" and any([o.basename == "config_settings.json" for o in a.outputs.to_list()])]
    env.expect.that_int(len(cs_actions)).equals(0)

    cfg = _main_config(target)
    env.expect.that_dict(cfg["config_settings"]).contains_exactly({"--build-option": ["--pure"]})
    env.expect.that_bool("config_settings_raw" in cfg).equals(False)

    # PYTHONPATH must not be set on action_env (context.py scrubs it and python_paths carries it).
    build_action = [a for a in target.actions if a.mnemonic == "PycrossPep517Build"][0]
    env.expect.that_bool("PYTHONPATH" in build_action.env).equals(False)

def _test_pep517_build_config_settings_data_location(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(_mock_sdist, name = name + "_data")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        data = [name + "_data"],
        config_settings = {"--config": ["$(location " + name + "_data)"]},
        build_env = {"DATA_FILE": "$(location " + name + "_data)"},
        resource_size = "medium",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pep517_build_config_settings_data_location_impl,
    )

def _test_pep517_build_config_settings_data_location_impl(env, target):
    cfg = _main_config(target)
    settings = cfg["config_settings"]
    expected_suffix = target.label.name.removesuffix("_subject") + "_data.tar.gz"
    env.expect.that_int(len(settings["--config"])).equals(1)
    env.expect.that_bool(settings["--config"][0].endswith(expected_suffix)).equals(True)
    env.expect.that_bool("$(location" in settings["--config"][0]).equals(False)

    # User build_env stays in main_config["build_env"]; programmatic env (MAKEFLAGS) stays on action_env.
    env.expect.that_bool(cfg["build_env"]["DATA_FILE"].endswith(expected_suffix)).equals(True)
    env.expect.that_bool("MAKEFLAGS" in cfg["build_env"]).equals(False)
    build_action = env.expect.that_target(target).action_named("PycrossPep517Build")
    build_action.env().contains_at_least({"MAKEFLAGS": "-j6"})

def _test_pep517_build_resources(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
        resource_size = "medium",
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_pep517_build_resources_impl)

# buildifier: disable=unused-variable
def _test_pep517_build_resources_impl(env, target):
    action = env.expect.that_target(target).action_named("PycrossPep517Build")
    action.env().contains_at_least({"MAKEFLAGS": "-j6"})

def _test_pep517_build_scratch_dirs(name):
    util.helper_target(_mock_sdist, name = name + "_sdist")
    util.helper_target(
        pep517_build,
        name = name + "_subject",
        sdist = name + "_sdist",
    )
    analysis_test(name = name, target = name + "_subject", impl = _test_pep517_build_scratch_dirs_impl)

def _test_pep517_build_scratch_dirs_impl(env, target):
    # Scratch dirs live next to the wheel output so they are unique per
    # repo/package/target (the builder wipes them before use).
    build = [a for a in target.actions if a.mnemonic == "PycrossPep517Build"][0]
    out_dir = build.outputs.to_list()[0].dirname
    env.expect.that_str(out_dir).contains(target.label.name)
    action = env.expect.that_target(target).action_named("PycrossPep517Build")
    action.env().contains_at_least({
        "PYCROSS_BUILD_ROOT": out_dir + "/_tmp",
        "PYCROSS_SDIST_DIR": out_dir + "/sdist",
    })

def _test_validate_build_requires(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_validate_build_requires_impl)

# buildifier: disable=unused-variable
def _test_validate_build_requires_impl(env, target):
    """validate_build_requires checks resolved PycrossPackageInfo versions against PEP 508 specifiers."""

    def _dep(name, version):
        return {PycrossPackageInfo: PycrossPackageInfo(package_name = name, package_version = version)}

    # 1. Single mismatch
    w_mismatch = validate_build_requires(
        ["numpy>=1.20"],
        [_dep("numpy", "1.19.0")],
        "my_pkg-1.0.tar.gz",
    )
    env.expect.that_collection(w_mismatch).contains_exactly([
        "WARNING: The build environment provides 'numpy==1.19.0', but 'my_pkg-1.0.tar.gz' requires 'numpy>=1.20' in pyproject.toml.",
    ])

    # 2. Match, canonical name normalization, markers, specifierless, missing, and non-PEP-440 version
    w_match = validate_build_requires(
        [
            "numpy>=1.20",
            "setuptools[ssl]>=40; python_version >= '3.8'",
            "wheel",
            "unknown-pkg>=99.0",
            "custom-pkg>=1.0",
        ],
        [
            _dep("NumPy", "1.21.0"),
            _dep("setuptools", "30.0.0"),
            _dep("wheel", "0.45.0"),
            _dep("custom-pkg", "not-a-pep440-version"),
            {},  # target without PycrossPackageInfo
        ],
        "my_pkg-1.0.tar.gz",
    )
    env.expect.that_collection(w_match).contains_exactly([])

    # 3. oldest-supported-numpy uses calendar versions and is skipped (no false-positive warning).
    w_oldest = validate_build_requires(
        ["oldest-supported-numpy>=2022.1"],
        [_dep("numpy", "1.26.4")],
        "my_pkg-1.0.tar.gz",
    )
    env.expect.that_collection(w_oldest).contains_exactly([])

    # 4. Multiple resolved versions: no warning if any satisfies; plural warning if none satisfy.
    w_multi_ok = validate_build_requires(
        ["setuptools>=70.0"],
        [_dep("setuptools", "68.0.0"), _dep("setuptools", "75.1.0")],
        "my_pkg-1.0.tar.gz",
    )
    env.expect.that_collection(w_multi_ok).contains_exactly([])

    w_multi_bad = validate_build_requires(
        ["setuptools>=80.0"],
        [_dep("setuptools", "68.0.0"), _dep("setuptools", "75.1.0")],
        "my_pkg-1.0.tar.gz",
    )
    env.expect.that_collection(w_multi_bad).contains_exactly([
        "WARNING: None of the provided 'setuptools' versions (68.0.0, 75.1.0) satisfy 'setuptools>=80.0' required by 'my_pkg-1.0.tar.gz' in pyproject.toml.",
    ])

def pep517_build_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pep517_build_valid_deps,
            _test_pep517_build_invalid_deps,
            _test_pep517_build_basic,
            _test_pep517_build_config_settings_data_location,
            _test_pep517_build_resources,
            _test_pep517_build_scratch_dirs,
            _test_validate_build_requires,
        ],
    )
