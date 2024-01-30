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
