""" Adopted from rules_foreign_cc."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cpp_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

CxxToolsInfo = provider(
    doc = "Paths to the C/C++ tools, taken from the toolchain",
    fields = dict(
        cc = "C compiler",
        cxx = "C++ compiler",
        cxx_linker_static = "C++ linker to link static library",
        cxx_linker_executable = "C++ linker to link executable",
    ),
)

CxxFlagsInfo = provider(
    doc = "Flags for the C/C++ tools, taken from the toolchain",
    fields = dict(
        cc = "C compiler flags",
        cxx = "C++ compiler flags",
        cxx_linker_shared = "C++ linker flags when linking shared library",
        cxx_linker_static = "C++ linker flags when linking static library",
        cxx_linker_executable = "C++ linker flags when linking executable",
        needs_pic_for_dynamic_libraries = "True if PIC should be enabled for shared libraries",
    ),
)

# Since we're calling an external build system we can't support some
# features that may be enabled on the toolchain - so we disable
# them here when configuring the toolchain flags to pass to the external
# build system.
CC_DISABLED_FEATURES = [
    "fdo_instrument",
    "fdo_optimize",
    "layering_check",
    "module_maps",
    "thin_lto",
]

def configure_features(ctx, cc_toolchain):
    """Configures CC toolchain features with external-build-unsupported features disabled.

    Args:
        ctx: The rule context.
        cc_toolchain: The C++ toolchain info.

    Returns:
        A FeatureConfiguration object.
    """
    disabled_features = ctx.disabled_features + CC_DISABLED_FEATURES
    if not ctx.coverage_instrumented():
        # In coverage mode, cc_common.configure_features() adds coverage related flags,
        # such as --coverage to the compiler and linker. However, if this library is not
        # instrumented, we don't need to pass those flags, and avoid unnecessary rebuilds.
        disabled_features.append("coverage")
    return cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = disabled_features,
    )

def _defines_from_deps(ctx, native_deps = None):
    deps = native_deps if native_deps != None else getattr(ctx.attr, "native_deps", [])
    return depset(transitive = [dep[CcInfo].compilation_context.defines for dep in deps if CcInfo in dep])

def get_tools_info(ctx, cc_toolchain = None, feature_configuration = None):
    """Takes information about tools paths from cc_toolchain, returns CxxToolsInfo

    Args:
        ctx: rule context
        cc_toolchain: optional pre-resolved C++ toolchain info
        feature_configuration: optional pre-configured FeatureConfiguration

    Returns:
        CxxToolsInfo: A provider containing C/C++ tool paths.
    """
    if cc_toolchain == None:
        cc_toolchain = find_cpp_toolchain(ctx)
    if feature_configuration == None:
        feature_configuration = configure_features(
            ctx = ctx,
            cc_toolchain = cc_toolchain,
        )

    return CxxToolsInfo(
        cc = cc_common.get_tool_for_action(
            feature_configuration = feature_configuration,
            action_name = ACTION_NAMES.c_compile,
        ),
        cxx = cc_common.get_tool_for_action(
            feature_configuration = feature_configuration,
            action_name = ACTION_NAMES.cpp_compile,
        ),
        cxx_linker_static = cc_common.get_tool_for_action(
            feature_configuration = feature_configuration,
            action_name = ACTION_NAMES.cpp_link_static_library,
        ),
        cxx_linker_executable = cc_common.get_tool_for_action(
            feature_configuration = feature_configuration,
            action_name = ACTION_NAMES.cpp_link_executable,
        ),
    )

_ARCHIVER_OUTPUT_SENTINEL = "__PYCROSS_ARCHIVER_OUTPUT__"

def _strip_archiver_output_sentinel(flags):
    """Remove the sentinel output path from archiver flags, keeping any `-o` trailing."""
    result = []
    had_dash_o = False
    for f in flags:
        if _ARCHIVER_OUTPUT_SENTINEL in f:
            if result and result[-1] == "-o":
                result.pop()
                had_dash_o = True
            continue
        result.append(f)
    if had_dash_o:
        result.append("-o")
    return result

def get_flags_info(
        ctx,
        copts = [],
        linkopts = [],
        link_output_file = None,
        native_deps = None,
        cc_toolchain = None,
        feature_configuration = None):
    """Takes information about flags from cc_toolchain, returns CxxFlagsInfo

    Args:
        ctx: rule context
        copts: compiler options
        linkopts: linker options
        link_output_file: output file to be specified in the link command line
            flags
        native_deps: optional list of native dependency targets providing CcInfo
        cc_toolchain: optional pre-resolved C++ toolchain info
        feature_configuration: optional pre-configured FeatureConfiguration

    Returns:
        CxxFlagsInfo: A provider containing Cxx flags
    """
    cc_toolchain_ = cc_toolchain if cc_toolchain != None else find_cpp_toolchain(ctx)
    if feature_configuration == None:
        feature_configuration = configure_features(
            ctx = ctx,
            cc_toolchain = cc_toolchain_,
        )

    c_opts = (ctx.fragments.cpp.copts + ctx.fragments.cpp.conlyopts + copts) or []
    cxx_opts = (ctx.fragments.cpp.copts + ctx.fragments.cpp.cxxopts + copts) or []
    link_opts = (ctx.fragments.cpp.linkopts + linkopts) or []
    defines = _defines_from_deps(ctx, native_deps)

    flags = CxxFlagsInfo(
        cc = cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            action_name = ACTION_NAMES.c_compile,
            variables = cc_common.create_compile_variables(
                feature_configuration = feature_configuration,
                cc_toolchain = cc_toolchain_,
                preprocessor_defines = defines,
            ),
        ),
        cxx = cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            action_name = ACTION_NAMES.cpp_compile,
            variables = cc_common.create_compile_variables(
                feature_configuration = feature_configuration,
                cc_toolchain = cc_toolchain_,
                preprocessor_defines = defines,
                add_legacy_cxx_options = True,
            ),
        ),
        cxx_linker_shared = cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            action_name = ACTION_NAMES.cpp_link_dynamic_library,
            variables = cc_common.create_link_variables(
                cc_toolchain = cc_toolchain_,
                feature_configuration = feature_configuration,
                is_using_linker = True,
                is_linking_dynamic_library = True,
                must_keep_debug = False,
            ),
        ),
        cxx_linker_static = cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            action_name = ACTION_NAMES.cpp_link_static_library,
            variables = cc_common.create_link_variables(
                cc_toolchain = cc_toolchain_,
                feature_configuration = feature_configuration,
                is_using_linker = False,
                is_linking_dynamic_library = False,
                must_keep_debug = False,
                # rules_cc gates archiver_flags (`rcsD` / `-static -o`) on output_execpath.
                output_file = link_output_file or _ARCHIVER_OUTPUT_SENTINEL,
            ),
        ),
        cxx_linker_executable = cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            action_name = ACTION_NAMES.cpp_link_executable,
            variables = cc_common.create_link_variables(
                cc_toolchain = cc_toolchain_,
                feature_configuration = feature_configuration,
                is_using_linker = True,
                is_linking_dynamic_library = False,
                must_keep_debug = False,
            ),
        ),
    )

    cxx_linker_static = flags.cxx_linker_static
    if not link_output_file:
        cxx_linker_static = _strip_archiver_output_sentinel(cxx_linker_static)

    # User flags are appended verbatim (no dedup against toolchain tokens:
    # that would split pairs like `-isystem DIR`).
    return CxxFlagsInfo(
        cc = _convert_flags(cc_toolchain_.compiler, flags.cc + c_opts),
        cxx = _convert_flags(cc_toolchain_.compiler, flags.cxx + cxx_opts),
        cxx_linker_shared = _convert_flags(cc_toolchain_.compiler, flags.cxx_linker_shared + link_opts),
        cxx_linker_static = _convert_flags(cc_toolchain_.compiler, cxx_linker_static),
        cxx_linker_executable = _convert_flags(cc_toolchain_.compiler, flags.cxx_linker_executable + link_opts),
        needs_pic_for_dynamic_libraries = cc_toolchain_.needs_pic_for_dynamic_libraries(
            feature_configuration = feature_configuration,
        ),
    )

def _convert_flags(compiler, flags):
    """ Rewrites flags depending on the provided compiler.

    MSYS2 may convert leading slashes to the absolute path of the msys root directory, even if MSYS_NO_PATHCONV=1 and MSYS2_ARG_CONV_EXCL="*"
    .E.g MSYS2 may convert "/nologo" to "C:/msys64/nologo".
    Therefore, as MSVC tool flags can start with either a slash or dash, convert the leading slash to a dash.

    Args:
        compiler: The target compiler, e.g. gcc, msvc-cl, mingw-gcc
        flags: The flags to convert

    Returns:
        list: The converted flags
    """
    if compiler == "msvc-cl":
        return ["-" + flag[1:] if flag.startswith("/") else flag for flag in flags]
    return flags

def absolutize_path_in_str(workspace_name, root_str, text, force = False):
    """Replaces relative paths in [the middle of] 'text', prepending them with 'root_str'. If there is nothing to replace, returns the 'text'.

    We only will replace relative paths starting with either 'external/' or '<top-package-name>/',
    because we only want to point with absolute paths to external repositories or inside our
    current workspace. (And also to limit the possibility of error with such not exact replacing.)

    Args:
        workspace_name: workspace name
        text: the text to do replacement in
        root_str: the text to prepend to the found relative path
        force: If true, the `root_str` will always be prepended

    Returns:
        string: A formatted string
    """
    new_text = _prefix(text, "external/", root_str)
    if new_text == text:
        new_text = _prefix(text, "../", root_str)  # Support Bzlmod sibling repository layout relative paths
    if new_text == text:
        new_text = _prefix(text, workspace_name + "/", root_str)
    if new_text == text:
        new_text = _prefix(text, "bazel-out/", root_str)

    # Check to see if the text is already absolute on a unix and windows system
    is_already_absolute = text.startswith("/") or \
                          (len(text) > 2 and text[0].isalpha() and text[1] == ":")

    # absolutize relative by adding our working directory
    # this works because we run on windows under msys now
    if force and new_text == text and not is_already_absolute:
        sep = "" if root_str.endswith("/") else "/"
        new_text = root_str + sep + text

    return new_text

def _prefix(text, from_str, prefix):
    (before, middle, after) = text.partition(from_str)
    if not middle or before.endswith("/"):
        return text
    return before + prefix + middle + after

def get_headers(ccinfo):
    """Returns a struct containing headers depset and include_dirs for the given CcInfo.

    Args:
        ccinfo: The CcInfo provider

    Returns:
        struct: A struct containing headers (depset) and include_dirs (list[str]).
    """
    compilation_info = ccinfo.compilation_context
    include_dirs = compilation_info.system_includes.to_list() + \
                   compilation_info.includes.to_list()

    # do not use quote includes, currently they do not contain
    # library-specific information
    include_dirs = collections.uniq(include_dirs)
    return struct(
        headers = compilation_info.headers,
        include_dirs = include_dirs,
    )

def get_libraries(ccinfo):
    """Returns a list of libraries for the given CcInfo.

    Prefers PIC static libraries over non-PIC static libraries because Python
    extension modules are linked as shared libraries.

    Args:
        ccinfo: The CcInfo provider

    Returns:
        list: A list of library Files.
    """
    all_libraries = []

    def add(lib):
        if lib:
            all_libraries.append(lib)

    for li in ccinfo.linking_context.linker_inputs.to_list():
        for library_to_link in li.libraries:
            add(library_to_link.pic_static_library or library_to_link.static_library)
            add(library_to_link.resolved_symlink_dynamic_library or library_to_link.dynamic_library)
            add(library_to_link.resolved_symlink_interface_library or library_to_link.interface_library)
    return all_libraries

# Visible for testing.
convert_flags_for_testing = _convert_flags
