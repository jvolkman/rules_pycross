import unittest
from typing import Dict
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
from pycross.private.tools.target_environment import TargetEnv


def make_env(name: str, platforms: List[str], version: str = "3.10", markers: Dict[str, str] = None) -> TargetEnv:
    from pip._internal.models.target_python import TargetPython

    version_info = tuple(int(p) for p in version.split(".")[:3])
    if len(version_info) == 2:
        version_info = version_info + (0,)
    tp = TargetPython(
        platforms=platforms,
        py_version_info=version_info,
        abis=[f"cp{version.replace('.', '')}"],
        implementation="cp",
    )
    compatibility_tags = [str(t) for t in tp.get_sorted_tags()]

    return TargetEnv(
        name=name,
        implementation="cp",
        version=version,
        abis=[f"cp{version.replace('.', '')}"],
        platforms=platforms,
        compatibility_tags=compatibility_tags,
        markers=markers or {},
        python_compatible_with=[],
        flag_values={},
    )


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
    def setUp(self):
        self.linux_env = make_env(
            "linux", ["manylinux_2_17_x86_64", "manylinux2014_x86_64"], markers={"sys_platform": "linux"}
        )
        self.mac_env = make_env("mac", ["macosx_10_9_x86_64"], markers={"sys_platform": "darwin"})

    # Core Resolution
    def test_single_package_single_env(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")])
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].key.name, "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")

    def test_single_package_no_matching_wheel_fallback_sdist(self):
        pkg = make_pkg(
            "foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"), make_file("foo-1.0.tar.gz")]
        )
        ctx = GenerationContext(
            target_environments=[self.mac_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("mac", resolved.environment_files)
        self.assertEqual(resolved.environment_files["mac"].key.name, "foo-1.0.tar.gz")
        self.assertTrue(resolver.uses_sdist)
        self.assertIsNotNone(resolved.sdist_file)

    def test_wheel_selection_priority(self):
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-manylinux2014_x86_64.whl"),
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
            ],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].key.name, "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")

    def test_wheel_selection_build_tag_tie_breaker(self):
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
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(
            resolved.environment_files["linux"].key.name, "foo-1.0-2-cp310-cp310-manylinux_2_17_x86_64.whl"
        )

    def test_wheel_preferred_over_sdist(self):
        """When both a compatible wheel and sdist exist, the wheel is selected."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("foo-1.0.tar.gz"),
            ],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].key.name, "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")
        self.assertFalse(resolver.uses_sdist)

    def test_incompatible_wheel_skipped(self):
        """A wheel for a different platform is skipped; sdist is used instead."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl"),
                make_file("foo-1.0.tar.gz"),
            ],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].key.name, "foo-1.0.tar.gz")
        self.assertTrue(resolver.uses_sdist)

    def test_source_only_forces_sdist(self):
        """With always_build annotation, sdist is selected even when a compatible wheel exists."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("foo-1.0.tar.gz"),
            ],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        annotations = PackageAnnotations(always_build=True)
        resolver = PackageResolver(pkg, ctx, annotations, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].key.name, "foo-1.0.tar.gz")
        self.assertTrue(resolver.uses_sdist)

    def test_no_matching_files_no_env_entry(self):
        """When no wheel matches and no sdist exists, the environment gets no entry."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl")],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertNotIn("linux", resolved.environment_files)

    def test_pure_python_wheel_matches_any_env(self):
        """A py3-none-any wheel is compatible with any environment."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0-py3-none-any.whl")],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env, self.mac_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].key.name, "foo-1.0-py3-none-any.whl")
        self.assertIn("mac", resolved.environment_files)
        self.assertEqual(resolved.environment_files["mac"].key.name, "foo-1.0-py3-none-any.whl")

    def test_multi_env_resolution(self):
        pkg = make_pkg(
            "foo",
            "1.0",
            [
                make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                make_file("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl"),
            ],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env, self.mac_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].key.name, "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")
        self.assertIn("mac", resolved.environment_files)
        self.assertEqual(resolved.environment_files["mac"].key.name, "foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl")

    def test_common_vs_env_specific_deps(self):
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[make_dep("depA", "1.0"), make_dep("depB", "1.0", marker="sys_platform == 'linux'")],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env, self.mac_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.common_dependencies), 1)
        self.assertEqual(resolved.common_dependencies[0].name, "depa")

        self.assertIn("linux", resolved.environment_dependencies)
        self.assertEqual(len(resolved.environment_dependencies["linux"]), 1)
        self.assertEqual(resolved.environment_dependencies["linux"][0].name, "depb")

        self.assertNotIn("mac", resolved.environment_dependencies)

    # Dependency Handling
    def test_marker_evaluation(self):
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[make_dep("depA", "1.0", marker="sys_platform == 'linux'")],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env, self.mac_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.common_dependencies), 0)
        self.assertIn("linux", resolved.environment_dependencies)
        self.assertEqual(len(resolved.environment_dependencies["linux"]), 1)
        self.assertNotIn("mac", resolved.environment_dependencies)

    def test_ignore_dependencies(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")], deps=[make_dep("depA", "1.0")])
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        annotations = PackageAnnotations(ignore_dependencies={"depa"})
        resolver = PackageResolver(pkg, ctx, annotations, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.common_dependencies), 0)
        self.assertEqual(len(resolved.environment_dependencies), 0)

    def test_multi_version_dep_resolution(self):
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
            target_environments=[self.linux_env, self.mac_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.common_dependencies), 0)
        self.assertEqual(resolved.environment_dependencies["linux"][0].version, Version("1.0"))
        self.assertEqual(resolved.environment_dependencies["mac"][0].version, Version("2.0"))

    def test_build_dependencies(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        ctx = GenerationContext(
            target_environments=[self.linux_env],
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
            target_environments=[self.linux_env],
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
            target_environments=[self.linux_env],
            local_wheels={"foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl": "@//path:wheel"},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].label, "@//path:wheel")
        self.assertIsNone(resolved.environment_files["linux"].key)

    def test_remote_wheel_override(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")])
        remote_wheel = PackageFile(
            name="foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl",
            sha256="remote_sha",
            urls=("https://remote.com/foo.whl",),
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={"foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl": remote_wheel},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].key.hash_prefix, "remote_s")

    def test_always_include_sdist(self):
        pkg = make_pkg(
            "foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"), make_file("foo-1.0.tar.gz")]
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=True,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].key.name, "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")
        self.assertIsNotNone(resolved.sdist_file)
        self.assertEqual(resolved.sdist_file.key.name, "foo-1.0.tar.gz")

    def test_always_build_annotation(self):
        pkg = make_pkg(
            "foo", "1.0", [make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"), make_file("foo-1.0.tar.gz")]
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        annotations = PackageAnnotations(always_build=True)
        resolver = PackageResolver(pkg, ctx, annotations, [])
        resolved = resolver.to_resolved_package()

        self.assertIn("linux", resolved.environment_files)
        self.assertEqual(resolved.environment_files["linux"].key.name, "foo-1.0.tar.gz")
        self.assertTrue(resolver.uses_sdist)
        self.assertIsNotNone(resolved.sdist_file)

    # Annotations
    def test_build_target_override(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")])
        ctx = GenerationContext(
            target_environments=[self.linux_env],
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
            target_environments=[self.linux_env],
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
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        annotations = PackageAnnotations(pre_build_patches=["@//:pre.patch"], post_install_patches=["@//:post.patch"])
        resolver = PackageResolver(pkg, ctx, annotations, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(resolved.pre_build_patches, ["@//:pre.patch"])
        self.assertEqual(resolved.post_install_patches, ["@//:post.patch"])

    # Edge Cases
    def test_python_version_incompatibility(self):
        pkg = make_pkg("foo", "1.0", [make_file("foo-1.0.tar.gz")], python_versions=">=3.12")
        ctx = GenerationContext(
            target_environments=[self.linux_env],  # 3.10
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        with self.assertRaisesRegex(Exception, "does not support Python version"):
            ctx.check_package_compatibility(pkg)


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

        env_file = os.path.join(self.td_path, "env.json")
        linux_env = make_env("linux", ["manylinux2014_x86_64"])
        with open(env_file, "w") as f:
            import json

            json.dump(linux_env.to_dict(), f)

        args = MagicMock()
        args.lock_model_file = lock_model_file
        args.target_environment = [(env_file, "@//env:linux")]
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
        args.target_environment = []
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
    def setUp(self):
        self.linux_env = make_env(
            "linux", ["manylinux_2_17_x86_64", "manylinux2014_x86_64"], markers={"sys_platform": "linux"}
        )
        self.mac_env = make_env("mac", ["macosx_10_9_x86_64"], markers={"sys_platform": "darwin"})

    def test_extras_basic(self):
        """Deps gated on extra == 'test' appear when resolving for that extra."""
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
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        # Both deps should appear
        self.assertEqual(len(resolved.common_dependencies), 2)
        dep_names = {k.name.package for k in resolved.common_dependencies}
        self.assertIn("depa", dep_names)
        self.assertIn("depb", dep_names)

    def test_extras_with_env_markers(self):
        """A dep with both extra and platform markers is env-specific within the extra."""
        pkg = make_pkg(
            "foo[test]",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[
                make_dep("depC", "1.0", marker="extra == 'test' and sys_platform == 'linux'"),
            ],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env, self.mac_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        # No base deps
        self.assertEqual(len(resolved.common_dependencies), 0)

        # It should appear under the linux env specifically
        self.assertIn("linux", resolved.environment_dependencies)
        linux_names = {k.name.package for k in resolved.environment_dependencies["linux"]}
        self.assertIn("depc", linux_names)

        self.assertNotIn("mac", resolved.environment_dependencies)

    def test_extras_no_extras(self):
        """Packages without extra markers have no extras."""
        pkg = make_pkg(
            "foo",
            "1.0",
            [make_file("foo-1.0.tar.gz")],
            deps=[make_dep("depA", "1.0")],
        )
        ctx = GenerationContext(
            target_environments=[self.linux_env],
            local_wheels={},
            remote_wheels={},
            always_include_sdist=False,
        )
        resolver = PackageResolver(pkg, ctx, None, [])
        resolved = resolver.to_resolved_package()

        self.assertEqual(len(resolved.common_dependencies), 1)

    def test_extras_multiple(self):
        """Multiple extras ('test', 'dev') each pull different deps."""
        deps = [
            make_dep("depA", "1.0"),
            make_dep("pytest", "7.0", marker="extra == 'test'"),
            make_dep("black", "22.0", marker="extra == 'dev'"),
        ]

        ctx = GenerationContext(
            target_environments=[self.linux_env],
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
        test_dep_names = {k.name.package for k in resolved_test.common_dependencies}
        self.assertIn("depa", test_dep_names)
        self.assertIn("pytest", test_dep_names)
        self.assertNotIn("black", test_dep_names)

        # Check "dev" extra has black
        dev_dep_names = {k.name.package for k in resolved_dev.common_dependencies}
        self.assertIn("depa", dev_dep_names)
        self.assertIn("black", dev_dep_names)
        self.assertNotIn("pytest", dev_dep_names)


class TestCycleDetection(unittest.TestCase):
    """Tests for Tarjan's SCC-based cycle detection in resolve()."""

    def setUp(self):
        import tempfile

        self.td = tempfile.TemporaryDirectory()
        self.td_path = self.td.name

        self.linux_env = make_env(
            "linux", ["manylinux_2_17_x86_64", "manylinux2014_x86_64"], markers={"sys_platform": "linux"}
        )

    def tearDown(self):
        self.td.cleanup()

    def _resolve_with_packages(self, packages, pins):
        """Helper to set up files and call resolve() with the given packages and pins."""
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

        env_file = os.path.join(self.td_path, "env.json")
        with open(env_file, "w") as f:
            json.dump(self.linux_env.to_dict(), f)

        args = MagicMock()
        args.lock_model_file = lock_model_file
        args.target_environment = [(env_file, "@//env:linux")]
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

        self.linux_env = make_env(
            "linux", ["manylinux_2_17_x86_64", "manylinux2014_x86_64"], markers={"sys_platform": "linux"}
        )

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

        env_file = os.path.join(self.td_path, "env.json")
        with open(env_file, "w") as f:
            json.dump(self.linux_env.to_dict(), f)

        args = MagicMock()
        args.lock_model_file = lock_model_file
        args.target_environment = [(env_file, "@//env:linux")]
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
        # Should use the sdist, not the wheel
        self.assertEqual(resolved.packages[foo_key].environment_files["linux"].key.name, "foo-1.0.tar.gz")

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

        # foo: specific override, should use wheel
        self.assertEqual(
            resolved.packages[foo_key].environment_files["linux"].key.name,
            "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl",
        )
        # bar: wildcard, should use sdist
        self.assertEqual(resolved.packages[bar_key].environment_files["linux"].key.name, "bar-2.0.tar.gz")

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
