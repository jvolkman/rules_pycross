"""Build-time and runtime import index support for rules_pycross wheels."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_python//python:defs.bzl", "py_binary", "py_test")
load("@rules_python//python:features.bzl", "features")
load("@rules_python//python:py_info.bzl", "PyInfo")

# buildifier: disable=bzl-visibility
load(
    "@rules_python//python/private:py_info.bzl",
    "VenvSymlinkEntry",
    "VenvSymlinkKind",
)
load(":providers.bzl", "PycrossExtractedWheelInfo")
load(":util.bzl", "PY_COMMON_ATTRS", "merge_py_providers")

_HAS_RULES_PYTHON_VENV_IMPORT_INDEX = getattr(features, "py_info_venv_import_indexes", False)

VENV_IMPORT_INDEX_ATTRS = dict(
    {
        "_pycross_venv_import_index_flag": attr.label(
            default = Label("//pycross/settings:venv_import_index"),
            providers = [BuildSettingInfo],
        ),
    },
    **({
        "_venv_import_index_flag": attr.label(
            default = Label("@rules_python//python/config_settings:venv_import_index"),
            providers = [BuildSettingInfo],
        ),
    } if _HAS_RULES_PYTHON_VENV_IMPORT_INDEX else {})
)

def _rules_python_import_index_mode(ctx):
    flag = getattr(ctx.attr, "_venv_import_index_flag", None)
    return flag[BuildSettingInfo].value if flag else "off"

def _pycross_import_index_mode(ctx):
    flag = getattr(ctx.attr, "_pycross_venv_import_index_flag", None)
    return flag[BuildSettingInfo].value if flag else "off"

def venv_import_index_mode(ctx):
    """Effective import index mode ("off", "scan", or "prebuilt").

    Args:
        ctx: The rule context.

    Returns:
        The effective mode string ("off", "scan", or "prebuilt").
    """
    pycross_mode = _pycross_import_index_mode(ctx)
    if pycross_mode != "off":
        return pycross_mode
    return _rules_python_import_index_mode(ctx)

def venv_import_index_enabled(ctx):
    """Whether wheel imports are resolved through the import index finder.

    Args:
        ctx: The rule context.

    Returns:
        True if the import index is enabled.
    """
    return venv_import_index_mode(ctx) != "off"

def pycross_venv_import_index_active(ctx):
    """Whether rules_pycross itself injects the finder into the venv via venv_symlinks.

    Args:
        ctx: The rule context.

    Returns:
        True if rules_pycross's own import index runtime is active.
    """
    return _pycross_import_index_mode(ctx) != "off" and _rules_python_import_index_mode(ctx) == "off"

def _runfiles_root_path(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    return paths.join(ctx.workspace_name, file.short_path)

def _pycross_venv_import_index_runtime_impl(ctx):
    if not pycross_venv_import_index_active(ctx):
        return [
            DefaultInfo(),
            PyInfo(transitive_sources = depset()),
        ]

    mode = _pycross_import_index_mode(ctx)
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

_PycrossVenvImportIndexInfo = provider(
    doc = "Transitive per-wheel import index entries collected across Python library targets.",
    fields = {
        "entries": "depset of struct(root = str, index = File)",
    },
)

def _pycross_venv_import_index_aspect_impl(target, ctx):
    transitive = []
    for attr_name in ("actual", "deps", "srcs"):
        val = getattr(ctx.rule.attr, attr_name, None)
        if not val:
            continue
        items = val if type(val) == "list" else [val]
        for dep in items:
            if type(dep) == "Target" and _PycrossVenvImportIndexInfo in dep:
                transitive.append(dep[_PycrossVenvImportIndexInfo].entries)

    direct = []
    if PycrossExtractedWheelInfo in target and not hasattr(ctx.rule.attr, "actual"):
        info = target[PycrossExtractedWheelInfo]
        if info.index and info.site_packages:
            imp = paths.join(_runfiles_root_path(ctx, info.site_packages), "site-packages")
            direct.append(struct(root = imp, index = info.index))

    return [
        _PycrossVenvImportIndexInfo(
            entries = depset(direct = direct, transitive = transitive),
        ),
    ]

pycross_venv_import_index_aspect = aspect(
    implementation = _pycross_venv_import_index_aspect_impl,
    attr_aspects = ["actual", "deps", "srcs"],
    provides = [_PycrossVenvImportIndexInfo],
)

def _format_merger_entry(entry):
    return ["--entry", entry.root, entry.index.path]

def _pycross_venv_import_index_impl(ctx):
    if venv_import_index_mode(ctx) != "prebuilt":
        return [
            DefaultInfo(),
            PyInfo(transitive_sources = depset()),
            OutputGroupInfo(python_import_index = depset()),
        ]

    by_root = {}
    for dep in ctx.attr.deps:
        if _PycrossVenvImportIndexInfo in dep:
            for entry in dep[_PycrossVenvImportIndexInfo].entries.to_list():
                by_root.setdefault(entry.root, entry.index)

    if not by_root:
        return [
            DefaultInfo(),
            PyInfo(transitive_sources = depset()),
            OutputGroupInfo(python_import_index = depset()),
        ]

    imports = depset(
        transitive = [
            dep[PyInfo].imports
            for dep in ctx.attr.deps
            if PyInfo in dep
        ],
    ).to_list()

    ordered_entries = []
    seen = {}
    for imp in imports:
        idx = by_root.get(imp)
        if idx and imp not in seen:
            seen[imp] = True
            ordered_entries.append(struct(root = imp, index = idx))
    for root, idx in by_root.items():
        if root not in seen:
            seen[root] = True
            ordered_entries.append(struct(root = root, index = idx))

    out = ctx.actions.declare_file(ctx.label.name + "/_bazel_import_index.json")
    args = ctx.actions.args()
    args.use_param_file("@%s")
    args.set_param_file_format("multiline")
    args.add("--output", out)
    args.add_all(ordered_entries, map_each = _format_merger_entry)

    ctx.actions.run(
        executable = ctx.executable._merger,
        arguments = [args],
        inputs = [e.index for e in ordered_entries],
        outputs = [out],
        mnemonic = "PyMakeVenvIndex",
        progress_message = "Merging Python import index %{output}",
        env = {
            "PYTHONHASHSEED": "0",
            "PYTHONNOUSERSITE": "1",
            "PYTHONSAFEPATH": "1",
        },
    )

    symlinks = []
    runtime_deps = []
    if pycross_venv_import_index_active(ctx):
        symlinks.append(
            VenvSymlinkEntry(
                kind = VenvSymlinkKind.LIB,
                venv_path = "_bazel_import_index.json",
                link_to_path = _runfiles_root_path(ctx, out),
                link_to_file = None,
                package = None,
                version = None,
                files = depset([out]),
            ),
        )
        runtime_deps.append(ctx.attr._runtime)

    merged = merge_py_providers(
        ctx,
        runtime_deps,
        base_runfiles = ctx.runfiles(files = [out]),
        direct_venv_symlinks = symlinks,
        uses_shared_libraries = False,
    )
    return [
        DefaultInfo(
            files = depset([out]),
            runfiles = merged.runfiles,
        ),
        merged.py_info,
        OutputGroupInfo(
            python_import_index = depset([out]),
        ),
    ]

pycross_venv_import_index = rule(
    implementation = _pycross_venv_import_index_impl,
    doc = """Merges transitive per-wheel import indexes into a single `_bazel_import_index.json` file for a binary's venv.""",
    provides = [PyInfo],
    attrs = dict({
        "deps": attr.label_list(
            doc = "The binary or test dependencies to collect transitive wheel indexes from.",
            aspects = [pycross_venv_import_index_aspect],
            providers = [PyInfo],
        ),
        "_merger": attr.label(
            default = Label("//pycross/private/tools:venv_import_index_merger"),
            cfg = "exec",
            executable = True,
        ),
        "_runtime": attr.label(
            default = Label("//pycross/private:venv_import_index_runtime"),
        ),
    }, **(PY_COMMON_ATTRS | VENV_IMPORT_INDEX_ATTRS)),
)

def pycross_py_binary(name, deps = None, **kwargs):
    """Wrapper around `py_binary` that pre-merges transitive wheel import indexes into `_bazel_import_index.json`.

    Args:
        name: The target name.
        deps: The binary's Python dependencies.
        **kwargs: Additional arguments forwarded to `py_binary`.
    """
    index_name = name + "._venv_import_index"
    pycross_venv_import_index(
        name = index_name,
        deps = deps or [],
        testonly = kwargs.get("testonly"),
        visibility = ["//visibility:private"],
    )
    py_binary(
        name = name,
        deps = (deps or []) + [":" + index_name],
        **kwargs
    )

def pycross_py_test(name, deps = None, **kwargs):
    """Wrapper around `py_test` that pre-merges transitive wheel import indexes into `_bazel_import_index.json`.

    Args:
        name: The target name.
        deps: The test's Python dependencies.
        **kwargs: Additional arguments forwarded to `py_test`.
    """
    index_name = name + "._venv_import_index"
    pycross_venv_import_index(
        name = index_name,
        deps = deps or [],
        testonly = True,
        visibility = ["//visibility:private"],
    )
    py_test(
        name = name,
        deps = (deps or []) + [":" + index_name],
        **kwargs
    )
