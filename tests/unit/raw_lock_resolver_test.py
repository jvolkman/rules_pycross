import unittest
from typing import Dict
from typing import List

from packaging.specifiers import SpecifierSet
from packaging.utils import canonicalize_name
from packaging.version import Version

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
    return TargetEnv(
        name=name,
        implementation="cp",
        version=version,
        abis=[f"cp{version.replace('.', '')}"],
        platforms=platforms,
        compatibility_tags=[],
        markers=markers or {},
        python_compatible_with=[],
        flag_values={},
    )


def make_file(name: str, sha256: str = "1234") -> PackageFile:
    return PackageFile(name=name, sha256=sha256)


def make_dep(name: str, version: str, marker: str = "") -> PackageDependency:
    return PackageDependency(name=canonicalize_name(name), version=Version(version), marker=marker)


def make_pkg(
    name: str,
    version: str,
    files: List[PackageFile],
    deps: List[PackageDependency] = None,
    python_versions: str = ">=3.8",
) -> RawPackage:
    return RawPackage(
        name=canonicalize_name(name),
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
        self.assertTrue(resolved.environment_files["linux"].key.name.endswith(".whl"))

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


if __name__ == "__main__":
    unittest.main()
