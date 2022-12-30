""" Adopted from rules_foreign_cc."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

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
    "layering_check",
    "module_maps",
    "thin_lto",
]

def _configure_features(ctx, cc_toolchain):
    return cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features + CC_DISABLED_FEATURES,
    )

def _defines_from_deps(ctx):
    return depset(transitive = [dep[CcInfo].compilation_context.defines for dep in getattr(ctx.attr, "deps", []) if CcInfo in dep])

def get_env_vars(ctx):
    """Returns environment variables for C tools

    Args:
        ctx: rule context
    Returns:
        environment variables
    """
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = _configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )
    copts = getattr(ctx.attr, "copts", [])

    action_names = [
        ACTION_NAMES.c_compile,
        ACTION_NAMES.cpp_link_static_library,
        ACTION_NAMES.cpp_link_executable,
    ]

    vars = dict()
    for action_name in action_names:
        vars.update(cc_common.get_environment_variables(
            feature_configuration = feature_configuration,
            action_name = action_name,
            variables = cc_common.create_compile_variables(
                feature_configuration = feature_configuration,
                cc_toolchain = cc_toolchain,
                user_compile_flags = copts,
            ),
        ))
    return vars

def get_tools_info(ctx):
    """Takes information about tools paths from cc_toolchain, returns CxxToolsInfo

    Args:
        ctx: rule context
    """
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = _configure_features(
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

def get_flags_info(ctx, link_output_file = None):
    """Takes information about flags from cc_toolchain, returns CxxFlagsInfo

    Args:
        ctx: rule context
        link_output_file: output file to be specified in the link command line
            flags

    Returns:
        CxxFlagsInfo: A provider containing Cxx flags
    """
    cc_toolchain_ = find_cpp_toolchain(ctx)
    feature_configuration = _configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain_,
    )

    copts = (ctx.fragments.cpp.copts + ctx.fragments.cpp.conlyopts + getattr(ctx.attr, "copts", [])) or []
    cxxopts = (ctx.fragments.cpp.copts + ctx.fragments.cpp.cxxopts + getattr(ctx.attr, "copts", [])) or []
    linkopts = (ctx.fragments.cpp.linkopts + getattr(ctx.attr, "linkopts", [])) or []
    defines = _defines_from_deps(ctx)

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
                output_file = link_output_file,
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
            ),
        ),
    )
    return CxxFlagsInfo(
        cc = _convert_flags(cc_toolchain_.compiler, _add_if_needed(flags.cc, copts)),
        cxx = _convert_flags(cc_toolchain_.compiler, _add_if_needed(flags.cxx, cxxopts)),
        cxx_linker_shared = _convert_flags(cc_toolchain_.compiler, _add_if_needed(flags.cxx_linker_shared, linkopts)),
        cxx_linker_static = _convert_flags(cc_toolchain_.compiler, flags.cxx_linker_static),
        cxx_linker_executable = _convert_flags(cc_toolchain_.compiler, _add_if_needed(flags.cxx_linker_executable, linkopts)),
        needs_pic_for_dynamic_libraries = cc_toolchain_.needs_pic_for_dynamic_libraries(
            feature_configuration = feature_configuration
        ),
    )

def _convert_flags(compiler, flags):
    """ Rewrites flags depending on the provided compiler.

    MSYS2 may convert leading slashes to the absolute path of the msys root directory, even if MSYS_NO_PATHCONV=1 and MSYS2_ARG_CONV_EXCL="*"
    .E.g MSYS2 may convert "/nologo" to "C:/msys64/nologo".
    Therefore, as MSVC tool flags can start with either a slash or dash, convert slashes to dashes

    Args:
        compiler: The target compiler, e.g. gcc, msvc-cl, mingw-gcc
        flags: The flags to convert

    Returns:
        list: The converted flags
    """
    if compiler == "msvc-cl":
        return [flag.replace("/", "-") if flag.startswith("/") else flag for flag in flags]
    return flags

def _add_if_needed(arr, add_arr):
    filtered = []
    for to_add in add_arr:
        found = False
        for existing in arr:
            if existing == to_add:
                found = True
        if not found:
            filtered.append(to_add)
    return arr + filtered

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
        new_text = _prefix(text, workspace_name + "/", root_str)

    # Check to see if the text is already absolute on a unix and windows system
    is_already_absolute = text.startswith("/") or \
                          (len(text) > 2 and text[0].isalpha() and text[1] == ":")

    # absolutize relative by adding our working directory
    # this works because we ru on windows under msys now
    if force and new_text == text and not is_already_absolute:
        new_text = root_str + "/" + text

    return new_text

def _prefix(text, from_str, prefix):
    (before, middle, after) = text.partition(from_str)
    if not middle or before.endswith("/"):
        return text
    return before + prefix + middle + after

def get_headers(ccinfo):
    """Returns a struct containing headers and include_dirs for the given CcInfo.

    Args:
        ccinfo: The CcInfo provider

    Returns:
        struct: A struct containing headers and include_dirs.
    """
    compilation_info = ccinfo.compilation_context
    include_dirs = compilation_info.system_includes.to_list() + \
                   compilation_info.includes.to_list()

    # do not use quote includes, currently they do not contain
    # library-specific information
    include_dirs = collections.uniq(include_dirs)
    headers = []
    for header in compilation_info.headers.to_list():
        path = header.path
        included = False
        for dir_ in include_dirs:
            if path.startswith(dir_):
                included = True
                break
        if not included:
            headers.append(header)
    return struct(
        headers = headers,
        include_dirs = include_dirs,
    )

def get_libraries(ccinfo):
    """Returns a list of libraries for the given CcInfo.

    Args:
        ccinfo: The CcInfo provider

    Returns:
        struct: A list of libraries.
    """
    all_libraries = []
    def add(lib):
        if lib:
            all_libraries.append(lib)
    for li in ccinfo.linking_context.linker_inputs.to_list():
        for library_to_link in li.libraries:
            add(library_to_link.static_library)
            add(library_to_link.pic_static_library)
            add(library_to_link.dynamic_library)
            add(library_to_link.interface_library)
    return all_libraries
