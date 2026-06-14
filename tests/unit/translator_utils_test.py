import unittest
from dataclasses import dataclass
from dataclasses import field
from typing import Any
from typing import Set

from packaging.specifiers import SpecifierSet
from packaging.utils import NormalizedName
from packaging.utils import canonicalize_name
from packaging.version import Version

from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import RawPackage
from pycross.private.tools.translator_utils import MismatchedVersionException
from pycross.private.tools.translator_utils import resolve_lock_graph


@dataclass
class FakePackage:
    """A minimal implementation of PackageProtocol for testing."""

    name: NormalizedName
    version: Version
    is_local: bool = False
    dependencies: list = field(default_factory=list)
    resolved_dependencies: Set[PackageDependency] = field(default_factory=set)
    _files: list = field(default_factory=list)
    source_dir: str | None = None

    @property
    def pypa_version(self) -> Version:
        return self.version

    @property
    def key(self) -> PackageKey:
        return PackageKey.from_parts(self.name, self.version)

    def add_resolved_dependency(self, dep: PackageDependency) -> None:
        self.resolved_dependencies.add(dep)

    def satisfies_dependency(self, dep: Any) -> bool:
        return dep.name == self.name and dep.specifier.contains(self.version, prereleases=True)

    def satisfies_pin(self, pin: Any) -> bool:
        return pin.specifier.contains(self.version, prereleases=True)

    def to_lock_package(self) -> RawPackage:
        files = self._files or [
            PackageFile(
                name=f"{self.name}-{self.version}-py3-none-any.whl",
                sha256="a" * 64,
            )
        ]
        return RawPackage(
            name=self.name,
            version=self.version,
            python_versions=SpecifierSet(">=3.8"),
            dependencies=sorted(self.resolved_dependencies, key=lambda d: d.name),
            files=files,
            source_dir=self.source_dir,
        )


@dataclass(frozen=True)
class FakeDependency:
    """A minimal dependency spec (like packaging.requirements.Requirement)."""

    name: str
    specifier: SpecifierSet
    marker: str | None = None


@dataclass(frozen=True)
class FakePin:
    """A minimal pin spec."""

    specifier: SpecifierSet


def _make_pkg(
    name: str, version: str, deps: list[tuple[str, str]] | None = None, is_local: bool = False
) -> FakePackage:
    """Helper to create a FakePackage with optional dependencies."""
    dep_list = []
    if deps:
        for dep_name, dep_spec in deps:
            dep_list.append(
                FakeDependency(
                    name=dep_name,
                    specifier=SpecifierSet(dep_spec),
                )
            )
    return FakePackage(
        name=canonicalize_name(name),
        version=Version(version),
        dependencies=dep_list,
        is_local=is_local,
    )


def _make_pin(version: str) -> FakePin:
    return FakePin(specifier=SpecifierSet(f"=={version}"))


