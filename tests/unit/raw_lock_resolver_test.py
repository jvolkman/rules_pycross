import unittest
from typing import List

from packaging.specifiers import SpecifierSet
from packaging.utils import canonicalize_name
from packaging.version import Version

from pycross.private.tools.lock_model import DependencyName
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import RawLockSet
from pycross.private.tools.lock_model import RawPackage
from pycross.private.tools.raw_lock_resolver import GenerationContext
from pycross.private.tools.raw_lock_resolver import PackageAnnotations
from pycross.private.tools.raw_lock_resolver import PackageResolver
from pycross.private.tools.raw_lock_resolver import collect_package_annotations
from pycross.private.tools.raw_lock_resolver import resolve


def make_file(name: str, sha256: str = "1234") -> PackageFile:
    return PackageFile(name=name, sha256=sha256)


def make_dep(name: str, version: str, marker: str = "") -> PackageDependency:
    return PackageDependency(name=DependencyName(name), version=Version(version), marker=marker)


def make_pkg(
    name: str,
    version: str,
    files: List[PackageFile],
    deps: List[PackageDependency] = None,
    python_versions: str = ">=3.8",
) -> RawPackage:
    return RawPackage(
        name=DependencyName(name),
        version=Version(version),
        python_versions=SpecifierSet(python_versions),
        dependencies=deps or [],
        files=files,
    )


