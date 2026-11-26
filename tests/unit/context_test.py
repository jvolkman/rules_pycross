import json
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch

from pycross.private.build.tools.utils import context


class BuildContextTest(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.prefix = Path(self.tmp.name)
        self.config_path = self.prefix / "config.json"

    def _load(
        self,
        platform,
        sdist_root,
        source_dir=None,
        build_env=None,
        launcher_pythonpath=None,
        config_settings=None,
        extra_environ=None,
    ):
        cfg = {
            "sdist": "pkg.tar.gz",
            "exec_python": "python",
            "target_python": "python",
            "wheel_dir": "wheels",
            "source_dir": source_dir,
            "build_env": build_env or {},
        }
        if config_settings is not None:
            cfg["config_settings"] = config_settings
        self.config_path.write_text(json.dumps(cfg))
        env = {"PYCROSS_BUILD_ROOT": "scratch", "PYCROSS_SDIST_DIR": str(sdist_root)}
        if extra_environ:
            env.update(extra_environ)
        if launcher_pythonpath is not None:
            env["PYTHONPATH"] = launcher_pythonpath
        # Simulate the requested OS while keeping this host's Path type.
        platform_os = SimpleNamespace(
            name=platform, environ=env, path=os.path, pathsep=";" if platform == "nt" else ":"
        )
        with patch.object(context, "os", platform_os), patch.object(context.Path, "cwd", return_value=self.prefix):
            return context.load_build_context(str(self.config_path))

    def test_windows_root_is_short_stable_and_inside_execroot(self):
        original = "bazel-out/" + "long-package-name/" * 30 + "sdist"
        first = self._load("nt", original)
        second = self._load("nt", original)

        self.assertEqual(first.sdist_root_dir, second.sdist_root_dir)
        self.assertEqual(first.sdist_root_dir.parent, self.prefix / "bazel-out" / "_pcr")
        self.assertRegex(first.sdist_root_dir.name, r"^[0-9a-f]{16}$")
        self.assertLess(len(str(first.sdist_root_dir.relative_to(self.prefix))), 64)
        self.assertEqual(first.sdist_dir, first.sdist_root_dir)
        self.assertEqual(first.temp_dir, self.prefix / "scratch")
        self.assertEqual(first.wheel_dir, self.prefix / "wheels")
        self.assertEqual(first.build_env["PYCROSS_SDIST_DIR"], str(first.sdist_root_dir))
        self.assertEqual(first.build_env["PYCROSS_BUILD_ROOT"], str(first.temp_dir))

    def test_windows_pythonpath_remaps_only_sdist_entries(self):
        original = "bazel-out/config-a/bin/pkg/target/sdist"
        relative_variant = "BAZEL-OUT\\CONFIG-A\\BIN\\PKG\\TARGET\\SDIST\\Project\\src"
        absolute_variant = (
            str(self.prefix).replace("/", "\\").upper() + "\\" + original.upper().replace("/", "\\") + "\\generated"
        )
        build_env = {
            "PYTHONPATH": ";".join(
                [
                    relative_variant,
                    absolute_variant,
                    "C:\\external\\dependency",
                    "Z:\\external\\dependency",
                    original + "-other",
                    "old-sdist-other",
                ],
            ),
        }
        launcher_pythonpath = original + ";C:\\launcher\\path"

        ctx = self._load("nt", original, build_env=build_env, launcher_pythonpath=launcher_pythonpath)
        entries = ctx.build_env["PYTHONPATH"].split(";")

        self.assertEqual(entries[0], str(ctx.sdist_root_dir / "Project" / "src"))
        self.assertEqual(entries[1], str(ctx.sdist_root_dir / "generated"))
        self.assertEqual(
            entries[2:],
            ["C:\\external\\dependency", "Z:\\external\\dependency", original + "-other", "old-sdist-other"],
        )
        self.assertNotIn("C:\\launcher\\path", ctx.build_env["PYTHONPATH"])

    def test_windows_reserved_paths_override_user_environment_values(self):
        ctx = self._load(
            "nt",
            "bazel-out/config-a/bin/pkg/target/sdist",
            build_env={"PYCROSS_SDIST_DIR": "wrong-sdist", "PYCROSS_BUILD_ROOT": "wrong-temp"},
        )
        self.assertEqual(ctx.build_env["PYCROSS_SDIST_DIR"], str(ctx.sdist_root_dir))
        self.assertEqual(ctx.build_env["PYCROSS_BUILD_ROOT"], str(ctx.temp_dir))

    def test_windows_does_not_restore_launcher_pythonpath(self):
        original = "bazel-out/config-a/bin/pkg/target/sdist"
        ctx = self._load("nt", original, launcher_pythonpath=original + ";C:\\launcher\\path")
        self.assertNotIn("PYTHONPATH", ctx.build_env)

    def test_windows_environment_names_are_case_insensitive(self):
        original = "bazel-out/config-a/bin/pkg/target/sdist"
        for key in ["pythonpath", "PythonPath"]:
            with self.subTest(key=key):
                ctx = self._load(
                    "nt",
                    original,
                    build_env={
                        key: original + "/src",
                        "pycross_sdist_dir": "old-source",
                        "pycross_build_root": "old-scratch",
                    },
                )
                self.assertEqual(ctx.build_env["PYTHONPATH"], str(ctx.sdist_root_dir / "src"))
                self.assertEqual(ctx.build_env["PYCROSS_SDIST_DIR"], str(ctx.sdist_root_dir))
                self.assertEqual(ctx.build_env["PYCROSS_BUILD_ROOT"], str(ctx.temp_dir))
                self.assertNotIn(key, ctx.build_env)
                self.assertNotIn("pycross_sdist_dir", ctx.build_env)
                self.assertNotIn("pycross_build_root", ctx.build_env)

    def test_windows_relative_pythonpath_matches_absolute_configured_root(self):
        original = str(self.prefix).replace("/", "\\") + "\\bazel-out\\config-a\\bin\\pkg\\target\\sdist"
        relative_variant = "BAZEL-OUT/CONFIG-A/BIN/PKG/TARGET/SDIST/Project/src"

        ctx = self._load("nt", original, build_env={"PYTHONPATH": relative_variant})

        self.assertEqual(ctx.build_env["PYTHONPATH"], str(ctx.sdist_root_dir / "Project" / "src"))

    def test_windows_roots_distinguish_build_configurations(self):
        original = "bazel-out/config-a/bin/pkg/target/sdist"
        different_configuration = "bazel-out/config-b/bin/pkg/target/sdist"
        different_target = "bazel-out/config-a/bin/pkg/other-target/sdist"

        first = self._load("nt", original)
        config_variant = self._load("nt", different_configuration)
        target_variant = self._load("nt", different_target)

        self.assertNotEqual(first.sdist_root_dir, config_variant.sdist_root_dir)
        self.assertNotEqual(first.sdist_root_dir, target_variant.sdist_root_dir)

    def test_source_dir_is_relative_to_selected_root(self):
        for platform in ["nt", "posix"]:
            with self.subTest(platform=platform):
                ctx = self._load(platform, "bazel-out/pkg/sdist", source_dir="project/src")
                self.assertEqual(ctx.sdist_dir, ctx.sdist_root_dir / "project" / "src")

    def test_non_windows_preserves_configured_root(self):
        for original in [Path("bazel-out/pkg/sdist"), self.prefix / "absolute-sdist"]:
            with self.subTest(original=original):
                pythonpath = str(original) + ":/external/dependency"
                ctx = self._load("posix", original, build_env={"PYTHONPATH": pythonpath, "pythonpath": "keep-case"})
                self.assertEqual(ctx.sdist_root_dir, (self.prefix / original).absolute())
                self.assertEqual(ctx.sdist_dir, ctx.sdist_root_dir)
                self.assertEqual(ctx.build_env["PYCROSS_SDIST_DIR"], str(original))
                self.assertEqual(ctx.build_env["PYCROSS_BUILD_ROOT"], "scratch")
                self.assertEqual(ctx.build_env["PYTHONPATH"], pythonpath)
                self.assertEqual(ctx.build_env["pythonpath"], "keep-case")

    def test_inline_config_settings_replaces_placeholders(self):
        ctx = self._load(
            "posix",
            "bazel-out/pkg/sdist",
            config_settings={
                "--flag": ["$$EXT_BUILD_ROOT$$/path/to/file", "plain"],
                "--single": "$$EXT_BUILD_ROOT$$/other",
            },
        )
        self.assertEqual(
            ctx.config_settings,
            {
                "--flag": [f"{self.prefix}/path/to/file", "plain"],
                "--single": f"{self.prefix}/other",
            },
        )

    def test_user_build_env_overrides_inherited_programmatic_env(self):
        ctx = self._load(
            "posix",
            "bazel-out/pkg/sdist",
            extra_environ={"MAKEFLAGS": "-j6", "CARGO_VENDORED_SOURCES": "vendor"},
            build_env={"MAKEFLAGS": "-j2"},
        )
        self.assertEqual(ctx.build_env["MAKEFLAGS"], "-j2")
        self.assertEqual(ctx.build_env["CARGO_VENDORED_SOURCES"], "vendor")


if __name__ == "__main__":
    unittest.main()