class TestResolveLockGraph(unittest.TestCase):
    def test_basic_resolution(self):
        """A simple case: app depends on requests, requests depends on urllib3."""
        packages = [
            _make_pkg("requests", "2.31.0", deps=[("urllib3", ">=1.21.1,<3")]),
            _make_pkg("urllib3", "2.1.0"),
        ]
        pins = {
            canonicalize_name("requests"): _make_pin("2.31.0"),
            canonicalize_name("urllib3"): _make_pin("2.1.0"),
        }

        result = resolve_lock_graph(packages, pins, SpecifierSet(">=3.8"))

        self.assertEqual(len(result.packages), 2)
        self.assertEqual(len(result.pins), 2)

        requests_key = PackageKey.from_parts(canonicalize_name("requests"), Version("2.31.0"))
        urllib3_key = PackageKey.from_parts(canonicalize_name("urllib3"), Version("2.1.0"))

        self.assertIn(requests_key, result.packages)
        self.assertIn(urllib3_key, result.packages)
        self.assertEqual(result.pins[canonicalize_name("requests")], requests_key)
        self.assertEqual(result.pins[canonicalize_name("urllib3")], urllib3_key)

        # Check that requests has urllib3 as a resolved dependency
        requests_pkg = result.packages[requests_key]
        dep_names = {d.name for d in requests_pkg.dependencies}
        self.assertIn(canonicalize_name("urllib3"), dep_names)

    def test_newest_version_selected(self):
        """When multiple versions exist, the newest matching one should be picked."""
        packages = [
            _make_pkg("requests", "2.31.0", deps=[("urllib3", ">=1.21.1,<3")]),
            _make_pkg("urllib3", "2.1.0"),
            _make_pkg("urllib3", "1.26.18"),
        ]
        pins = {
            canonicalize_name("requests"): _make_pin("2.31.0"),
            canonicalize_name("urllib3"): _make_pin("2.1.0"),
        }

        result = resolve_lock_graph(packages, pins, SpecifierSet(">=3.8"))

        requests_key = PackageKey.from_parts(canonicalize_name("requests"), Version("2.31.0"))
        requests_pkg = result.packages[requests_key]
        dep_versions = {d.version for d in requests_pkg.dependencies}
        self.assertIn(Version("2.1.0"), dep_versions)

    def test_version_constraint_respected(self):
        """When the newest version doesn't match the constraint, fall back to an older one."""
        packages = [
            _make_pkg("requests", "2.31.0", deps=[("urllib3", ">=1.21.1,<2")]),
            _make_pkg("urllib3", "2.1.0"),
            _make_pkg("urllib3", "1.26.18"),
        ]
        pins = {
            canonicalize_name("requests"): _make_pin("2.31.0"),
            canonicalize_name("urllib3"): _make_pin("1.26.18"),
        }

        result = resolve_lock_graph(packages, pins, SpecifierSet(">=3.8"))

        requests_key = PackageKey.from_parts(canonicalize_name("requests"), Version("2.31.0"))
        requests_pkg = result.packages[requests_key]
        dep_versions = {d.version for d in requests_pkg.dependencies}
        self.assertIn(Version("1.26.18"), dep_versions)
        self.assertNotIn(Version("2.1.0"), dep_versions)

    def test_missing_dependency_raises_strict(self):
        """With strict_dependencies=True, a missing dep should raise."""
        packages = [
            _make_pkg("requests", "2.31.0", deps=[("nonexistent", ">=1.0")]),
        ]
        pins = {
            canonicalize_name("requests"): _make_pin("2.31.0"),
        }

        with self.assertRaises(MismatchedVersionException):
            resolve_lock_graph(packages, pins, SpecifierSet(">=3.8"), strict_dependencies=True)

    def test_missing_dependency_ignored_non_strict(self):
        """With strict_dependencies=False, a missing dep should be silently skipped."""
        packages = [
            _make_pkg("requests", "2.31.0", deps=[("nonexistent", ">=1.0")]),
        ]
        pins = {
            canonicalize_name("requests"): _make_pin("2.31.0"),
        }

        result = resolve_lock_graph(packages, pins, SpecifierSet(">=3.8"), strict_dependencies=False)
        self.assertEqual(len(result.packages), 1)

    def test_missing_pin_raises(self):
        """A pin that matches no package should raise."""
        packages = [
            _make_pkg("requests", "2.31.0"),
        ]
        pins = {
            canonicalize_name("requests"): _make_pin("9.9.9"),
        }

        with self.assertRaises(MismatchedVersionException):
            resolve_lock_graph(packages, pins, SpecifierSet(">=3.8"))

    def test_local_packages_elided(self):
        """Local packages should not appear in the output."""
        packages = [
            _make_pkg("my-app", "0.1.0", deps=[("requests", ">=2.0")], is_local=True),
            _make_pkg("requests", "2.31.0"),
        ]
        pins = {
            canonicalize_name("my-app"): _make_pin("0.1.0"),
            canonicalize_name("requests"): _make_pin("2.31.0"),
        }

        result = resolve_lock_graph(packages, pins, SpecifierSet(">=3.8"))

        # my-app should be replaced by its transitive deps in the pins
        self.assertNotIn(canonicalize_name("my-app"), result.pins)
        self.assertIn(canonicalize_name("requests"), result.pins)
        # And not in the packages either
        my_app_key = PackageKey.from_parts(canonicalize_name("my-app"), Version("0.1.0"))
        self.assertNotIn(my_app_key, result.packages)

    def test_chained_local_packages(self):
        """Local packages that depend on other local packages should be fully flattened."""
        packages = [
            _make_pkg("root", "0.1.0", deps=[("lib-a", ">=0.1")], is_local=True),
            _make_pkg("lib-a", "0.1.0", deps=[("requests", ">=2.0")], is_local=True),
            _make_pkg("requests", "2.31.0"),
        ]
        pins = {
            canonicalize_name("root"): _make_pin("0.1.0"),
            canonicalize_name("lib-a"): _make_pin("0.1.0"),
            canonicalize_name("requests"): _make_pin("2.31.0"),
        }

        result = resolve_lock_graph(packages, pins, SpecifierSet(">=3.8"))

        # Both local packages should be elided
        self.assertNotIn(canonicalize_name("root"), result.pins)
        self.assertNotIn(canonicalize_name("lib-a"), result.pins)
        # Only requests should remain
        self.assertEqual(len(result.pins), 1)
        self.assertIn(canonicalize_name("requests"), result.pins)

    def test_no_packages(self):
        """Empty package set should produce empty output."""
        result = resolve_lock_graph([], {}, SpecifierSet(">=3.8"))
        self.assertEqual(len(result.packages), 0)
        self.assertEqual(len(result.pins), 0)

    def test_diamond_dependency(self):
        """Diamond dependencies: A->B, A->C, B->D, C->D."""
        packages = [
            _make_pkg("a", "1.0", deps=[("b", ">=1.0"), ("c", ">=1.0")]),
            _make_pkg("b", "1.0", deps=[("d", ">=1.0")]),
            _make_pkg("c", "1.0", deps=[("d", ">=1.0")]),
            _make_pkg("d", "1.0"),
        ]
        pins = {
            canonicalize_name("a"): _make_pin("1.0"),
            canonicalize_name("b"): _make_pin("1.0"),
            canonicalize_name("c"): _make_pin("1.0"),
            canonicalize_name("d"): _make_pin("1.0"),
        }

        result = resolve_lock_graph(packages, pins, SpecifierSet(">=3.8"))

        self.assertEqual(len(result.packages), 4)
        self.assertEqual(len(result.pins), 4)

        # Both B and C should have D as a dependency
        b_key = PackageKey.from_parts(canonicalize_name("b"), Version("1.0"))
        c_key = PackageKey.from_parts(canonicalize_name("c"), Version("1.0"))
        b_deps = {d.name for d in result.packages[b_key].dependencies}
        c_deps = {d.name for d in result.packages[c_key].dependencies}
        self.assertIn(canonicalize_name("d"), b_deps)
        self.assertIn(canonicalize_name("d"), c_deps)

    def test_python_versions_propagated(self):
        """The requires_python specifier should be propagated to the output."""
        packages = [_make_pkg("requests", "2.31.0")]
        pins = {canonicalize_name("requests"): _make_pin("2.31.0")}

        result = resolve_lock_graph(packages, pins, SpecifierSet(">=3.9,<3.13"))
        self.assertEqual(result.python_versions, SpecifierSet(">=3.9,<3.13"))

    def test_duplicate_packages_deduped(self):
        """If the same package key appears multiple times, only one should remain."""
        pkg = _make_pkg("requests", "2.31.0")
        packages = [pkg, pkg]  # Duplicate
        pins = {canonicalize_name("requests"): _make_pin("2.31.0")}

        result = resolve_lock_graph(packages, pins, SpecifierSet(">=3.8"))
        self.assertEqual(len(result.packages), 1)


if __name__ == "__main__":
    unittest.main()
