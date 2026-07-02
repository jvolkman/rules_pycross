"""Package repo hook for cargo lock generating backends (e.g. maturin, setuptools-rust).

Generates a _cargo/ sub-directory in the package repo with
pycross_generate_cargo_lock targets for each overridden package.
Targets are versioned (e.g., _cargo:jiter@0.5.0) to handle multiple
versions of the same package.
"""

# Resolve at load time so str() gives the canonical label form.
_GENERATE_CARGO_LOCK_BZL = str(Label("@rules_pycross_backend_maturin//rules:generate_cargo_lock.bzl"))

def cargo_lock_package_repo_hook(packages_info, override_packages):
    """Generate _cargo/ directory with cargo lock generation targets.

    Args:
        packages_info: dict of normalized_name -> {"versions": [struct(version, package_key, has_sdist)]}.
            All packages in the package repo.
        override_packages: dict of pkg_name -> dict of backend_attrs.
            Only packages that have overrides.

    Returns:
        A list of structs with dir and files fields.
    """

    if not override_packages:
        return []

    lines = [
        'load("{}", "pycross_generate_cargo_lock")'.format(_GENERATE_CARGO_LOCK_BZL),
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    for pkg_name in sorted(override_packages.keys()):
        attrs = override_packages[pkg_name]
        pkg_info = packages_info.get(pkg_name)
        if not pkg_info:
            continue

        for version_info in pkg_info["versions"]:
            if not version_info.has_sdist:
                continue

            versioned_name = "{}@{}".format(pkg_name, version_info.version)

            lines.append("pycross_generate_cargo_lock(")
            lines.append('    name = "%s",' % versioned_name)
            lines.append('    sdist = "//_sdist:%s",' % versioned_name)

            cargo_lock_json = attrs.get("cargo_lock")
            if cargo_lock_json:
                cargo_lock_label = json.decode(cargo_lock_json)
                lbl = Label(cargo_lock_label)
                output_path = lbl.package + "/" + lbl.name if lbl.package else lbl.name
                lines.append('    output = "%s",' % output_path)

            lines.append(")")
            lines.append("")

    return [struct(
        dir = "_cargo",
        files = {"BUILD.bazel": "\n".join(lines)},
    )]
