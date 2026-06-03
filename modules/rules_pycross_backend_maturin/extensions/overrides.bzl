"""Maturin overrides extension.

Provides the `maturin_overrides` module extension with an `override` tag class
for declaring maturin-specific package overrides. Generates:

  1. `@maturin_overrides//:overrides.json` — consumed by lock_import via
     `lock_import.override_source(file = ...)`.

  2. `@<repo>_cargo//` repos — containing `pycross_generate_cargo_lock` targets
     for each maturin-overridden package.
"""

def _overrides_repo_impl(rctx):
    """Simple repo that exports an overrides.json file."""
    rctx.file("overrides.json", rctx.attr.content)
    rctx.file("BUILD.bazel", 'exports_files(["overrides.json"])')

_overrides_repo = repository_rule(
    implementation = _overrides_repo_impl,
    attrs = {"content": attr.string()},
)

def _cargo_lock_repo_impl(rctx):
    """Generates a repo with pycross_generate_cargo_lock targets for each package."""
    pkgs = json.decode(rctx.attr.packages)
    repo_name = rctx.attr.repo_name

    lines = [
        'load("@rules_pycross_backend_maturin//rules:generate_cargo_lock.bzl", "pycross_generate_cargo_lock")',
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    for pkg_name, info in sorted(pkgs.items()):
        lines.append("pycross_generate_cargo_lock(")
        lines.append('    name = "%s",' % pkg_name)
        lines.append('    sdist = "@%s//_sdist:%s",' % (repo_name, pkg_name))
        if info.get("cargo_lock"):
            # Convert label string to workspace-relative path for the output attr.
            cargo_lock_label = info["cargo_lock"]
            if cargo_lock_label.startswith("//"):
                output_path = cargo_lock_label.lstrip("/").lstrip(":")
            elif cargo_lock_label.startswith(":"):
                output_path = cargo_lock_label.lstrip(":")
            else:
                output_path = cargo_lock_label
            lines.append('    output = "%s",' % output_path)
        lines.append(")")
        lines.append("")

    rctx.file("BUILD.bazel", "\n".join(lines))

_cargo_lock_repo = repository_rule(
    implementation = _cargo_lock_repo_impl,
    attrs = {
        "repo_name": attr.string(mandatory = True),
        "packages": attr.string(mandatory = True),
    },
)

def _maturin_overrides_impl(module_ctx):
    overrides = {}
    cargo_targets = {}  # repo_name -> {pkg_name -> {cargo_lock}}

    for module in module_ctx.modules:
        for tag in module.tags.override:
            backend_attrs = {}
            if tag.copts:
                backend_attrs["copts"] = json.encode(tag.copts)
            if tag.linkopts:
                backend_attrs["linkopts"] = json.encode(tag.linkopts)
            if tag.native_deps:
                backend_attrs["native_deps"] = json.encode(
                    [str(dep) for dep in tag.native_deps],
                )
            if tag.config_settings:
                backend_attrs["config_settings"] = json.encode(tag.config_settings)
            if tag.tool_deps:
                backend_attrs["tool_deps"] = json.encode(tag.tool_deps)
            if tag.cargo_lock:
                backend_attrs["cargo_lock"] = json.encode(str(tag.cargo_lock))

            key = tag.repo + ":" + tag.name
            overrides[key] = {
                "always_build": tag.always_build,
                "build_backend": "maturin_build",
                "build_dependencies": tag.build_dependencies,
                "ignore_dependencies": tag.ignore_dependencies,
                "install_exclude_globs": tag.install_exclude_globs,
                "post_install_patches": tag.post_install_patches,
                "build_target": None,
                "backend_attrs": backend_attrs,
            }

            # Track for cargo repo generation
            cargo_targets.setdefault(tag.repo, {})[tag.name] = {
                "cargo_lock": str(tag.cargo_lock) if tag.cargo_lock else None,
            }

    # Write overrides JSON
    _overrides_repo(
        name = "maturin_overrides",
        content = json.encode(overrides),
    )

    # Generate <repo>_cargo repos with pycross_generate_cargo_lock targets
    for repo_name, pkgs in cargo_targets.items():
        _cargo_lock_repo(
            name = repo_name + "_cargo",
            repo_name = repo_name,
            packages = json.encode(pkgs),
        )

maturin_overrides = module_extension(
    implementation = _maturin_overrides_impl,
    tag_classes = dict(
        override = tag_class(
            doc = "Specify maturin-specific package overrides.",
            attrs = {
                "name": attr.string(
                    doc = "The package name.",
                    mandatory = True,
                ),
                "repo": attr.string(
                    doc = "The lock repo this override applies to.",
                    mandatory = True,
                ),
                "always_build": attr.bool(
                    doc = "If True, don't use pre-built wheels for this package.",
                    default = True,
                ),
                "build_dependencies": attr.string_list(
                    doc = "Additional build-time dependencies.",
                ),
                "ignore_dependencies": attr.string_list(
                    doc = "Dependencies to drop from this package.",
                ),
                "install_exclude_globs": attr.string_list(
                    doc = "Globs for files to exclude during installation.",
                ),
                "post_install_patches": attr.string_list(
                    doc = "Patches to apply after wheel installation.",
                ),
                # Maturin-specific typed attrs:
                "cargo_lock": attr.label(
                    doc = "A Cargo.lock file to use. If not provided, the sdist's own Cargo.lock is used.",
                    allow_single_file = [".lock"],
                ),
                "copts": attr.string_list(
                    doc = "Extra C++ compiler options.",
                ),
                "linkopts": attr.string_list(
                    doc = "Extra linker options.",
                ),
                "native_deps": attr.label_list(
                    doc = "CC dependencies to link against.",
                ),
                "config_settings": attr.string_list_dict(
                    doc = "Setup configuration arguments.",
                ),
                "tool_deps": attr.string_dict(
                    doc = "Overrides for built-in dependencies.",
                ),
            },
        ),
    ),
)
