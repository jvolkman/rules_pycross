"""Tests for free-threaded (PEP 703) target platforms and wheel selection."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:pep508_marker_values.bzl", "FREETHREADED_VALUES")

# buildifier: disable=bzl-visibility
load("//pycross/private:target_platform.bzl", "PycrossTargetPlatformInfo", "pycross_target_platform")

# buildifier: disable=bzl-visibility
load("//pycross/private:wheel_chooser.bzl", "pycross_wheel_chooser")

_PY_FREETHREADED = str(Label("@rules_python//python/config_settings:py_freethreaded"))
_PYTHON_VERSION = str(Label("@rules_python//python/config_settings:python_version"))

_FREETHREADED = {_PYTHON_VERSION: "3.14", _PY_FREETHREADED: "yes"}
_GIL = {_PYTHON_VERSION: "3.14", _PY_FREETHREADED: "no"}

_PLATFORM = "manylinux_2_17_x86_64"
_CP314T = "pkg-1.0-cp314-cp314t-manylinux_2_17_x86_64.whl"
_CP314 = "pkg-1.0-cp314-cp314-manylinux_2_17_x86_64.whl"
_ABI3 = "pkg-1.0-cp39-abi3-manylinux_2_17_x86_64.whl"
_PURE = "pkg-1.0-py3-none-any.whl"

def _platform(name):
    util.helper_target(
        pycross_target_platform,
        name = name + "_platform",
        freethreaded = select(FREETHREADED_VALUES),
        platforms = [_PLATFORM],
    )
    return name + "_platform"

def _chooser(name, candidates):
    util.helper_target(
        pycross_wheel_chooser,
        name = name + "_chooser",
        candidates = candidates,
        supported_tags = _platform(name),
    )
    return name + "_chooser"

def _test_freethreaded_tags_impl(env, target):
    info = target[PycrossTargetPlatformInfo]
    env.expect.that_collection(info.abis).contains_exactly(["cp314t"])
    tags = env.expect.that_collection(info.compatibility_tags)
    tags.contains("cp314-cp314t-" + _PLATFORM)
    tags.contains("py3-none-any")
    tags.not_contains("cp314-cp314-" + _PLATFORM)
    env.expect.that_collection([t for t in info.compatibility_tags if "-abi3-" in t]).contains_exactly([])

def _test_freethreaded_tags(name):
    analysis_test(
        name = name,
        target = _platform(name),
        impl = _test_freethreaded_tags_impl,
        config_settings = _FREETHREADED,
    )

def _test_gil_tags_impl(env, target):
    info = target[PycrossTargetPlatformInfo]
    env.expect.that_collection(info.abis).contains_exactly(["cp314"])
    tags = env.expect.that_collection(info.compatibility_tags)
    tags.contains("cp314-cp314-" + _PLATFORM)
    tags.contains("cp314-abi3-" + _PLATFORM)
    tags.not_contains("cp314-cp314t-" + _PLATFORM)

def _test_gil_tags(name):
    analysis_test(
        name = name,
        target = _platform(name),
        impl = _test_gil_tags_impl,
        config_settings = _GIL,
    )

def _chooser_test(name, candidates, config_settings, expected):
    def impl(env, target):
        env.expect.that_str(target[config_common.FeatureFlagInfo].value).equals(expected)

    analysis_test(
        name = name,
        target = _chooser(name, candidates),
        impl = impl,
        config_settings = config_settings,
    )

def _test_freethreaded_chooser_prefers_cp314t(name):
    _chooser_test(name, [_PURE, _ABI3, _CP314, _CP314T], _FREETHREADED, _CP314T)

def _test_freethreaded_chooser_falls_back_to_pure(name):
    _chooser_test(name, [_ABI3, _CP314, _PURE], _FREETHREADED, _PURE)

def _test_freethreaded_chooser_no_match(name):
    _chooser_test(name, [_ABI3, _CP314], _FREETHREADED, "__no_matching_wheel__")

def _test_gil_chooser_prefers_cp314(name):
    _chooser_test(name, [_PURE, _ABI3, _CP314T, _CP314], _GIL, _CP314)

def freethreaded_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_freethreaded_tags,
            _test_gil_tags,
            _test_freethreaded_chooser_prefers_cp314t,
            _test_freethreaded_chooser_falls_back_to_pure,
            _test_freethreaded_chooser_no_match,
            _test_gil_chooser_prefers_cp314,
        ],
    )
