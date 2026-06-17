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
        self.assertEqual(resolved.environment_files["linux"].key.name, "foo-1.0-2-cp310-cp310-manylinux_2_17_x86_64.whl")

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


if __name__ == "__main__":
    unittest.main()
