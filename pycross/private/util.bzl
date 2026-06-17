"""Shared utilities"""

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

def normalize_pep503_name(name):
    """PEP 503 normalization: lowercase, replace [_-.] with -, collapse runs.

    Args:
      name: The string to normalize.

    Returns:
      The PEP 503 normalized string.
    """
    name = name.replace("_", "-").replace(".", "-").lower()
    for _i in range(len(name)):
        if "--" in name:
            name = name.replace("--", "-")
        else:
            break
    return name

def underscore_name(name):
    """rules_python-style normalization: lowercase, replace [-. ] with _."""
    return normalize_pep503_name(name).replace("-", "_")

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
    normalized = name.lower().replace("_", "-").replace(".", "-")

    # Dedup hyphens (PEP 503 normalization)
    return "-".join([part for part in normalized.split("-") if part])

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
