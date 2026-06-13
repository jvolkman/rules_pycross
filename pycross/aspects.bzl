"""Aspects for detecting package version conflicts across pycross repos.

Usage:
    bazel build //... --aspects=@rules_pycross//pycross:aspects.bzl%pycross_conflict_check

Or in .bazelrc:
    build:ci --aspects=@rules_pycross//pycross:aspects.bzl%pycross_conflict_check
"""

load("//pycross/private:providers.bzl", "PycrossPackageInfo")

PycrossConflictInfo = provider(
    doc = "Tracks pycross package identities transitively for conflict detection.",
    fields = {
        "packages": "depset of struct(name, version, label)",
    },
)

def _conflict_check_impl(target, ctx):
    direct = []

    # Collect from this target if it provides PycrossPackageInfo
    if PycrossPackageInfo in target:
        info = target[PycrossPackageInfo]
        if info.package_name and info.package_version:
            direct.append(struct(
                name = info.package_name,
                version = info.package_version,
                label = str(target.label),
            ))

    # Collect transitive from deps
    transitive = []
    for attr_name in ("deps", "dep"):
        deps = getattr(ctx.rule.attr, attr_name, None)
        if deps == None:
            continue
        dep_list = deps if type(deps) == "list" else [deps]
        for dep in dep_list:
            if PycrossConflictInfo in dep:
                transitive.append(dep[PycrossConflictInfo].packages)

    all_packages = depset(direct = direct, transitive = transitive)

    # Validate at terminal targets (py_binary, py_test)
    if ctx.rule.kind in ("py_binary", "py_test"):
        seen = {}  # name -> (version, label)
        for pkg in all_packages.to_list():
            if pkg.name in seen:
                prev_ver, prev_label = seen[pkg.name]
                if prev_ver != pkg.version:
                    fail((
                        "Pycross package conflict in {target}: " +
                        "'{name}' has multiple versions in the dependency graph:\n" +
                        "  {name}=={v1} (from {l1})\n" +
                        "  {name}=={v2} (from {l2})\n\n" +
                        "This typically happens when two hub-linked repos " +
                        "pin different versions and a target depends on both.\n" +
                        "Align the versions in your lock files."
                    ).format(
                        target = str(target.label),
                        name = pkg.name,
                        v1 = prev_ver,
                        l1 = prev_label,
                        v2 = pkg.version,
                        l2 = pkg.label,
                    ))
            else:
                seen[pkg.name] = (pkg.version, pkg.label)

    return [PycrossConflictInfo(packages = all_packages)]

pycross_conflict_check = aspect(
    doc = "Detects conflicting pycross package versions in the transitive dependency graph.",
    implementation = _conflict_check_impl,
    attr_aspects = ["deps", "dep"],
)
