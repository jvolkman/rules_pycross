"""Shared utilities"""

load("@rules_python//python/api:api.bzl", "py_common")
load("//pycross/private/pypackaging/utils:utils.bzl", "canonicalize_name")

# The http library seems to depend on cache.bzl as of Bazel 7
REPO_HTTP_DEPS = [
    "@bazel_tools//tools/build_defs/repo:http.bzl",
    "@bazel_tools//tools/build_defs/repo:cache.bzl",
]

def trace_ctx(ctx, display_name = "ctx"):
    """Wraps a context object so that method calls are printed with their arguments.

    Usage example:
      def _my_module_impl(module_ctx):
          module_ctx = trace_context(module_ctx, "module_ctx")
          ...
    """

    def wrap(field_name):
        field = getattr(ctx, field_name)

        if type(field) != "builtin_function_or_method":
            return field

        def _wrapper(*a, **kw):
            args = [repr(arg) for arg in a]
            for k, v in kw.items():
                args.append("{}={}".format(k, repr(v)))

            # buildifier: disable=print
            print("{}.{}({})".format(display_name, field_name, ", ".join(args)))

            return field(*a, **kw)

        return _wrapper

    return struct(**{field_name: wrap(field_name) for field_name in dir(ctx)})

def sanitize_name(val):
    """Sanitize a string into a valid Bazel repository and target name identifier."""
    return val.lower().replace("-", "_").replace(".", "_").replace("+", "_").replace("@", "_").replace("!", "_")



def underscore_name(name):
    """rules_python-style normalization: lowercase, replace [-. ] with _."""
    return canonicalize_name(name).replace("-", "_")

_PEP508_NAME_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."

def extract_pep508_name(spec):
    """Extract the PEP 503 normalized package name from a PEP508 requirement line.

    Args:
        spec: The PEP508 requirement string to parse.

    Returns:
        The PEP 503 normalized package name (with hyphens) as a string.
    """
    spec = spec.strip()
    stripped = spec.lstrip(_PEP508_NAME_CHARS)
    name_len = len(spec) - len(stripped)
    name = spec[:name_len]
    return canonicalize_name(name)

def key_parts(key):
    """Split a lockfile package key into its name and version parts.

    Args:
        key: The package key string (e.g. "package@1.0.0").

    Returns:
        A tuple of (name, version).
    """
    parts = key.split("@", 1)
    if len(parts) != 2:
        fail("Invalid package key format: " + key)
    return parts[0], parts[1]

def key_name(key):
    """Extract the package name part from a lockfile package key.

    Args:
        key: The package key string.

    Returns:
        The package name part.
    """
    return key.split("@", 1)[0]

# Attrs that consuming rules must include for merge_py_providers to work.
PY_COMMON_ATTRS = py_common.API_ATTRS

def merge_py_providers(
        ctx,
        deps,
        direct_sources = [],
        direct_imports = [],
        base_runfiles = None,
        direct_venv_symlinks = [],
        has_py2_only_sources = False,
        has_py3_only_sources = False,
        uses_shared_libraries = True):
    """Merges PyInfo and DefaultInfo from deps with optional direct entries.

    Uses rules_python's PyInfoBuilder to ensure all PyInfo fields (including
    pyc files, pyi stubs, and venv symlinks) are properly merged.

    The consuming rule must include PY_COMMON_ATTRS in its attrs dict.

    Args:
        ctx: The rule context (must have PY_COMMON_ATTRS in its rule attrs).
        deps: List of Target objects providing PyInfo and DefaultInfo.
        direct_sources: Files to add as direct entries to transitive_sources.
        direct_imports: Strings to add as direct entries to imports.
        base_runfiles: A Runfiles object (e.g. from ctx.runfiles) to merge with dep runfiles.
        direct_venv_symlinks: VenvSymlinkEntry values to add directly.
        has_py2_only_sources: Whether this target has PY2-only sources.
        has_py3_only_sources: Whether this target has PY3-only sources.
        uses_shared_libraries: Whether to set uses_shared_libraries on PyInfo.

    Returns:
        A struct with fields:
          - default_info: A DefaultInfo provider.
          - py_info: A PyInfo provider.
          - runfiles: The merged Runfiles object.
    """
    api = py_common.get(ctx)
    builder = api.PyInfoBuilder()

    # Merge all dep PyInfos as transitive.
    builder.merge_targets(deps)

    # Add our own direct content.
    builder.transitive_sources.add(direct_sources)
    builder.imports.add(direct_imports)
    if direct_venv_symlinks:
        builder.venv_symlinks.add(direct_venv_symlinks)

    if has_py2_only_sources:
        builder.set_has_py2_only_sources(True)
    if has_py3_only_sources:
        builder.set_has_py3_only_sources(True)
    if uses_shared_libraries:
        builder.set_uses_shared_libraries(True)

    py_info = builder.build()

    # Merge runfiles from all deps.
    runfiles = base_runfiles
    for dep in deps:
        rf = dep[DefaultInfo].default_runfiles
        if rf:
            if runfiles == None:
                runfiles = rf
            else:
                runfiles = runfiles.merge(rf)

    return struct(
        default_info = DefaultInfo(
            files = depset(direct = direct_sources) if direct_sources else depset(),
            runfiles = runfiles,
        ),
        py_info = py_info,
        runfiles = runfiles,
    )