class RawLockResolverTest(unittest.TestCase):
    # Core Resolution
    def test_single_package_single_env(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")])
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 1)
        self.assertEqual(resolved.wheel_candidates[0].filename, "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")

    def test_single_package_with_sdist_and_wheel(self):
        """Both wheels and sdist are available; wheel is a candidate, sdist found separately."""
        pkg = make_pkg(
            "foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"), make_file("foo-1.0.tar.gz")]
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=True,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 1)
        self.assertEqual(resolved.wheel_candidates[0].filename, "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")
        self.assertTrue(resolver.uses_sdist)
        self.assertIsNotNone(resolved.sdist_file)

    def test_wheel_candidates_include_all_wheels(self):
        """All wheel files become candidates; selection happens at Starlark analysis time."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-manylinux2014_x86_64.whl"),
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
            ],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 2)
        filenames = {c.filename for c in resolved.wheel_candidates}
        self.assertIn("foo-1.0-cp310-cp310-manylinux2014_x86_64.whl", filenames)
        self.assertIn("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl", filenames)

    def test_wheel_candidates_with_build_tags(self):
        """Wheels with build tags are all included as candidates."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-1-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("foo-1.0-2-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
            ],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 3)
        filenames = {c.filename for c in resolved.wheel_candidates}
        self.assertIn("foo-1.0-2-cp310-cp310-manylinux_2_17_x86_64.whl", filenames)

    def test_wheel_preferred_over_sdist(self):
        """When both a wheel and sdist exist, sdist is NOT included unless always_include_sdist."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("foo-1.0.tar.gz"),
            ],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 1)
        self.assertEqual(resolved.wheel_candidates[0].filename, "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")
        self.assertFalse(resolver.uses_sdist)

    def test_all_wheels_become_candidates(self):
        """All wheels become candidates regardless of platform compatibility."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl"),
                make_file("foo-1.0.tar.gz"),
            ],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        # The macos wheel is still a candidate (selection is at analysis time)
        self.assertEqual(len(resolved.wheel_candidates), 1)
        self.assertEqual(resolved.wheel_candidates[0].filename, "foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl")

    def test_always_include_sdist_flag(self):
        """With always_include_sdist, sdist file is set alongside wheel candidates."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("foo-1.0.tar.gz"),
            ],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=True,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        # Wheel is still a candidate
        self.assertEqual(len(resolved.wheel_candidates), 1)
        # But sdist is also included
        self.assertTrue(resolver.uses_sdist)
        self.assertIsNotNone(resolved.sdist_file)
        self.assertEqual(resolved.sdist_file.key.name, "foo-1.0.tar.gz")

    def test_wheel_only_no_sdist(self):
        """When only a wheel exists and no sdist, no sdist is set."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl")],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 1)
        self.assertIsNone(resolved.sdist_file)

    def test_pure_python_wheel_is_candidate(self):
        """A py3-none-any wheel becomes a wheel candidate."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0-py3-none-any.whl")],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 1)
        self.assertEqual(resolved.wheel_candidates[0].filename, "foo-1.0-py3-none-any.whl")

    def test_multi_platform_wheels_all_candidates(self):
        """Multiple platform-specific wheels all become candidates."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl"),
            ],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 2)
        filenames = {c.filename for c in resolved.wheel_candidates}
        self.assertIn("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl", filenames)
        self.assertIn("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl", filenames)

    def test_unconditional_and_conditional_deps(self):
        """Unconditional deps have no marker; conditional deps preserve their marker."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[make_dep("depA", "1.0"), make_dep("depB", "1.0", marker="sys_platform == 'linux'")],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.marker_dependencies), 2)
        unconditional = [md for md in resolved.marker_dependencies if not md.marker]
        conditional = [md for md in resolved.marker_dependencies if md.marker]
        self.assertEqual(len(unconditional), 1)
        self.assertEqual(unconditional[0].key.name.package, "depa")
        self.assertEqual(len(conditional), 1)
        self.assertEqual(conditional[0].key.name.package, "depb")
        self.assertIn("sys_platform", conditional[0].marker)

    # Dependency Handling
    def test_marker_preserved(self):
        """Marker strings are preserved as-is in marker_dependencies."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[make_dep("depA", "1.0", marker="sys_platform == 'linux'")],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.marker_dependencies), 1)
        self.assertEqual(resolved.marker_dependencies[0].key.name.package, "depa")
        self.assertIn("sys_platform", resolved.marker_dependencies[0].marker)

    def test_ignore_dependencies(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")], deps=[make_dep("depA", "1.0")])
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        annotations = PackageAnnotations(ignore_dependencies={"depa"})
        resolver = PackageResolver(pkg, ctx, annotations, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.marker_dependencies), 0)

    def test_multi_version_dep_resolution(self):
        """Multiple versions of the same dep with different markers are preserved."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[
                make_dep("depA", "1.0", marker="sys_platform == 'linux'"),
                make_dep("depA", "2.0", marker="sys_platform == 'darwin'"),
            ],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.marker_dependencies), 2)
        versions = {md.key.version for md in resolved.marker_dependencies}
        self.assertIn(Version("1.0"), versions)
        self.assertIn(Version("2.0"), versions)

    def test_build_dependencies(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        build_dep_key = PackageKey.from_parts("setuptools", Version("60.0"))
        resolver = PackageResolver(pkg, ctx, None, default_build_dependencies=[build_dep_key])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.build_dependencies), 1)
        self.assertEqual(resolved.build_dependencies[0].name, "setuptools")

    def test_build_deps_not_duplicated(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")], deps=[make_dep("setuptools", "60.0")])
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        build_dep_key = PackageKey.from_parts("setuptools", Version("60.0"))
        resolver = PackageResolver(pkg, ctx, None, default_build_dependencies=[build_dep_key])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.build_dependencies), 0)

    # Source Selection
    def test_local_wheel_override(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")])
        ctx = GenerationContext(
            local_wheels={"foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl": "@//path:wheel"},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 1)
        self.assertEqual(resolved.wheel_candidates[0].file_reference.label, "@//path:wheel")
        self.assertIsNone(resolved.wheel_candidates[0].file_reference.key)

    def test_remote_wheel_override(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")])
        remote_wheel = PackageFile(
            name="foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl",
            sha256="remote_sha",
            urls=("https://remote.com/foo.whl",),
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={"foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl": remote_wheel},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 1)
        self.assertEqual(resolved.wheel_candidates[0].file_reference.key.hash_prefix, "remote_s")

    def test_always_include_sdist(self):
        pkg = make_pkg(
            "foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"), make_file("foo-1.0.tar.gz")]
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=True,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.wheel_candidates), 1)
        self.assertEqual(resolved.wheel_candidates[0].filename, "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")
        self.assertIsNotNone(resolved.sdist_file)
        self.assertEqual(resolved.sdist_file.key.name, "foo-1.0.tar.gz")

    def test_always_build_annotation(self):
        """With always_build, sdist is not auto-included unless always_include_sdist is set."""
        pkg = make_pkg(
            "foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"), make_file("foo-1.0.tar.gz")]
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=True,
        )
        annotations = PackageAnnotations(always_build=True)
        resolver = PackageResolver(pkg, ctx, annotations, [])
        resolved = resolver.to_resolved_package()

        self.assertTrue(resolver.uses_sdist)
        self.assertIsNotNone(resolved.sdist_file)
        self.assertEqual(resolved.sdist_file.key.name, "foo-1.0.tar.gz")

    # Annotations
    def test_build_target_override(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        annotations = PackageAnnotations(build_target="@//custom:build")
        resolver = PackageResolver(pkg, ctx, annotations, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(resolved.build_target, "@//custom:build")

    def test_install_exclude_globs(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        annotations = PackageAnnotations(install_exclude_globs={"tests/**"})
        resolver = PackageResolver(pkg, ctx, annotations, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("tests/**", resolved.install_exclude_globs)

    def test_pre_post_install_patches(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        annotations = PackageAnnotations(pre_build_patches=["@//:pre.patch"], post_install_patches=["@//:post.patch"])
        resolver = PackageResolver(pkg, ctx, annotations, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(resolved.pre_build_patches, ["@//:pre.patch"])
        self.assertEqual(resolved.post_install_patches, ["@//:post.patch"])

    # Edge Cases (python_version_incompatibility test removed — check_package_compatibility no longer exists)


class TestResolveFunction(unittest.TestCase):
    def setUp(self):
        import tempfile

        self.td = tempfile.TemporaryDirectory()
        self.td_path = self.td.name

    def tearDown(self):
        self.td.cleanup()

    def test_empty_lock(self):
        import os
        from unittest.mock import MagicMock

        lock_model_file = os.path.join(self.td_path, "lock.json")
        with open(lock_model_file, "w") as f:
            f.write(RawLockSet(python_versions=SpecifierSet(">=3.8"), packages={}, pins={}).to_json())

        args = MagicMock()
        args.lock_model_file = lock_model_file
        args.local_wheel = []
        args.remote_wheel = []
        args.always_include_sdist = False
        args.annotations_file = None
        args.default_build_dependencies = []
        args.disallow_builds = False
        args.default_alias_single_version = False

        resolved = resolve(args)
        self.assertEqual(len(resolved.packages), 0)

    def test_pinned_package_not_in_packages(self):
        import os
        from unittest.mock import MagicMock

        lock_model_file = os.path.join(self.td_path, "lock.json")
        with open(lock_model_file, "w") as f:
            f.write(
                RawLockSet(
                    python_versions=SpecifierSet(">=3.8"),
                    packages={},
                    pins={canonicalize_name("foo"): PackageKey.from_parts("foo", Version("1.0"))},
                ).to_json()
            )

        args = MagicMock()
        args.lock_model_file = lock_model_file
        args.local_wheel = []
        args.remote_wheel = []
        args.always_include_sdist = False
        args.annotations_file = None
        args.default_build_dependencies = []
        args.disallow_builds = False
        args.default_alias_single_version = False

        with self.assertRaises(KeyError):
            resolve(args)


class TestExtras(unittest.TestCase):
    def test_extras_basic(self):
        """Deps gated on extra == 'test' appear as marker_dependencies."""
        pkg = make_pkg(
            "foo[test]",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[
                make_dep("depA", "1.0"),
                make_dep("depB", "1.0", marker="extra == 'test'"),
            ],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        # Both deps should appear as marker_dependencies
        self.assertEqual(len(resolved.marker_dependencies), 2)
        dep_names = {md.key.name.package for md in resolved.marker_dependencies}
        self.assertIn("depa", dep_names)
        self.assertIn("depb", dep_names)

    def test_extras_with_env_markers(self):
        """A dep with both extra and platform markers preserves the combined marker."""
        pkg = make_pkg(
            "foo[test]",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[
                make_dep("depC", "1.0", marker="extra == 'test' and sys_platform == 'linux'"),
            ],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        # The dep should appear with its marker (extra stripped, platform marker preserved)
        self.assertEqual(len(resolved.marker_dependencies), 1)
        self.assertEqual(resolved.marker_dependencies[0].key.name.package, "depc")
        self.assertIn("sys_platform", resolved.marker_dependencies[0].marker)

    def test_extras_no_extras(self):
        """Packages without extra markers have normal deps."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[make_dep("depA", "1.0")],
        )
        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.marker_dependencies), 1)

    def test_extras_multiple(self):
        """Multiple extras ('test', 'dev') each pull different deps."""
        deps = [
            make_dep("depA", "1.0"),
            make_dep("pytest", "7.0", marker="extra == 'test'"),
            make_dep("black", "22.0", marker="extra == 'dev'"),
        ]

        ctx = GenerationContext(
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )

        pkg_test = make_pkg("foo[test]", "1.0", [make_file("foo-1.0.tar.gz")], deps=deps)
        resolver_test = PackageResolver(pkg_test, ctx, None, [])
        resolved_test = resolver_test.to_resolved_package()

        pkg_dev = make_pkg("foo[dev]", "1.0", [make_file("foo-1.0.tar.gz")], deps=deps)
        resolver_dev = PackageResolver(pkg_dev, ctx, None, [])
        resolved_dev = resolver_dev.to_resolved_package()

        # Check "test" extra has pytest
        test_dep_names = {md.key.name.package for md in resolved_test.marker_dependencies}
        self.assertIn("depa", test_dep_names)
        self.assertIn("pytest", test_dep_names)
        self.assertNotIn("black", test_dep_names)

        # Check "dev" extra has black
        dev_dep_names = {md.key.name.package for md in resolved_dev.marker_dependencies}
        self.assertIn("depa", dev_dep_names)
        self.assertIn("black", dev_dep_names)
        self.assertNotIn("pytest", dev_dep_names)


