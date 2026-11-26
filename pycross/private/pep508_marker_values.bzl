"""PEP 508 marker constants, environment rule, and collection helpers.

Platform and Python toolchain marker values are resolved once per Bazel
configuration by the `//pycross/private/markers:env` target (`pep508_env`),
which provides `Pep508EnvInfo`. Rules that evaluate PEP 508 markers (such as
`_pycross_pep508_evaluator`, `_pycross_cycle_dep_needed`, and
`_pycross_target_platform`) depend on that single target via
`marker_value_attrs()` instead of resolving separate marker targets and the
Python toolchain on every rule instance.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@pypackaging.bzl", "pypackaging")
load(":providers.bzl", "VariantStateInfo")

# Maps @platforms//os constraint values to PEP 508 sys_platform values.
# Synced with rules_python's pep508_env.bzl sys_platform_select_map.
SYS_PLATFORM_VALUES = {
    "@platforms//os:android": "android",
    "@platforms//os:emscripten": "emscripten",
    "@platforms//os:freebsd": "freebsd",
    "@platforms//os:ios": "ios",
    "@platforms//os:linux": "linux",
    "@platforms//os:openbsd": "openbsd",
    "@platforms//os:osx": "darwin",
    "@platforms//os:wasi": "wasi",
    "@platforms//os:windows": "win32",
    "//conditions:default": "",
}

# Maps @platforms//os constraint values to PEP 508 os_name values.
# Synced with rules_python's pep508_env.bzl os_name_select_map.
# Everything non-Windows is "posix" (including the default).
OS_NAME_VALUES = {
    "@platforms//os:windows": "nt",
    "//conditions:default": "posix",
}

# Maps @platforms//os constraint values to PEP 508 platform_system values.
# Synced with rules_python's pep508_env.bzl platform_system_select_map.
PLATFORM_SYSTEM_VALUES = {
    "@platforms//os:android": "Android",
    "@platforms//os:freebsd": "FreeBSD",
    "@platforms//os:ios": "iOS",
    "@platforms//os:linux": "Linux",
    "@platforms//os:netbsd": "NetBSD",
    "@platforms//os:openbsd": "OpenBSD",
    "@platforms//os:osx": "Darwin",
    "@platforms//os:windows": "Windows",
    "//conditions:default": "",
}

# Maps platform constraints to PEP 508 platform_machine values.
# Synced with rules_python's pep508_env.bzl platform_machine_select_map,
# with one important difference: aarch64 handling.
#
# Python's platform.machine() reports different values for aarch64 depending
# on the OS: "aarch64" on Linux/Android, "arm64" on macOS/iOS, "ARM64" on
# Windows. We use compound config_settings (OS + CPU) from
# //pycross/private:BUILD.bazel to resolve the correct value.
# rules_python maps aarch64 uniformly to "aarch64" regardless of OS.
#
# All other architectures have consistent names across OSes.
PLATFORM_MACHINE_VALUES = {
    # OS-specific aarch64 handling (more correct than rules_python).
    "@rules_pycross//pycross/private:is_linux_aarch64": "aarch64",
    "@rules_pycross//pycross/private:is_macos_aarch64": "arm64",
    "@rules_pycross//pycross/private:is_windows_aarch64": "ARM64",
    # Fallback for other OSes on aarch64 (e.g., FreeBSD, Android, iOS).
    "@platforms//cpu:aarch64": "aarch64",
    # All other CPUs.
    "@platforms//cpu:aarch32": "aarch32",
    "@platforms//cpu:armv7": "armv7",
    "@platforms//cpu:i386": "i386",
    "@platforms//cpu:ppc": "ppc",
    "@platforms//cpu:ppc64le": "ppc64le",
    "@platforms//cpu:riscv64": "riscv64",
    "@platforms//cpu:s390x": "s390x",
    "@platforms//cpu:wasm32": "wasm32",
    "@platforms//cpu:wasm64": "wasm64",
    "@platforms//cpu:x86_32": "x86_32",
    "@platforms//cpu:x86_64": "x86_64",
    "//conditions:default": "",
}

# Maps rules_python libc flag to a libc identifier.
# Used by the wheel chooser to distinguish manylinux vs musllinux wheels.
LIBC_VALUES = {
    "@rules_python//python/config_settings:_is_py_linux_libc_glibc": "glibc",
    "@rules_python//python/config_settings:_is_py_linux_libc_musl": "musl",
    "//conditions:default": "",
}

# Maps rules_python freethreaded flag to a boolean-like string.
# Used by the wheel chooser to match cp313t (freethreaded) vs cp313 tags.
FREETHREADED_VALUES = {
    "@rules_python//python/config_settings:_is_py_freethreaded_yes": "yes",
    "@rules_python//python/config_settings:_is_py_freethreaded_no": "no",
    "//conditions:default": "no",
}

PYTHON_TOOLCHAIN_TYPE = Label("@rules_python//python:toolchain_type")

DEFAULT_PEP508_IMPLEMENTATION_NAME = "cpython"
DEFAULT_PEP508_PLATFORM_PYTHON_IMPLEMENTATION = "CPython"
DEFAULT_PEP508_PLATFORM_RELEASE = ""
DEFAULT_PEP508_PLATFORM_VERSION = ""

Pep508EnvInfo = provider(
    doc = "Resolved baseline PEP 508 environment markers for a Bazel configuration.",
    fields = {
        "markers": "Dict of baseline PEP 508 marker values (with extra = '') for this configuration.",
        "flag_platform_python_implementation": (
            "Raw value of //pycross/settings:pep508_platform_python_implementation, " +
            "used to preserve derivation precedence when implementation_name is overridden."
        ),
    },
)

def flag_value(target):
    """Read a flag value from either FeatureFlagInfo or BuildSettingInfo.

    Args:
        target: A target providing FeatureFlagInfo or BuildSettingInfo.

    Returns:
        The string value of the flag, or empty string if neither provider is found.
    """
    if config_common.FeatureFlagInfo in target:
        return target[config_common.FeatureFlagInfo].value
    if BuildSettingInfo in target:
        return target[BuildSettingInfo].value
    return ""

def marker_value_attrs():
    """Returns rule attrs for consuming the resolved PEP 508 marker environment.

    Consumers depend on the single `//pycross/private/markers:env` target and do
    not need to declare `toolchains = [PYTHON_TOOLCHAIN_TYPE]`. Optional string
    attributes allow callers and unit tests to override individual marker
    dimensions.

    Usage in a rule definition:
        _my_rule = rule(
            attrs = {
                "expr": attr.string(),
            } | marker_value_attrs(),
        )
    """
    return {
        "os_name": attr.string(default = ""),
        "sys_platform": attr.string(default = ""),
        "platform_machine": attr.string(default = ""),
        "platform_system": attr.string(default = ""),
        "platform_release": attr.string(default = ""),
        "platform_version": attr.string(default = ""),
        "python_version": attr.string(default = ""),
        "python_full_version": attr.string(default = ""),
        "implementation_name": attr.string(default = ""),
        "implementation_version": attr.string(default = ""),
        "platform_python_implementation": attr.string(default = ""),
        "extra": attr.string(default = ""),
        "variants": attr.label_list(
            default = [],
            providers = [[VariantStateInfo], [config_common.FeatureFlagInfo]],
        ),
        "_pep508_env": attr.label(
            default = Label("//pycross/private/markers:env"),
            providers = [Pep508EnvInfo],
        ),
    }

def _toolchain_py3_runtime(ctx):
    if PYTHON_TOOLCHAIN_TYPE not in ctx.toolchains:
        return None
    tc = ctx.toolchains[PYTHON_TOOLCHAIN_TYPE]
    if not hasattr(tc, "py3_runtime"):
        return None
    return tc.py3_runtime

def _derive_platform_python_implementation(implementation_name, flag_ppi):
    if flag_ppi and (flag_ppi != DEFAULT_PEP508_PLATFORM_PYTHON_IMPLEMENTATION or implementation_name == DEFAULT_PEP508_IMPLEMENTATION_NAME):
        return flag_ppi
    if implementation_name == DEFAULT_PEP508_IMPLEMENTATION_NAME:
        return DEFAULT_PEP508_PLATFORM_PYTHON_IMPLEMENTATION
    if implementation_name == "pypy":
        return "PyPy"
    return implementation_name

def with_extra(markers_env, extra):
    """Returns a markers dict with its base extra replaced, preserving active variants.

    Active conflict variants are stored alongside the base extra as
    `[base_extra, "__variant_...", ...]`. Replacing the base extra preserves the
    trailing variant entries and returns `markers_env` unchanged when the extra
    already matches.

    Args:
        markers_env: A PEP 508 markers dict.
        extra: The new base extra string (for example, `""` or `"dev"`).

    Returns:
        `markers_env` if already matching, or a shallow copy with updated `"extra"`.
    """
    base_extra = markers_env.get("extra", "")
    if type(base_extra) == "list":
        if base_extra and base_extra[0] == extra:
            return markers_env
        env = dict(markers_env)
        env["extra"] = ([extra] + base_extra[1:]) if base_extra else extra
        return env
    if base_extra == extra:
        return markers_env
    env = dict(markers_env)
    env["extra"] = extra
    return env

def _resolve_extra(ctx):
    active = {}
    for v in getattr(ctx.attr, "variants", []):
        if VariantStateInfo in v:
            for item in v[VariantStateInfo].active_items.keys():
                if item:
                    active[item] = True
        else:
            val = flag_value(v)
            if val:
                active[val] = True
    if not active:
        return ctx.attr.extra
    return [ctx.attr.extra] + ["__variant_" + item for item in sorted(active.keys())]

def collect_markers(ctx):
    """Collects PEP 508 marker values from `Pep508EnvInfo` and any rule overrides.

    When no explicit marker override attributes are set, this returns the
    pre-resolved baseline dict from `//pycross/private/markers:env` directly (or
    a shallow copy when `extra` or `variants` are active). When explicit
    override attributes are set, it applies the same precedence rules as the
    baseline environment.

    Args:
        ctx: The rule context whose attrs include those from `marker_value_attrs()`.

    Returns:
        A dict mapping each PEP 508 marker name to its value.
    """
    env_info = ctx.attr._pep508_env[Pep508EnvInfo]
    base = env_info.markers
    extra = _resolve_extra(ctx)

    has_overrides = bool(
        ctx.attr.os_name or
        ctx.attr.sys_platform or
        ctx.attr.platform_machine or
        ctx.attr.platform_system or
        ctx.attr.platform_release or
        ctx.attr.platform_version or
        ctx.attr.python_version or
        ctx.attr.python_full_version or
        ctx.attr.implementation_name or
        ctx.attr.implementation_version or
        ctx.attr.platform_python_implementation,
    )
    if not has_overrides:
        if extra == "":
            return base
        markers = dict(base)
        markers["extra"] = extra
        return markers

    # 1. Platform markers (explicit attr or pre-resolved baseline)
    os_name = ctx.attr.os_name or base["os_name"]
    sys_platform = ctx.attr.sys_platform or base["sys_platform"]
    platform_machine = ctx.attr.platform_machine or base["platform_machine"]
    platform_system = ctx.attr.platform_system or base["platform_system"]
    platform_release = ctx.attr.platform_release or base["platform_release"]
    platform_version = ctx.attr.platform_version or base["platform_version"]

    # 2. Python version markers (explicit attr or pre-resolved baseline)
    python_version = ctx.attr.python_version
    python_full_version = ctx.attr.python_full_version
    implementation_version = ctx.attr.implementation_version

    # Keep explicit python_version / python_full_version consistent with each
    # other instead of mixing an explicit attr with the baseline toolchain version.
    if python_version or python_full_version:
        if python_full_version and not python_version:
            python_version = ".".join(python_full_version.split(".")[:2])
        elif python_version and not python_full_version:
            if python_version.count(".") >= 2:
                python_full_version = python_version
                python_version = ".".join(python_version.split(".")[:2])
            else:
                python_full_version = python_version + ".0"
        if not implementation_version and python_full_version:
            implementation_version = python_full_version
    else:
        python_version = base["python_version"]
        python_full_version = base["python_full_version"]
        if not implementation_version:
            implementation_version = base["implementation_version"]

    implementation_name = ctx.attr.implementation_name or base["implementation_name"]
    platform_python_implementation = ctx.attr.platform_python_implementation
    if not platform_python_implementation:
        if ctx.attr.implementation_name:
            platform_python_implementation = _derive_platform_python_implementation(
                implementation_name,
                env_info.flag_platform_python_implementation,
            )
        else:
            platform_python_implementation = base["platform_python_implementation"]

    return {
        "os_name": os_name,
        "sys_platform": sys_platform,
        "platform_machine": platform_machine,
        "platform_system": platform_system,
        "platform_release": platform_release,
        "platform_version": platform_version,
        "python_version": python_version,
        "python_full_version": python_full_version,
        "implementation_name": implementation_name,
        "implementation_version": implementation_version,
        "platform_python_implementation": platform_python_implementation,
        "extra": extra,
    }

def _pep508_env_impl(ctx):
    python_version = ""
    python_full_version = ""
    implementation_name = ""

    # Try PyRuntimeInfo from the Python toolchain first (most accurate).
    runtime = _toolchain_py3_runtime(ctx)
    if runtime:
        if hasattr(runtime, "implementation_name") and runtime.implementation_name:
            implementation_name = runtime.implementation_name

        vi = runtime.interpreter_version_info if hasattr(runtime, "interpreter_version_info") else None
        if vi:
            python_version = "{}.{}".format(vi.major, vi.minor)
            python_full_version = pypackaging.markers.format_full_version(vi)

    # Fall back to rules_python and pycross config flags.
    if not python_version:
        python_version = flag_value(ctx.attr._python_version)
    if not python_full_version:
        python_full_version = flag_value(ctx.attr._python_full_version)
    if not implementation_name:
        implementation_name = flag_value(ctx.attr._implementation_name)

    if not implementation_name:
        implementation_name = DEFAULT_PEP508_IMPLEMENTATION_NAME

    flag_ppi = flag_value(ctx.attr._platform_python_implementation)
    platform_python_implementation = _derive_platform_python_implementation(
        implementation_name,
        flag_ppi,
    )

    markers = {
        "os_name": ctx.attr.os_name,
        "sys_platform": ctx.attr.sys_platform,
        "platform_machine": ctx.attr.platform_machine,
        "platform_system": ctx.attr.platform_system,
        "platform_release": flag_value(ctx.attr._platform_release),
        "platform_version": flag_value(ctx.attr._platform_version),
        "python_version": python_version,
        "python_full_version": python_full_version,
        "implementation_name": implementation_name,
        "implementation_version": python_full_version,
        "platform_python_implementation": platform_python_implementation,
        "extra": "",
    }

    return [
        Pep508EnvInfo(
            markers = markers,
            flag_platform_python_implementation = flag_ppi,
        ),
    ]

pep508_env = rule(
    implementation = _pep508_env_impl,
    attrs = {
        "os_name": attr.string(default = ""),
        "sys_platform": attr.string(default = ""),
        "platform_machine": attr.string(default = ""),
        "platform_system": attr.string(default = ""),
        "_platform_release": attr.label(default = Label("//pycross/settings:pep508_platform_release")),
        "_platform_version": attr.label(default = Label("//pycross/settings:pep508_platform_version")),
        "_python_version": attr.label(default = Label("@rules_python//python/config_settings:python_version_major_minor")),
        "_python_full_version": attr.label(default = Label("@rules_python//python/config_settings:python_version")),
        "_implementation_name": attr.label(default = Label("//pycross/settings:pep508_implementation_name")),
        "_platform_python_implementation": attr.label(default = Label("//pycross/settings:pep508_platform_python_implementation")),
    },
    provides = [Pep508EnvInfo],
    toolchains = [PYTHON_TOOLCHAIN_TYPE],
    doc = "Resolves the baseline PEP 508 marker environment once per Bazel configuration.",
)
