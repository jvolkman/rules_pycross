"""Shared utilities"""

# Whether we're using at least Bazel 7
IS_BAZEL_7_OR_HIGHER = hasattr(native, "starlark_doc_extract")

# Whether we're using bzlmod
BZLMOD = str(Label("//:invalid")).startswith("@@")

# The http library seems to depend on cache.bzl as of Bazel 7
REPO_HTTP_DEPS = [
    "@bazel_tools//tools/build_defs/repo:http.bzl",
] + [
    "@bazel_tools//tools/build_defs/repo:cache.bzl",
] if IS_BAZEL_7_OR_HIGHER else []

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

_PEP508_NAME_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."

def extract_pep508_name(spec):
    """Extract the normalized package name from a PEP508 requirement line.

    Args:
        spec: The PEP508 requirement string to parse.

    Returns:
        The normalized package name (with underscores) as a string.
    """
    spec = spec.strip()
    stripped = spec.lstrip(_PEP508_NAME_CHARS)
    name_len = len(spec) - len(stripped)
    name = spec[:name_len]
    normalized = name.lower().replace("-", "_").replace(".", "_")

    # Dedup underscores (standard PEP 503 name normalization helper)
    return "_".join([part for part in normalized.split("_") if part])
