"""Shared _cargo_lock_repo rule for Rust extensions."""

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

cargo_lock_repo = repository_rule(
    implementation = _cargo_lock_repo_impl,
    attrs = {
        "repo_name": attr.string(mandatory = True),
        "packages": attr.string(mandatory = True),
    },
)