class TestCycleDetection(unittest.TestCase):
    """Tests for Tarjan's SCC-based cycle detection in resolve()."""

    def setUp(self):
        import tempfile

        self.td = tempfile.TemporaryDirectory()
        self.td_path = self.td.name

    def tearDown(self):
        self.td.cleanup()

    def _resolve_with_packages(self, packages, pins):
        """Helper to set up files and call resolve() with the given packages and pins."""
        import os
        from unittest.mock import MagicMock

        pkg_dict = {}
        for pkg in packages:
            pkg_dict[pkg.key] = pkg

        lock_model = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            packages=pkg_dict,
            pins=pins,
        )
        lock_model_file = os.path.join(self.td_path, "lock.json")
        with open(lock_model_file, "w") as f:
            f.write(lock_model.to_json())

        args = MagicMock()
        args.lock_model_file = lock_model_file
        args.local_wheel = []
        args.remote_wheel = []
        args.always_include_sdist = False
        args.annotations_file = None
        args.default_build_dependencies = []
        args.disallow_builds = False
        args.default_alias_single_version = False

        return resolve(args)

    def test_cycle_two_nodes(self):
        """A depends on B, B depends on A. Both should have the same cycle_group."""
        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")], deps=[make_dep("b", "1.0")])
        pkg_b = make_pkg("b", "1.0", [make_file("b-1.0.tar.gz")], deps=[make_dep("a", "1.0")])
        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
            canonicalize_name("b"): PackageKey.from_parts(canonicalize_name("b"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_b], pins)

        key_a = PackageKey.from_parts(canonicalize_name("a"), Version("1.0"))
        key_b = PackageKey.from_parts(canonicalize_name("b"), Version("1.0"))

        self.assertIsNotNone(resolved.packages[key_a].cycle_group)
        self.assertIsNotNone(resolved.packages[key_b].cycle_group)
        self.assertEqual(resolved.packages[key_a].cycle_group, resolved.packages[key_b].cycle_group)

        # The cycle group should exist in the top-level mapping
        group_name = resolved.packages[key_a].cycle_group
        self.assertIn(group_name, resolved.cycle_groups)
        self.assertEqual(len(resolved.cycle_groups[group_name]), 2)

    def test_cycle_three_nodes(self):
        """A→B→C→A. All three in the same cycle group."""
        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")], deps=[make_dep("b", "1.0")])
        pkg_b = make_pkg("b", "1.0", [make_file("b-1.0.tar.gz")], deps=[make_dep("c", "1.0")])
        pkg_c = make_pkg("c", "1.0", [make_file("c-1.0.tar.gz")], deps=[make_dep("a", "1.0")])
        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
            canonicalize_name("b"): PackageKey.from_parts(canonicalize_name("b"), Version("1.0")),
            canonicalize_name("c"): PackageKey.from_parts(canonicalize_name("c"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_b, pkg_c], pins)

        key_a = PackageKey.from_parts(canonicalize_name("a"), Version("1.0"))
        key_b = PackageKey.from_parts(canonicalize_name("b"), Version("1.0"))
        key_c = PackageKey.from_parts(canonicalize_name("c"), Version("1.0"))

        group = resolved.packages[key_a].cycle_group
        self.assertIsNotNone(group)
        self.assertEqual(resolved.packages[key_b].cycle_group, group)
        self.assertEqual(resolved.packages[key_c].cycle_group, group)
        self.assertEqual(len(resolved.cycle_groups[group]), 3)

    def test_no_cycles(self):
        """Simple A→B→C chain. No cycle_group should be assigned."""
        pkg_c = make_pkg("c", "1.0", [make_file("c-1.0.tar.gz")])
        pkg_b = make_pkg("b", "1.0", [make_file("b-1.0.tar.gz")], deps=[make_dep("c", "1.0")])
        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")], deps=[make_dep("b", "1.0")])
        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_b, pkg_c], pins)

        for pkg in resolved.packages.values():
            self.assertIsNone(pkg.cycle_group)
        self.assertEqual(len(resolved.cycle_groups), 0)

    def test_cycle_group_naming_stable(self):
        """Same cycle members should always produce the same hash-based name."""
        import hashlib

        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")], deps=[make_dep("b", "1.0")])
        pkg_b = make_pkg("b", "1.0", [make_file("b-1.0.tar.gz")], deps=[make_dep("a", "1.0")])
        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
            canonicalize_name("b"): PackageKey.from_parts(canonicalize_name("b"), Version("1.0")),
        }

        resolved1 = self._resolve_with_packages([pkg_a, pkg_b], pins)
        resolved2 = self._resolve_with_packages([pkg_a, pkg_b], pins)

        key_a = PackageKey.from_parts(canonicalize_name("a"), Version("1.0"))
        group1 = resolved1.packages[key_a].cycle_group
        group2 = resolved2.packages[key_a].cycle_group
        self.assertEqual(group1, group2)

        # Verify it matches the expected format: cycle_group_<sha256[:8]>
        members = sorted(
            [
                PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
                PackageKey.from_parts(canonicalize_name("b"), Version("1.0")),
            ]
        )
        expected_digest = hashlib.sha256("\n".join(str(m) for m in members).encode()).hexdigest()[:8]
        expected_name = f"group_{expected_digest}"
        self.assertEqual(group1, expected_name)

    def test_multiple_disconnected_cycles(self):
        """Two independent cycles should produce two separate groups."""
        # Cycle 1: A <-> B
        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")], deps=[make_dep("b", "1.0")])
        pkg_b = make_pkg("b", "1.0", [make_file("b-1.0.tar.gz")], deps=[make_dep("a", "1.0")])
        # Cycle 2: X <-> Y
        pkg_x = make_pkg("x", "1.0", [make_file("x-1.0.tar.gz")], deps=[make_dep("y", "1.0")])
        pkg_y = make_pkg("y", "1.0", [make_file("y-1.0.tar.gz")], deps=[make_dep("x", "1.0")])
        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
            canonicalize_name("b"): PackageKey.from_parts(canonicalize_name("b"), Version("1.0")),
            canonicalize_name("x"): PackageKey.from_parts(canonicalize_name("x"), Version("1.0")),
            canonicalize_name("y"): PackageKey.from_parts(canonicalize_name("y"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_b, pkg_x, pkg_y], pins)

        key_a = PackageKey.from_parts(canonicalize_name("a"), Version("1.0"))
        key_b = PackageKey.from_parts(canonicalize_name("b"), Version("1.0"))
        key_x = PackageKey.from_parts(canonicalize_name("x"), Version("1.0"))
        key_y = PackageKey.from_parts(canonicalize_name("y"), Version("1.0"))

        group_ab = resolved.packages[key_a].cycle_group
        group_xy = resolved.packages[key_x].cycle_group

        # Both cycles should be detected
        self.assertIsNotNone(group_ab)
        self.assertIsNotNone(group_xy)

        # Members within each cycle share the same group
        self.assertEqual(resolved.packages[key_a].cycle_group, resolved.packages[key_b].cycle_group)
        self.assertEqual(resolved.packages[key_x].cycle_group, resolved.packages[key_y].cycle_group)

        # The two cycles should have different group names
        self.assertNotEqual(group_ab, group_xy)

        # Two distinct cycle groups
        self.assertEqual(len(resolved.cycle_groups), 2)

    def test_cycle_via_extra(self):
        """A cycle formed via an extra dependency should be detected."""
        # foo -> depA (base)
        # depA -> depB (extra test)
        # depB -> depA (base) - cycle A <-> B
        pkg_foo = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[
                make_dep("depA[test]", "1.0"),
            ],
        )
        pkg_dep_a = make_pkg(
            "depA",
            "1.0",
            [make_file("depA-1.0.tar.gz")],
            deps=[
                make_dep("depB", "1.0", marker="extra == 'test'"),
            ],
        )
        pkg_dep_b = make_pkg(
            "depB",
            "1.0",
            [make_file("depB-1.0.tar.gz")],
            deps=[
                make_dep("depA[test]", "1.0"),
            ],
        )

        pins = {
            canonicalize_name("foo"): PackageKey.from_parts(canonicalize_name("foo"), Version("1.0")),
        }

        # Resolve packages
        resolved = self._resolve_with_packages([pkg_foo, pkg_dep_a, pkg_dep_b], pins)

        key_a_test = PackageKey.from_parts(DependencyName("depA[test]"), Version("1.0"))
        key_b = PackageKey.from_parts(canonicalize_name("depB"), Version("1.0"))

        # depA[test] and depB should be in a cycle group
        res_a_test = resolved.packages[key_a_test]
        res_b = resolved.packages[key_b]
        self.assertIsNotNone(res_a_test.cycle_group)
        self.assertIsNotNone(res_b.cycle_group)
        self.assertEqual(res_a_test.cycle_group, res_b.cycle_group)

    def test_cycle_eight_member_hub_and_spoke(self):
        """Stress test: 8-member hub-and-spoke cycle modeled after Apache Airflow.

        airflow → airflow-core, task-sdk
        airflow-core → provider-compat, provider-io, provider-sql, provider-smtp, provider-standard, task-sdk
        provider-compat → airflow  (back-edge)
        provider-io → airflow  (back-edge)
        provider-sql → airflow  (back-edge)
        provider-smtp → airflow, provider-compat  (back-edges)
        provider-standard → airflow  (back-edge)
        task-sdk → airflow-core  (back-edge)

        Plus non-cycle leaves: packaging, jinja2, attrs
        """
        # Non-cycle leaf packages
        pkg_packaging = make_pkg("packaging", "1.0", [make_file("packaging-1.0.tar.gz")])
        pkg_jinja2 = make_pkg("jinja2", "1.0", [make_file("jinja2-1.0.tar.gz")])
        pkg_attrs = make_pkg("attrs", "1.0", [make_file("attrs-1.0.tar.gz")])

        # Cycle members
        pkg_airflow = make_pkg(
            "airflow",
            "2.0",
            [make_file("airflow-2.0.tar.gz")],
            deps=[make_dep("airflow-core", "2.0"), make_dep("task-sdk", "2.0")],
        )
        pkg_core = make_pkg(
            "airflow-core",
            "2.0",
            [make_file("airflow_core-2.0.tar.gz")],
            deps=[
                make_dep("provider-compat", "2.0"),
                make_dep("provider-io", "2.0"),
                make_dep("provider-sql", "2.0"),
                make_dep("provider-smtp", "2.0"),
                make_dep("provider-standard", "2.0"),
                make_dep("task-sdk", "2.0"),
                make_dep("packaging", "1.0"),
                make_dep("jinja2", "1.0"),
            ],
        )
        pkg_task_sdk = make_pkg(
            "task-sdk",
            "2.0",
            [make_file("task_sdk-2.0.tar.gz")],
            deps=[make_dep("airflow-core", "2.0"), make_dep("attrs", "1.0")],
        )
        pkg_compat = make_pkg(
            "provider-compat",
            "2.0",
            [make_file("provider_compat-2.0.tar.gz")],
            deps=[make_dep("airflow", "2.0")],
        )
        pkg_io = make_pkg(
            "provider-io",
            "2.0",
            [make_file("provider_io-2.0.tar.gz")],
            deps=[make_dep("airflow", "2.0")],
        )
        pkg_sql = make_pkg(
            "provider-sql",
            "2.0",
            [make_file("provider_sql-2.0.tar.gz")],
            deps=[make_dep("airflow", "2.0")],
        )
        pkg_smtp = make_pkg(
            "provider-smtp",
            "2.0",
            [make_file("provider_smtp-2.0.tar.gz")],
            deps=[make_dep("airflow", "2.0"), make_dep("provider-compat", "2.0")],
        )
        pkg_standard = make_pkg(
            "provider-standard",
            "2.0",
            [make_file("provider_standard-2.0.tar.gz")],
            deps=[make_dep("airflow", "2.0")],
        )

        all_packages = [
            pkg_airflow,
            pkg_core,
            pkg_task_sdk,
            pkg_compat,
            pkg_io,
            pkg_sql,
            pkg_smtp,
            pkg_standard,
            pkg_packaging,
            pkg_jinja2,
            pkg_attrs,
        ]
        pins = {
            canonicalize_name("airflow"): PackageKey.from_parts(canonicalize_name("airflow"), Version("2.0")),
        }

        resolved = self._resolve_with_packages(all_packages, pins)

        # All 8 cycle members should share the same cycle group
        cycle_member_names = [
            "airflow",
            "airflow-core",
            "task-sdk",
            "provider-compat",
            "provider-io",
            "provider-sql",
            "provider-smtp",
            "provider-standard",
        ]
        cycle_keys = [PackageKey.from_parts(canonicalize_name(n), Version("2.0")) for n in cycle_member_names]

        groups = set()
        for key in cycle_keys:
            self.assertIn(key, resolved.packages, f"Package {key} not found in resolved packages")
            group = resolved.packages[key].cycle_group
            self.assertIsNotNone(group, f"Package {key} should be in a cycle group")
            groups.add(group)

        self.assertEqual(len(groups), 1, f"All 8 members should share one cycle group, got {groups}")
        group_name = groups.pop()
        self.assertEqual(len(resolved.cycle_groups[group_name]), 8)

        # Non-cycle packages should NOT be in any cycle group
        for leaf_name in ["packaging", "jinja2", "attrs"]:
            leaf_key = PackageKey.from_parts(canonicalize_name(leaf_name), Version("1.0"))
            self.assertIsNone(
                resolved.packages[leaf_key].cycle_group,
                f"Leaf {leaf_name} should not be in a cycle group",
            )

    def test_cycle_with_non_cycle_tail(self):
        """A 3-member cycle with a long non-cyclic tail: cycle shouldn't leak.

        Cycle: A ↔ B ↔ C ↔ A
        Tail: C → D → E → F → G (no back-edge)
        """
        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")], deps=[make_dep("b", "1.0")])
        pkg_b = make_pkg("b", "1.0", [make_file("b-1.0.tar.gz")], deps=[make_dep("c", "1.0")])
        pkg_c = make_pkg(
            "c",
            "1.0",
            [make_file("c-1.0.tar.gz")],
            deps=[
                make_dep("a", "1.0"),
                make_dep("d", "1.0"),
            ],
        )
        pkg_d = make_pkg("d", "1.0", [make_file("d-1.0.tar.gz")], deps=[make_dep("e", "1.0")])
        pkg_e = make_pkg("e", "1.0", [make_file("e-1.0.tar.gz")], deps=[make_dep("f", "1.0")])
        pkg_f = make_pkg("f", "1.0", [make_file("f-1.0.tar.gz")], deps=[make_dep("g", "1.0")])
        pkg_g = make_pkg("g", "1.0", [make_file("g-1.0.tar.gz")])

        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_b, pkg_c, pkg_d, pkg_e, pkg_f, pkg_g], pins)

        # A, B, C should be in one cycle group
        key_a = PackageKey.from_parts(canonicalize_name("a"), Version("1.0"))
        key_b = PackageKey.from_parts(canonicalize_name("b"), Version("1.0"))
        key_c = PackageKey.from_parts(canonicalize_name("c"), Version("1.0"))
        group = resolved.packages[key_a].cycle_group
        self.assertIsNotNone(group)
        self.assertEqual(resolved.packages[key_b].cycle_group, group)
        self.assertEqual(resolved.packages[key_c].cycle_group, group)
        self.assertEqual(len(resolved.cycle_groups[group]), 3)

        # D, E, F, G should NOT be in any cycle group
        for name in ["d", "e", "f", "g"]:
            key = PackageKey.from_parts(canonicalize_name(name), Version("1.0"))
            self.assertIsNone(
                resolved.packages[key].cycle_group,
                f"Tail package {name} should not be in a cycle group",
            )

    def test_conditional_cycle_union_semantics(self):
        """A cycle that only exists on one platform (linux) via markers.

        A → B (unconditional)
        B → A (only on linux: sys_platform == 'linux')

        Both should still be grouped because the SCC runs on the union graph.
        """
        pkg_a = make_pkg(
            "a",
            "1.0",
            [make_file("a-1.0.tar.gz")],
            deps=[make_dep("b", "1.0")],
        )
        pkg_b = make_pkg(
            "b",
            "1.0",
            [make_file("b-1.0.tar.gz")],
            deps=[make_dep("a", "1.0", marker="sys_platform == 'linux'")],
        )
        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
            canonicalize_name("b"): PackageKey.from_parts(canonicalize_name("b"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_b], pins)

        key_a = PackageKey.from_parts(canonicalize_name("a"), Version("1.0"))
        key_b = PackageKey.from_parts(canonicalize_name("b"), Version("1.0"))

        # Under union semantics, both should be in the same cycle group
        # even though the cycle only exists on linux
        self.assertIsNotNone(resolved.packages[key_a].cycle_group)
        self.assertIsNotNone(resolved.packages[key_b].cycle_group)
        self.assertEqual(
            resolved.packages[key_a].cycle_group,
            resolved.packages[key_b].cycle_group,
        )

    def test_interconnected_cycles(self):
        """A more complex graph with multiple interconnected cycles (graph4 in rules_py).

        a -> b
        b -> c, e
        c -> d
        d -> b  (cycle b-c-d)
        e -> f
        f -> e, g  (cycle e-f)
        g (leaf)
        """
        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")], deps=[make_dep("b", "1.0")])
        pkg_b = make_pkg("b", "1.0", [make_file("b-1.0.tar.gz")], deps=[make_dep("c", "1.0"), make_dep("e", "1.0")])
        pkg_c = make_pkg("c", "1.0", [make_file("c-1.0.tar.gz")], deps=[make_dep("d", "1.0")])
        pkg_d = make_pkg("d", "1.0", [make_file("d-1.0.tar.gz")], deps=[make_dep("b", "1.0")])
        pkg_e = make_pkg("e", "1.0", [make_file("e-1.0.tar.gz")], deps=[make_dep("f", "1.0")])
        pkg_f = make_pkg("f", "1.0", [make_file("f-1.0.tar.gz")], deps=[make_dep("e", "1.0"), make_dep("g", "1.0")])
        pkg_g = make_pkg("g", "1.0", [make_file("g-1.0.tar.gz")])

        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_b, pkg_c, pkg_d, pkg_e, pkg_f, pkg_g], pins)

        key_a = PackageKey.from_parts(canonicalize_name("a"), Version("1.0"))
        key_b = PackageKey.from_parts(canonicalize_name("b"), Version("1.0"))
        key_c = PackageKey.from_parts(canonicalize_name("c"), Version("1.0"))
        key_d = PackageKey.from_parts(canonicalize_name("d"), Version("1.0"))
        key_e = PackageKey.from_parts(canonicalize_name("e"), Version("1.0"))
        key_f = PackageKey.from_parts(canonicalize_name("f"), Version("1.0"))
        key_g = PackageKey.from_parts(canonicalize_name("g"), Version("1.0"))

        # b, c, d should be in one cycle group
        group_bcd = resolved.packages[key_b].cycle_group
        self.assertIsNotNone(group_bcd)
        self.assertEqual(resolved.packages[key_c].cycle_group, group_bcd)
        self.assertEqual(resolved.packages[key_d].cycle_group, group_bcd)
        self.assertEqual(len(resolved.cycle_groups[group_bcd]), 3)

        # e, f should be in another cycle group
        group_ef = resolved.packages[key_e].cycle_group
        self.assertIsNotNone(group_ef)
        self.assertEqual(resolved.packages[key_f].cycle_group, group_ef)
        self.assertEqual(len(resolved.cycle_groups[group_ef]), 2)

        # They must be different groups
        self.assertNotEqual(group_bcd, group_ef)

        # a and g should NOT be in any cycle group
        self.assertIsNone(resolved.packages[key_a].cycle_group)
        self.assertIsNone(resolved.packages[key_g].cycle_group)

    def test_no_cycles_diamond(self):
        """A diamond graph with no cycles (graph1 in rules_py).

        a -> b, c
        b -> d
        c -> d
        d (leaf)
        """
        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")], deps=[make_dep("b", "1.0"), make_dep("c", "1.0")])
        pkg_b = make_pkg("b", "1.0", [make_file("b-1.0.tar.gz")], deps=[make_dep("d", "1.0")])
        pkg_c = make_pkg("c", "1.0", [make_file("c-1.0.tar.gz")], deps=[make_dep("d", "1.0")])
        pkg_d = make_pkg("d", "1.0", [make_file("d-1.0.tar.gz")])

        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_b, pkg_c, pkg_d], pins)

        for pkg in resolved.packages.values():
            self.assertIsNone(pkg.cycle_group)
        self.assertEqual(len(resolved.cycle_groups), 0)

    def test_self_loop(self):
        """A package depending on itself. Should not be grouped (ignored as size 1)."""
        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")], deps=[make_dep("a", "1.0")])
        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
        }
        resolved = self._resolve_with_packages([pkg_a], pins)
        key_a = PackageKey.from_parts(canonicalize_name("a"), Version("1.0"))
        self.assertIsNone(resolved.packages[key_a].cycle_group)
        self.assertEqual(len(resolved.cycle_groups), 0)

    def test_unpinned_cycle_still_emitted(self):
        """A cycle exists in the lock model but none of its members are pinned.

        Packages x, y, z form a cycle but are not reachable from any pin.
        The full-graph Tarjan detects the SCC and the cycle group IS emitted
        (cycle groups are a pure property of the graph).  However, no resolved
        packages receive cycle_group annotations because x/y/z are not part
        of the resolved set.
        """
        # Pinned leaf — completely disconnected from the cycle
        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")])

        # Unpinned cycle: x → y → z → x
        pkg_x = make_pkg("x", "1.0", [make_file("x-1.0.tar.gz")], deps=[make_dep("y", "1.0")])
        pkg_y = make_pkg("y", "1.0", [make_file("y-1.0.tar.gz")], deps=[make_dep("z", "1.0")])
        pkg_z = make_pkg("z", "1.0", [make_file("z-1.0.tar.gz")], deps=[make_dep("x", "1.0")])

        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_x, pkg_y, pkg_z], pins)

        # a is resolved, x/y/z are not
        key_a = PackageKey.from_parts(canonicalize_name("a"), Version("1.0"))
        self.assertIn(key_a, resolved.packages)
        for name in ["x", "y", "z"]:
            key = PackageKey.from_parts(canonicalize_name(name), Version("1.0"))
            self.assertNotIn(key, resolved.packages)

        # The cycle group IS emitted (it's a graph property, not pin-dependent)
        self.assertEqual(len(resolved.cycle_groups), 1)

        # But no resolved package has a cycle_group annotation
        for pkg in resolved.packages.values():
            self.assertIsNone(pkg.cycle_group)

    def test_partially_pinned_cycle(self):
        """A 4-member cycle where only 1 member is directly pinned.

        a → b → c → d → a (cycle)
        Only 'a' is pinned; b, c, d are reached transitively.
        All four should still be detected as one cycle group.
        """
        pkg_a = make_pkg("a", "1.0", [make_file("a-1.0.tar.gz")], deps=[make_dep("b", "1.0")])
        pkg_b = make_pkg("b", "1.0", [make_file("b-1.0.tar.gz")], deps=[make_dep("c", "1.0")])
        pkg_c = make_pkg("c", "1.0", [make_file("c-1.0.tar.gz")], deps=[make_dep("d", "1.0")])
        pkg_d = make_pkg("d", "1.0", [make_file("d-1.0.tar.gz")], deps=[make_dep("a", "1.0")])

        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_b, pkg_c, pkg_d], pins)

        keys = [PackageKey.from_parts(canonicalize_name(n), Version("1.0")) for n in ["a", "b", "c", "d"]]
        group = resolved.packages[keys[0]].cycle_group
        self.assertIsNotNone(group)
        for key in keys[1:]:
            self.assertEqual(resolved.packages[key].cycle_group, group)
        self.assertEqual(len(resolved.cycle_groups[group]), 4)

    def test_version_isolation(self):
        """Different versions of the same package should be independent for cycle detection.

        foo@1.0 → bar@1.0 → foo@1.0  (cycle)
        foo@2.0 → baz@1.0             (no cycle)
        """
        pkg_foo1 = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")], deps=[make_dep("bar", "1.0")])
        pkg_bar = make_pkg("bar", "1.0", [make_file("bar-1.0.tar.gz")], deps=[make_dep("foo", "1.0")])
        pkg_foo2 = make_pkg("foo", "2.0", [make_file("foo-2.0.tar.gz")], deps=[make_dep("baz", "1.0")])
        pkg_baz = make_pkg("baz", "1.0", [make_file("baz-1.0.tar.gz")])

        pins = {
            canonicalize_name("foo"): {
                "": PackageKey.from_parts(canonicalize_name("foo"), Version("1.0")),
                "v2": PackageKey.from_parts(canonicalize_name("foo"), Version("2.0")),
            },
        }

        resolved = self._resolve_with_packages([pkg_foo1, pkg_bar, pkg_foo2, pkg_baz], pins)

        key_foo1 = PackageKey.from_parts(canonicalize_name("foo"), Version("1.0"))
        key_bar = PackageKey.from_parts(canonicalize_name("bar"), Version("1.0"))
        key_foo2 = PackageKey.from_parts(canonicalize_name("foo"), Version("2.0"))
        key_baz = PackageKey.from_parts(canonicalize_name("baz"), Version("1.0"))

        # foo@1.0 and bar@1.0 should be in a cycle
        group = resolved.packages[key_foo1].cycle_group
        self.assertIsNotNone(group)
        self.assertEqual(resolved.packages[key_bar].cycle_group, group)
        self.assertEqual(len(resolved.cycle_groups[group]), 2)

        # foo@2.0 and baz@1.0 should NOT be in any cycle
        self.assertIsNone(resolved.packages[key_foo2].cycle_group)
        self.assertIsNone(resolved.packages[key_baz].cycle_group)

    def test_cross_platform_marker_cycle(self):
        """A cycle where each edge is gated by a different platform marker.

        a → b  (only on linux: sys_platform == 'linux')
        b → a  (only on windows: sys_platform == 'win32')

        No single platform has this cycle, but the union graph does.
        Since we ignore markers in cycle detection, both should be grouped.
        """
        pkg_a = make_pkg(
            "a",
            "1.0",
            [make_file("a-1.0.tar.gz")],
            deps=[make_dep("b", "1.0", marker="sys_platform == 'linux'")],
        )
        pkg_b = make_pkg(
            "b",
            "1.0",
            [make_file("b-1.0.tar.gz")],
            deps=[make_dep("a", "1.0", marker="sys_platform == 'win32'")],
        )
        pins = {
            canonicalize_name("a"): PackageKey.from_parts(canonicalize_name("a"), Version("1.0")),
            canonicalize_name("b"): PackageKey.from_parts(canonicalize_name("b"), Version("1.0")),
        }

        resolved = self._resolve_with_packages([pkg_a, pkg_b], pins)

        key_a = PackageKey.from_parts(canonicalize_name("a"), Version("1.0"))
        key_b = PackageKey.from_parts(canonicalize_name("b"), Version("1.0"))

        # Both should be in the same cycle group despite no single
        # platform having both edges
        self.assertIsNotNone(resolved.packages[key_a].cycle_group)
        self.assertEqual(
            resolved.packages[key_a].cycle_group,
            resolved.packages[key_b].cycle_group,
        )


