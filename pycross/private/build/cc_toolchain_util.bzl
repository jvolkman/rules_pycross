""" Adopted from rules_foreign_cc."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

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

def _defines_from_deps(native_deps):
    return depset(transitive = [dep[CcInfo].compilation_context.defines for dep in native_deps if CcInfo in dep])

def get_tools_info(feature_configuration):
    """Takes information about tool paths from a configured C++ toolchain.

    Args:
        feature_configuration: Pre-configured FeatureConfiguration.

    Returns:
        struct: C/C++ tool paths (cc, cxx, cxx_linker_static).
    """
    return struct(
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
        cc_toolchain,
        feature_configuration,
        copts = [],
        linkopts = [],
        native_deps = []):
    """Takes information about flags from cc_toolchain.

    Args:
        ctx: rule context
        cc_toolchain: pre-resolved C++ toolchain info
        feature_configuration: pre-configured FeatureConfiguration
        copts: compiler options
        linkopts: linker options
        native_deps: list of native dependency targets providing CcInfo

    Returns:
        struct: C/C++ compiler and linker flags.
    """
    c_opts = (ctx.fragments.cpp.copts + ctx.fragments.cpp.conlyopts + copts) or []
    cxx_opts = (ctx.fragments.cpp.copts + ctx.fragments.cpp.cxxopts + copts) or []
    link_opts = (ctx.fragments.cpp.linkopts + linkopts) or []
    defines = _defines_from_deps(native_deps)

    cc_flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.c_compile,
        variables = cc_common.create_compile_variables(
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            preprocessor_defines = defines,
        ),
    )
    cxx_flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_compile,
        variables = cc_common.create_compile_variables(
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            preprocessor_defines = defines,
            add_legacy_cxx_options = True,
        ),
    )
    cxx_linker_shared = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_link_dynamic_library,
        variables = cc_common.create_link_variables(
            cc_toolchain = cc_toolchain,
            feature_configuration = feature_configuration,
            is_using_linker = True,
            is_linking_dynamic_library = True,
            must_keep_debug = False,
        ),
    )
    cxx_linker_static = _strip_archiver_output_sentinel(
        cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            action_name = ACTION_NAMES.cpp_link_static_library,
            variables = cc_common.create_link_variables(
                cc_toolchain = cc_toolchain,
                feature_configuration = feature_configuration,
                is_using_linker = False,
                is_linking_dynamic_library = False,
                must_keep_debug = False,
                # rules_cc gates archiver_flags (`rcsD` / `-static -o`) on output_execpath.
                output_file = _ARCHIVER_OUTPUT_SENTINEL,
            ),
        ),
    )
    cxx_linker_executable = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_link_executable,
        variables = cc_common.create_link_variables(
            cc_toolchain = cc_toolchain,
            feature_configuration = feature_configuration,
            is_using_linker = True,
            is_linking_dynamic_library = False,
            must_keep_debug = False,
        ),
    )

    # User flags are appended verbatim (no dedup against toolchain tokens:
    # that would split pairs like `-isystem DIR`).
    return struct(
        cc = _convert_flags(cc_toolchain.compiler, cc_flags + c_opts),
        cxx = _convert_flags(cc_toolchain.compiler, cxx_flags + cxx_opts),
        cxx_linker_shared = _convert_flags(cc_toolchain.compiler, cxx_linker_shared + link_opts),
        cxx_linker_static = _convert_flags(cc_toolchain.compiler, cxx_linker_static),
        cxx_linker_executable = _convert_flags(cc_toolchain.compiler, cxx_linker_executable + link_opts),
    )

_MSVC_NOT_FOUND = "msvc_not_found"

def _clean_msvc_env_value(value):
    """Strip rules_cc msvc_not_found placeholder segments from an MSVC env value.

    Args:
        value: A semicolon-delimited string from a toolchain env entry, or None.

    Returns:
        The cleaned string, or None when no non-empty segment remains.
    """
    if not value:
        return None
    parts = [entry for entry in value.split(";") if entry.strip().lower() != _MSVC_NOT_FOUND]
    if not any([part.strip() for part in parts]):
        return None
    return ";".join(parts)

def create_msvc_environment(cc_toolchain, feature_configuration):
    """Create a dictionary of MSVC toolchain paths without inheriting the process environment.

    Reads PATH and INCLUDE from the compile action and LIB from the shared-link
    action so the build setup can merge them into its environment. Omits keys
    that are empty or contain only rules_cc's msvc_not_found placeholder.

    Args:
        cc_toolchain: The selected C++ toolchain.
        feature_configuration: The configured external-build features.

    Returns:
        A new dictionary containing the available PATH, INCLUDE, and LIB values.
    """
    compile_env = cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_compile,
        variables = cc_common.create_compile_variables(
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            add_legacy_cxx_options = True,
        ),
    )
    link_env = cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_link_dynamic_library,
        variables = cc_common.create_link_variables(
            cc_toolchain = cc_toolchain,
            feature_configuration = feature_configuration,
            is_using_linker = True,
            is_linking_dynamic_library = True,
            must_keep_debug = False,
        ),
    )

    # Custom toolchains may provide only part of the SDK environment, and
    # rules_cc writes "msvc_not_found" when MSVC detection fails. Normalize
    # Windows' case-insensitive keys, then emit only keys with real paths.
    compile_env = {key.upper(): value for key, value in compile_env.items()}
    link_env = {key.upper(): value for key, value in link_env.items()}
    environment = {}
    for key, raw_value in [
        ("PATH", compile_env.get("PATH")),
        ("INCLUDE", compile_env.get("INCLUDE")),
        ("LIB", link_env.get("LIB")),
    ]:
        cleaned = _clean_msvc_env_value(raw_value)
        if cleaned:
            environment[key] = cleaned
    return environment

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

_RUNTIME_PATH_FLAGS = (
    "-rpath",
    "--rpath",
    "-install_name",
    "-soname",
    "--soname",
)
_RUNTIME_PATH_PREFIXES = tuple([flag + "=" for flag in _RUNTIME_PATH_FLAGS])

def _absolutize_wl_flag(workspace_name, root_str, flag, skip_next):
    """Absolutizes path tokens inside a `-Wl,...` flag while skipping runtime loader paths.

    Returns:
        tuple[str, bool]: The rewritten `-Wl,...` flag and whether the next
        linker token in a following flag is a runtime path argument to skip.
    """
    parts = flag.split(",")
    out = [parts[0]]
    for sub in parts[1:]:
        if skip_next:
            out.append(sub)
            skip_next = False
            continue
        if sub in _RUNTIME_PATH_FLAGS:
            out.append(sub)
            skip_next = True
            continue
        if sub.startswith(_RUNTIME_PATH_PREFIXES):
            out.append(sub)
            continue
        out.append(absolutize_path_in_str(workspace_name, root_str, sub))
    return ",".join(out), skip_next

def absolutize_flags(workspace_name, root_str, flags):
    """Absolutizes build-time relative paths in compiler and linker flags.

    Prefixes relative Bazel paths (`external/`, `../`, `<workspace>/`, and
    `bazel-out/`) with `root_str`, while leaving runtime loader path values
    (`-rpath`, `--rpath`, `-install_name`, `-soname`) unchanged across
    single-token `=`, `-Wl,...`, two-token, and `-Xlinker` forms.

    Args:
        workspace_name: The Bazel workspace name.
        root_str: The placeholder prefix to prepend (for example,
            `"$$EXT_BUILD_ROOT$$/"`).
        flags: list[str], compiler or linker flag tokens.

    Returns:
        list[str]: Flag tokens with build-time relative paths absolutized.
    """
    result = []
    skip_next_arg = False
    for flag in flags:
        if flag.startswith("-Wl,"):
            rewritten, skip_next_arg = _absolutize_wl_flag(
                workspace_name,
                root_str,
                flag,
                skip_next_arg,
            )
            result.append(rewritten)
            continue
        if skip_next_arg:
            result.append(flag)
            if flag != "-Xlinker":
                skip_next_arg = False
            continue
        if flag in _RUNTIME_PATH_FLAGS:
            result.append(flag)
            skip_next_arg = True
            continue
        if flag.startswith(_RUNTIME_PATH_PREFIXES):
            result.append(flag)
            continue
        result.append(absolutize_path_in_str(workspace_name, root_str, flag))
    return result

def get_include_dirs(ccinfo):
    """Returns unique include directories for the given CcInfo.

    Args:
        ccinfo: The CcInfo provider

    Returns:
        list[str]: Unique system and regular include directories.
    """
    compilation_info = ccinfo.compilation_context
    include_dirs = compilation_info.system_includes.to_list() + \
                   compilation_info.includes.to_list()

    # do not use quote includes, currently they do not contain
    # library-specific information
    return collections.uniq(include_dirs)

def get_libraries(ccinfo):
    """Returns categorized libraries for the given CcInfo.

    Prefers PIC static libraries over non-PIC static libraries because Python
    extension modules are linked as shared libraries.

    Args:
        ccinfo: The CcInfo provider.

    Returns:
        struct: Lists of library Files grouped as `static`, `dynamic`,
            `interface`, and `all` (preserving original linker-input order).
    """
    static = []
    dynamic = []
    interface = []
    all_libraries = []

    for li in ccinfo.linking_context.linker_inputs.to_list():
        for library_to_link in li.libraries:
            static_lib = library_to_link.pic_static_library or library_to_link.static_library
            if static_lib:
                static.append(static_lib)
                all_libraries.append(static_lib)
            dynamic_lib = library_to_link.resolved_symlink_dynamic_library or library_to_link.dynamic_library
            if dynamic_lib:
                dynamic.append(dynamic_lib)
                all_libraries.append(dynamic_lib)
            interface_lib = library_to_link.resolved_symlink_interface_library or library_to_link.interface_library
            if interface_lib:
                interface.append(interface_lib)
                all_libraries.append(interface_lib)

    return struct(
        static = static,
        dynamic = dynamic,
        interface = interface,
        all = all_libraries,
    )

def _absolutize_additional_input_paths(flag, input_paths):
    """Prefixes relative paths from `additional_inputs` with `$$EXT_BUILD_ROOT$$/`."""
    for path in input_paths:
        if not path or path.startswith("/"):
            continue
        if "$$EXT_BUILD_ROOT$$/" + path in flag:
            continue
        if flag == path:
            return "$$EXT_BUILD_ROOT$$/" + path
        if path not in flag:
            continue
        before, middle, after = flag.partition(path)
        valid_before = (
            before in ("-T", "@") or
            before.endswith(("=", ",", ":", ",-T"))
        )
        if valid_before and (not after or after[0] in (",", ":")):
            flag = before + "$$EXT_BUILD_ROOT$$/" + middle + after
    return flag

def get_link_flags(native_deps):
    """Returns transitive `user_link_flags` and `additional_inputs` from `native_deps`.

    Merges `linking_context.linker_inputs` across all `CcInfo` deps in a single
    depset so diamond dependencies are deduplicated in topological link order.
    Any relative path matching a linker input's `additional_inputs` is prefixed
    with `$$EXT_BUILD_ROOT$$/` so main-repo linker and version scripts resolve
    inside sdist build directories.

    Args:
        native_deps: list[Target], targets that may provide CcInfo.

    Returns:
        struct(flags = list[str], additional_inputs = depset[File]).
    """
    linker_inputs = depset(
        transitive = [
            dep[CcInfo].linking_context.linker_inputs
            for dep in native_deps
            if CcInfo in dep and dep[CcInfo].linking_context
        ],
        order = "topological",
    ).to_list()

    flags = []
    additional_inputs = []
    for li in linker_inputs:
        li_inputs = li.additional_inputs.to_list() if type(li.additional_inputs) == "depset" else list(li.additional_inputs or [])
        if li_inputs:
            additional_inputs.extend(li_inputs)
        if not li.user_link_flags:
            continue
        input_paths = sorted(
            [f.path for f in li_inputs],
            key = len,
            reverse = True,
        ) if li_inputs else []
        for flag in li.user_link_flags:
            flags.append(_absolutize_additional_input_paths(flag, input_paths))

    return struct(
        flags = flags,
        additional_inputs = depset(additional_inputs),
    )

# Visible for testing.
absolutize_additional_input_paths_for_testing = _absolutize_additional_input_paths
convert_flags_for_testing = _convert_flags
