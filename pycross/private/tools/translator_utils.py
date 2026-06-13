import sys
from collections import defaultdict
from typing import Any
from typing import Dict
from typing import Iterable
from typing import List
from typing import Protocol

from packaging.utils import NormalizedName
from packaging.utils import canonicalize_name
from packaging.version import Version
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import RawLockSet
from pycross.private.tools.lock_model import RawPackage


class MismatchedVersionException(Exception):
    pass


class PackageProtocol(Protocol):
    @property
    def name(self) -> NormalizedName: ...

    @property
    def version(self) -> Any: ...

    @property
    def pypa_version(self) -> Version: ...

    @property
    def key(self) -> PackageKey: ...

    @property
    def is_local(self) -> bool: ...

    @property
    def dependencies(self) -> Iterable[Any]: ...

    @property
    def resolved_dependencies(self) -> Iterable[PackageDependency]: ...

    def add_resolved_dependency(self, dep: PackageDependency) -> None: ...
    def satisfies_dependency(self, dep: Any) -> bool: ...
    def satisfies_pin(self, pin: Any) -> bool: ...
    def to_lock_package(self) -> RawPackage: ...


def resolve_lock_graph(
    packages: Iterable[PackageProtocol],
    pinned_package_specs: Dict[NormalizedName, Any],
    requires_python: Any,
    strict_dependencies: bool = True,
) -> RawLockSet:
    """
    Resolves a dependency graph of packages by hooking up their dependencies and pins.
    """
    distinct_packages = {p.key: p for p in packages}
    all_packages = list(distinct_packages.values())

    # Group packages by their canonical name
    packages_by_canonical_name: Dict[str, List[PackageProtocol]] = defaultdict(list)
    for package in all_packages:
        packages_by_canonical_name[package.name].append(package)

    # Sort the packages by version in descending order (newest first)
    for package_list in packages_by_canonical_name.values():
        package_list.sort(key=lambda p: p.version, reverse=True)

    # Iterate through each package's dependencies and find the newest one that matches.
    for package in all_packages:
        for dep in package.dependencies:
            dependency_packages = packages_by_canonical_name[canonicalize_name(dep.name)]
            for dep_pkg in dependency_packages:
                if dep_pkg.satisfies_dependency(dep):
                    resolved = PackageDependency(
                        name=dep_pkg.name,
                        version=dep_pkg.pypa_version,
                        marker=str(dep.marker or ""),
                    )
                    package.add_resolved_dependency(resolved)
                    break
            else:
                if strict_dependencies:
                    raise MismatchedVersionException(
                        f"Found no packages to satisfy dependency (name={dep.name}, spec={dep})"
                    )

    pinned_keys: Dict[NormalizedName, PackageKey] = {}

    for pin, pin_spec in pinned_package_specs.items():
        pin_packages = packages_by_canonical_name[pin]
        for pin_pkg in pin_packages:
            if pin_pkg.satisfies_pin(pin_spec):
                pinned_keys[pin] = pin_pkg.key
                break
        else:
            raise MismatchedVersionException(f"Found no packages to satisfy pin (name={pin}, spec={pin_spec})")

    # Replace pins of local packages with pins of their dependencies.
    # We may need to loop multiple times if local packages depend on one another.
    while local_pins := [key for key in pinned_keys.values() if distinct_packages[key].is_local]:
        for pin_key in local_pins:
            pin_pkg = distinct_packages[pin_key]
            pinned_keys.update({dep.name: dep.key for dep in pin_pkg.resolved_dependencies})
            del pinned_keys[pin_key.name]

    lock_packages: Dict[PackageKey, RawPackage] = {}
    for package in all_packages:
        if package.is_local:
            print(
                f"WARNING: Local package {package.key} elided from pycross repo. It can still be referenced directly from the main repo.",
                file=sys.stderr,
            )
            continue
        lock_package = package.to_lock_package()
        lock_packages[lock_package.key] = lock_package

    return RawLockSet(
        python_versions=requires_python,
        packages=lock_packages,
        pins=pinned_keys,
    )
