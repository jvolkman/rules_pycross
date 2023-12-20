"""Debug utilities"""

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
