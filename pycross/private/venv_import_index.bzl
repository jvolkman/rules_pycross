"""Build-time and runtime import index support for rules_pycross wheels."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_python//python:py_info.bzl", "PyInfo")

# buildifier: disable=bzl-visibility
load(
    "@rules_python//python/private:py_info.bzl",
    "VenvSymlinkEntry",
    "VenvSymlinkKind",
)
load(":util.bzl", "PY_COMMON_ATTRS", "merge_py_providers")

VENV_IMPORT_INDEX_ATTRS = {
    "_pycross_venv_import_index_flag": attr.label(
        default = Label("//pycross/settings:venv_import_index"),
        providers = [BuildSettingInfo],
    ),
}

def venv_import_index_mode(ctx):
    """Effective import index mode ("off", "scan", or "prebuilt").

    Args:
        ctx: The rule context.

    Returns:
        The effective mode string ("off", "scan", or "prebuilt").
    """
    flag = getattr(ctx.attr, "_pycross_venv_import_index_flag", None)
    return flag[BuildSettingInfo].value if flag else "off"

def venv_import_index_enabled(ctx):
    """Whether wheel imports are resolved through the import index finder.

    Args:
        ctx: The rule context.

    Returns:
        True if the import index is enabled.
    """
    return venv_import_index_mode(ctx) != "off"

def _runfiles_root_path(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    return paths.join(ctx.workspace_name, file.short_path)

def _pycross_venv_import_index_runtime_impl(ctx):
    if not venv_import_index_enabled(ctx):
        return [
            DefaultInfo(),
            PyInfo(transitive_sources = depset()),
        ]

    mode = venv_import_index_mode(ctx)
    pth = ctx.actions.declare_file(ctx.label.name + "/pycross_import_index.pth")
    ctx.actions.write(
        output = pth,
        content = "import _bazel_import_index; _bazel_import_index.auto_install()\n",
    )

    finder = ctx.actions.declare_file(ctx.label.name + "/_bazel_import_index.py")
    ctx.actions.expand_template(
        template = ctx.file._finder_template,
        output = finder,
        substitutions = {
            "%import_index_mode%": mode,
        },
    )

    symlinks = [
        VenvSymlinkEntry(
            kind = VenvSymlinkKind.LIB,
            venv_path = "pycross_import_index.pth",
            link_to_path = _runfiles_root_path(ctx, pth),
            link_to_file = None,
            package = None,
            version = None,
            files = depset([pth]),
        ),
        VenvSymlinkEntry(
            kind = VenvSymlinkKind.LIB,
            venv_path = "_bazel_import_index.py",
            link_to_path = _runfiles_root_path(ctx, finder),
            link_to_file = None,
            package = None,
            version = None,
            files = depset([finder]),
        ),
    ]

    merged = merge_py_providers(
        ctx,
        [],
        base_runfiles = ctx.runfiles(files = [pth, finder]),
        direct_venv_symlinks = symlinks,
        uses_shared_libraries = False,
    )
    return [
        DefaultInfo(
            files = depset([pth, finder]),
            runfiles = merged.runfiles,
        ),
        merged.py_info,
    ]

pycross_venv_import_index_runtime = rule(
    implementation = _pycross_venv_import_index_runtime_impl,
    provides = [PyInfo],
    attrs = dict({
        "_finder_template": attr.label(
            default = Label("//pycross/private/tools:import_index.py"),
            allow_single_file = True,
        ),
    }, **(PY_COMMON_ATTRS | VENV_IMPORT_INDEX_ATTRS)),
)
