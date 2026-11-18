"""Finds shared libraries from other wheels anywhere under a native dependency."""

load("//pycross/private:providers.bzl", "PycrossWheelSharedLibraryInfo")

PycrossCollectedWheelLibrariesInfo = provider(
    doc = "Shared libraries from pycross_wheel_cc_import targets in a target's C/C++ dependency graph.",
    fields = {
        "shared_libraries": "depset[File]: The libraries, copied out of the wheels that ship them.",
    },
)

def _collect_wheel_shared_libraries_impl(target, ctx):
    transitive = []
    if PycrossWheelSharedLibraryInfo in target:
        transitive.append(target[PycrossWheelSharedLibraryInfo].shared_libraries)
    for attr_name in ("deps", "implementation_deps"):
        deps = getattr(ctx.rule.attr, attr_name, None)
        if type(deps) != "list":
            continue
        for dep in deps:
            if PycrossCollectedWheelLibrariesInfo in dep:
                transitive.append(dep[PycrossCollectedWheelLibrariesInfo].shared_libraries)
    return [PycrossCollectedWheelLibrariesInfo(shared_libraries = depset(transitive = transitive))]

collect_wheel_shared_libraries = aspect(
    implementation = _collect_wheel_shared_libraries_impl,
    attr_aspects = ["deps", "implementation_deps"],
    doc = "Collects PycrossWheelSharedLibraryInfo through wrappers such as cc_library, so repair " +
          "still leaves those libraries out of the wheel.",
)

def wheel_shared_libraries(native_deps):
    """Returns the depset of other wheels' shared libraries under `native_deps`.

    Args:
        native_deps: list[Target], ideally from an attribute with the
            `collect_wheel_shared_libraries` aspect.

    Returns:
        depset[File]
    """
    transitive = []
    for dep in native_deps:
        if PycrossCollectedWheelLibrariesInfo in dep:
            transitive.append(dep[PycrossCollectedWheelLibrariesInfo].shared_libraries)
        elif PycrossWheelSharedLibraryInfo in dep:
            transitive.append(dep[PycrossWheelSharedLibraryInfo].shared_libraries)
    return depset(transitive = transitive)