class TestCollectPackageAnnotations(unittest.TestCase):
    """Tests for collect_package_annotations, including wildcard '*' support."""

    def setUp(self):
        import tempfile

        self.td = tempfile.TemporaryDirectory()
        self.td_path = self.td.name

    def tearDown(self):
        self.td.cleanup()

    def _make_lock_model(self, packages):
        pkg_dict = {}
        for pkg in packages:
            pkg_dict[pkg.key] = pkg
        return RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            packages=pkg_dict,
            pins={},
        )

    def _make_args(self, annotations_data):
        import json
        import os
        from unittest.mock import MagicMock

        args = MagicMock()
        if annotations_data is not None:
            annotations_file = os.path.join(self.td_path, "annotations.json")
            with open(annotations_file, "w") as f:
                json.dump(annotations_data, f)
            args.annotations_file = annotations_file
        else:
            args.annotations_file = None
        return args

    def test_no_annotations_file(self):
        """No annotations file returns empty dict and empty wildcard keys."""
        lock_model = self._make_lock_model([make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])])
        args = self._make_args(None)

        annotations, wildcard_keys = collect_package_annotations(args, lock_model)
        self.assertEqual(annotations, {})
        self.assertEqual(wildcard_keys, set())

    def test_specific_annotation_only(self):
        """A specific annotation applies to the named package only."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
                make_pkg("bar", "2.0", [make_file("bar-2.0.tar.gz")]),
            ]
        )
        args = self._make_args({"foo": {"always_build": True}})

        annotations, wildcard_keys = collect_package_annotations(args, lock_model)

        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        self.assertIn(foo_key, annotations)
        self.assertTrue(annotations[foo_key].always_build)

        bar_key = PackageKey.from_parts("bar", Version("2.0"))
        self.assertNotIn(bar_key, annotations)
        self.assertEqual(wildcard_keys, set())

    def test_wildcard_applies_to_all_packages(self):
        """Wildcard '*' annotation applies to every package in the lock model."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
                make_pkg("bar", "2.0", [make_file("bar-2.0.tar.gz")]),
                make_pkg("baz", "3.0", [make_file("baz-3.0.tar.gz")]),
            ]
        )
        args = self._make_args({"*": {"always_build": True}})

        annotations, wildcard_keys = collect_package_annotations(args, lock_model)

        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        bar_key = PackageKey.from_parts("bar", Version("2.0"))
        baz_key = PackageKey.from_parts("baz", Version("3.0"))

        for key in [foo_key, bar_key, baz_key]:
            self.assertIn(key, annotations)
            self.assertTrue(annotations[key].always_build)

        self.assertEqual(wildcard_keys, {foo_key, bar_key, baz_key})

    def test_wildcard_scalar_fields(self):
        """Wildcard correctly sets scalar fields: always_build, build_target, build_repo, build_backend."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
            ]
        )
        args = self._make_args(
            {
                "*": {
                    "always_build": True,
                    "build_target": "@//custom:target",
                    "build_repo": "build_deps",
                    "build_backend": "meson_build",
                }
            }
        )

        annotations, _ = collect_package_annotations(args, lock_model)
        foo_key = PackageKey.from_parts("foo", Version("1.0"))

        self.assertTrue(annotations[foo_key].always_build)
        self.assertEqual(annotations[foo_key].build_target, "@//custom:target")
        self.assertEqual(annotations[foo_key].build_repo, "build_deps")
        self.assertEqual(annotations[foo_key].build_backend, "meson_build")

    def test_wildcard_collection_fields(self):
        """Wildcard correctly sets collection fields: install_exclude_globs, pre_build_patches, etc."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
            ]
        )
        args = self._make_args(
            {
                "*": {
                    "install_exclude_globs": ["*.pyc", "__pycache__/**"],
                    "pre_build_patches": ["@//:fix.patch"],
                    "post_install_patches": ["@//:post.patch"],
                    "site_hooks": ["import foo"],
                }
            }
        )

        annotations, _ = collect_package_annotations(args, lock_model)
        foo_key = PackageKey.from_parts("foo", Version("1.0"))

        self.assertEqual(annotations[foo_key].install_exclude_globs, {"*.pyc", "__pycache__/**"})
        self.assertEqual(annotations[foo_key].pre_build_patches, ["@//:fix.patch"])
        self.assertEqual(annotations[foo_key].post_install_patches, ["@//:post.patch"])
        self.assertEqual(annotations[foo_key].site_hooks, ["import foo"])

    # --- Replace Semantics ---

    def test_specific_fully_replaces_wildcard(self):
        """A specific annotation fully replaces the wildcard for that package."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
                make_pkg("bar", "2.0", [make_file("bar-2.0.tar.gz")]),
            ]
        )
        args = self._make_args(
            {
                "*": {"always_build": True, "install_exclude_globs": ["*.pyc"]},
                "foo": {"always_build": False},
            }
        )

        annotations, wildcard_keys = collect_package_annotations(args, lock_model)

        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        bar_key = PackageKey.from_parts("bar", Version("2.0"))

        # foo has specific annotation: wildcard is fully replaced
        self.assertFalse(annotations[foo_key].always_build)
        # Crucially, foo does NOT inherit install_exclude_globs from wildcard
        self.assertEqual(annotations[foo_key].install_exclude_globs, set())

        # bar has no specific annotation: gets wildcard
        self.assertTrue(annotations[bar_key].always_build)
        self.assertEqual(annotations[bar_key].install_exclude_globs, {"*.pyc"})

        # foo is not in wildcard_only_keys; bar is
        self.assertNotIn(foo_key, wildcard_keys)
        self.assertIn(bar_key, wildcard_keys)

    def test_specific_does_not_merge_collections_from_wildcard(self):
        """Specific annotations don't merge list/set fields from wildcard — full replace."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
            ]
        )
        args = self._make_args(
            {
                "*": {"pre_build_patches": ["@//:global.patch"], "site_hooks": ["import hook"]},
                "foo": {"pre_build_patches": ["@//:foo.patch"]},
            }
        )

        annotations, _ = collect_package_annotations(args, lock_model)
        foo_key = PackageKey.from_parts("foo", Version("1.0"))

        # foo should only have its own patch, not the wildcard's
        self.assertEqual(annotations[foo_key].pre_build_patches, ["@//:foo.patch"])
        # site_hooks from wildcard should NOT be inherited
        self.assertEqual(annotations[foo_key].site_hooks, [])

    def test_specific_replaces_wildcard_scalars(self):
        """Specific scalar values replace wildcard scalars; unmentioned scalars stay default."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
            ]
        )
        args = self._make_args(
            {
                "*": {"build_repo": "global_build", "always_build": True},
                "foo": {"build_repo": "foo_build"},
            }
        )

        annotations, _ = collect_package_annotations(args, lock_model)
        foo_key = PackageKey.from_parts("foo", Version("1.0"))

        # build_repo replaced
        self.assertEqual(annotations[foo_key].build_repo, "foo_build")
        # always_build NOT inherited from wildcard (full replace)
        self.assertFalse(annotations[foo_key].always_build)

    # --- Wildcard-Only Key Tracking ---

    def test_wildcard_only_keys_exclude_specific(self):
        """wildcard_only_keys does not include packages with specific annotations."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
                make_pkg("bar", "2.0", [make_file("bar-2.0.tar.gz")]),
                make_pkg("baz", "3.0", [make_file("baz-3.0.tar.gz")]),
            ]
        )
        args = self._make_args(
            {
                "*": {"always_build": True},
                "foo": {"always_build": False},
                "baz": {"build_target": "@//custom:baz"},
            }
        )

        _, wildcard_keys = collect_package_annotations(args, lock_model)

        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        bar_key = PackageKey.from_parts("bar", Version("2.0"))
        baz_key = PackageKey.from_parts("baz", Version("3.0"))

        # Only bar is wildcard-only; foo and baz have specific annotations
        self.assertNotIn(foo_key, wildcard_keys)
        self.assertIn(bar_key, wildcard_keys)
        self.assertNotIn(baz_key, wildcard_keys)

    def test_no_wildcard_returns_empty_wildcard_keys(self):
        """Without wildcard, wildcard_only_keys is empty."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
            ]
        )
        args = self._make_args({"foo": {"always_build": True}})

        _, wildcard_keys = collect_package_annotations(args, lock_model)
        self.assertEqual(wildcard_keys, set())

    # --- build_repo ---

    def test_build_repo_specific(self):
        """build_repo flows through annotation to the resolved data."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
            ]
        )
        args = self._make_args({"foo": {"build_repo": "my_build_repo"}})

        annotations, _ = collect_package_annotations(args, lock_model)
        foo_key = PackageKey.from_parts("foo", Version("1.0"))

        self.assertEqual(annotations[foo_key].build_repo, "my_build_repo")

    def test_build_repo_wildcard(self):
        """build_repo from wildcard applies to all packages."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
                make_pkg("bar", "2.0", [make_file("bar-2.0.tar.gz")]),
            ]
        )
        args = self._make_args({"*": {"build_repo": "shared_build"}})

        annotations, _ = collect_package_annotations(args, lock_model)

        for key in annotations:
            self.assertEqual(annotations[key].build_repo, "shared_build")

    def test_build_repo_default_is_none(self):
        """build_repo defaults to None when not specified."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
            ]
        )
        args = self._make_args({"foo": {"always_build": True}})

        annotations, _ = collect_package_annotations(args, lock_model)
        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        self.assertIsNone(annotations[foo_key].build_repo)

    # --- Path fields ---

    def test_wildcard_path_fields(self):
        """Wildcard sets site_paths, bin_paths, data_paths, include_paths."""
        lock_model = self._make_lock_model(
            [
                make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")]),
            ]
        )
        args = self._make_args(
            {
                "*": {
                    "site_paths": ["src"],
                    "bin_paths": ["bin"],
                    "data_paths": ["data"],
                    "include_paths": ["include"],
                }
            }
        )

        annotations, _ = collect_package_annotations(args, lock_model)
        foo_key = PackageKey.from_parts("foo", Version("1.0"))

        self.assertEqual(annotations[foo_key].site_paths, ["src"])
        self.assertEqual(annotations[foo_key].bin_paths, ["bin"])
        self.assertEqual(annotations[foo_key].data_paths, ["data"])
        self.assertEqual(annotations[foo_key].include_paths, ["include"])


