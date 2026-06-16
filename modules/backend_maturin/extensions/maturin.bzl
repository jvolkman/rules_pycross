"""Maturin overrides extension.

Provides the `maturin_overrides` module extension with an `override` tag class
for declaring maturin-specific package overrides. Generates:

  1. `@maturin_overrides//:overrides.json` — consumed by lock_import via
     `lock_import.override_source(file = ...)`.

  2. `@<repo>_cargo//` repos — containing `pycross_generate_cargo_lock` targets
     for each maturin-overridden package.
"""

load(
    "@rules_pycross//pycross:backend.bzl",
    "MATURIN_OVERRIDE_ATTRS",
    "create_overrides_repo",
    "encode_build_system_attrs",
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
        if info.get("sdist"):
            lines.append('    sdist = "%s",' % info["sdist"])
        else:
            lines.append('    sdist = "@%s//%s:sdist",' % (repo_name, pkg_name))
        if info.get("cargo_lock"):
            # Convert label string to workspace-relative path for the output attr.
            cargo_lock_label = info["cargo_lock"]

            # Parse the string into a Label object
            lbl = Label(cargo_lock_label)
            output_path = lbl.package + "/" + lbl.name if lbl.package else lbl.name

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
            backend_attrs = encode_build_system_attrs(tag)
            if tag.cargo_lock:
                backend_attrs["cargo_lock"] = json.encode(str(tag.cargo_lock))

            overrides.setdefault(tag.repo, {})[tag.name] = {
                "build_backend": "maturin_build",
                "backend_attrs": backend_attrs,
            }

            # Track for cargo repo generation
            cargo_targets.setdefault(tag.repo, {})[tag.name] = {
                "cargo_lock": str(tag.cargo_lock) if tag.cargo_lock else None,
                "sdist": str(tag.sdist) if tag.sdist else None,
            }

    # Write overrides JSON
    create_overrides_repo(
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

maturin = module_extension(
    implementation = _maturin_overrides_impl,
    tag_classes = dict(
        override = tag_class(
            doc = "Specify maturin-specific package overrides.",
            attrs = dict(
                # Maturin-specific typed attrs:
                sdist = attr.label(
                    doc = "Label to the sdist target (e.g. @uv//pkg:sdist). Used to resolve repository visibility in the generated _cargo repo.",
                ),
                cargo_lock = attr.label(
                    doc = "A Cargo.lock file to use. If not provided, the sdist's own Cargo.lock is used.",
                    allow_single_file = [".lock"],
                ),
                **MATURIN_OVERRIDE_ATTRS
            ),
        ),
    ),
)