class TestWildcardEndToEnd(unittest.TestCase):
    """End-to-end tests for wildcard annotations through resolve()."""

    def setUp(self):
        import tempfile

        self.td = tempfile.TemporaryDirectory()
        self.td_path = self.td.name

    def tearDown(self):
        self.td.cleanup()

    def _resolve_with_annotations(self, packages, pins, annotations_data=None):
        """Helper to call resolve() with optional annotations."""
        import json
        import os
        from unittest.mock import MagicMock

        pkg_dict = {}
        for pkg in packages:
            pkg_dict[pkg.key] = pkg

        lock_model = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            packages=pkg_dict,
            pins=pins,
        )
        lock_model_file = os.path.join(self.td_path, "lock.json")
        with open(lock_model_file, "w") as f:
            f.write(lock_model.to_json())

        args = MagicMock()
        args.lock_model_file = lock_model_file
        args.local_wheel = []
        args.remote_wheel = []
        args.always_include_sdist = False
        args.default_build_dependencies = []
        args.disallow_builds = False
        args.default_alias_single_version = False

        if annotations_data is not None:
            annotations_file = os.path.join(self.td_path, "annotations.json")
            with open(annotations_file, "w") as f:
                json.dump(annotations_data, f)
            args.annotations_file = annotations_file
        else:
            args.annotations_file = None

        return resolve(args)

    def test_wildcard_always_build_end_to_end(self):
        """Wildcard always_build forces all packages to use sdist."""
        pkg_foo = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("foo-1.0.tar.gz"),
            ],
        )
        pins = {
            canonicalize_name("foo"): PackageKey.from_parts("foo", Version("1.0")),
        }

        resolved = self._resolve_with_annotations([pkg_foo], pins, {"*": {"always_build": True}})

        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        # With always_build, sdist should be present
        self.assertIsNotNone(resolved.packages[foo_key].sdist_file)
        self.assertEqual(resolved.packages[foo_key].sdist_file.key.name, "foo-1.0.tar.gz")

    def test_wildcard_with_specific_override_end_to_end(self):
        """Specific override replaces wildcard: foo gets always_build=False despite wildcard."""
        pkg_foo = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("foo-1.0.tar.gz"),
            ],
        )
        pkg_bar = make_pkg(
            "bar",
            "2.0",
            [
                make_file("bar-2.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("bar-2.0.tar.gz"),
            ],
        )
        pins = {
            canonicalize_name("foo"): PackageKey.from_parts("foo", Version("1.0")),
            canonicalize_name("bar"): PackageKey.from_parts("bar", Version("2.0")),
        }

        resolved = self._resolve_with_annotations(
            [pkg_foo, pkg_bar],
            pins,
            {
                "*": {"always_build": True},
                "foo": {"always_build": False},
            },
        )

        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        bar_key = PackageKey.from_parts("bar", Version("2.0"))

        # foo: specific override (always_build=False), should have wheel candidates
        foo_whl_names = {c.filename for c in resolved.packages[foo_key].wheel_candidates}
        self.assertIn("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl", foo_whl_names)

        # bar: wildcard (always_build=True), should have sdist
        self.assertIsNotNone(resolved.packages[bar_key].sdist_file)
        self.assertEqual(resolved.packages[bar_key].sdist_file.key.name, "bar-2.0.tar.gz")

    def test_unconsumed_wildcard_annotations_no_error(self):
        """Packages in lock model but not in pins should not cause errors when wildcard is used."""
        pkg_foo = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        pkg_unused = make_pkg("unused", "1.0", [make_file("unused-1.0.tar.gz")])

        # Only foo is pinned; unused is in the lock model but not transitively depended on
        pins = {
            canonicalize_name("foo"): PackageKey.from_parts("foo", Version("1.0")),
        }

        # This should NOT raise, even though unused gets a wildcard annotation
        resolved = self._resolve_with_annotations(
            [pkg_foo, pkg_unused],
            pins,
            {"*": {"always_build": True}},
        )

        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        self.assertIn(foo_key, resolved.packages)

    def test_unconsumed_specific_annotation_still_errors(self):
        """A specific annotation for a package not in the locked set still raises."""
        pkg_foo = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        pkg_unused = make_pkg("unused", "1.0", [make_file("unused-1.0.tar.gz")])

        pins = {
            canonicalize_name("foo"): PackageKey.from_parts("foo", Version("1.0")),
        }

        with self.assertRaisesRegex(Exception, "not part of the locked set"):
            self._resolve_with_annotations(
                [pkg_foo, pkg_unused],
                pins,
                {"unused": {"always_build": True}},
            )

    def test_build_repo_flows_to_resolved_package(self):
        """build_repo annotation makes it into the resolved package JSON."""
        pkg_foo = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        pins = {
            canonicalize_name("foo"): PackageKey.from_parts("foo", Version("1.0")),
        }

        resolved = self._resolve_with_annotations([pkg_foo], pins, {"foo": {"build_repo": "build_deps"}})

        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        self.assertEqual(resolved.packages[foo_key].build_repo, "build_deps")

    def test_wildcard_build_repo_flows_to_resolved_package(self):
        """Wildcard build_repo applies to all resolved packages."""
        pkg_foo = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        pkg_bar = make_pkg("bar", "2.0", [make_file("bar-2.0.tar.gz")])
        pins = {
            canonicalize_name("foo"): PackageKey.from_parts("foo", Version("1.0")),
            canonicalize_name("bar"): PackageKey.from_parts("bar", Version("2.0")),
        }

        resolved = self._resolve_with_annotations([pkg_foo, pkg_bar], pins, {"*": {"build_repo": "shared_build"}})

        for pkg in resolved.packages.values():
            self.assertEqual(pkg.build_repo, "shared_build")

    def test_wildcard_install_exclude_globs_end_to_end(self):
        """Wildcard install_exclude_globs propagate to resolved packages."""
        pkg_foo = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        pins = {
            canonicalize_name("foo"): PackageKey.from_parts("foo", Version("1.0")),
        }

        resolved = self._resolve_with_annotations(
            [pkg_foo], pins, {"*": {"install_exclude_globs": ["*.pyc", "__pycache__/**"]}}
        )

        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        self.assertIn("*.pyc", resolved.packages[foo_key].install_exclude_globs)
        self.assertIn("__pycache__/**", resolved.packages[foo_key].install_exclude_globs)

    def test_wildcard_replace_semantics_exclude_globs_end_to_end(self):
        """Specific package's exclude_globs fully replaces wildcard, not union."""
        pkg_foo = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        pkg_bar = make_pkg("bar", "2.0", [make_file("bar-2.0.tar.gz")])
        pins = {
            canonicalize_name("foo"): PackageKey.from_parts("foo", Version("1.0")),
            canonicalize_name("bar"): PackageKey.from_parts("bar", Version("2.0")),
        }

        resolved = self._resolve_with_annotations(
            [pkg_foo, pkg_bar],
            pins,
            {
                "*": {"install_exclude_globs": ["*.pyc"]},
                "foo": {"install_exclude_globs": ["tests/**"]},
            },
        )

        foo_key = PackageKey.from_parts("foo", Version("1.0"))
        bar_key = PackageKey.from_parts("bar", Version("2.0"))

        # foo: specific replaces wildcard entirely
        self.assertIn("tests/**", resolved.packages[foo_key].install_exclude_globs)
        self.assertNotIn("*.pyc", resolved.packages[foo_key].install_exclude_globs)

        # bar: wildcard applies
        self.assertIn("*.pyc", resolved.packages[bar_key].install_exclude_globs)


if __name__ == "__main__":
    unittest.main()
