import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace

from private.tools import rust_common


def _make_fake_rustc(path: Path) -> Path:
    path.write_text(
        f'#!/bin/sh\nexec "{sys.executable}" -c '
        '\'import json, sys; print("rustc 1.85.0 (test)") if sys.argv[1:] == ["--version"] '
        'else print(json.dumps(sys.argv[1:]))\' "$@"\n'
    )
    path.chmod(0o755)
    return path


class RustCommonTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.orig_cwd = Path.cwd()
        self.sdist_dir = self.root / "sdist"
        self.sdist_dir.mkdir()
        self.temp_build = self.root / "tmp"
        self.temp_build.mkdir()
        self.fake_rustc = _make_fake_rustc(self.root / "fake_rustc")
        self.host_rustlib = self.root / "custom_host_tc" / "lib" / "rustlib" / "x86_64-unknown-linux-gnu" / "lib"
        self.target_rustlib = self.root / "custom_target_tc" / "lib" / "rustlib" / "aarch64-unknown-linux-gnu" / "lib"
        self.host_rustlib.mkdir(parents=True)
        self.target_rustlib.mkdir(parents=True)
        (self.host_rustlib / "libstd.rlib").write_text("host")
        (self.target_rustlib / "libstd.rlib").write_text("target")

    def tearDown(self):
        os.chdir(self.orig_cwd)
        self.temp_dir.cleanup()

    def _make_ctx(self, *, extra_files=None, build_env=None, is_cross=True):
        target_triple = "aarch64-unknown-linux-gnu" if is_cross else "x86_64-unknown-linux-gnu"
        target_rustlib = self.target_rustlib if is_cross else self.host_rustlib
        rust_layer_json = self.root / "rust_layer.json"
        rust_layer_json.write_text(
            json.dumps(
                {
                    "rustc": str(self.fake_rustc.relative_to(self.root)),
                    "cargo": str(self.fake_rustc.relative_to(self.root)),
                    "sysroot": "custom_target_tc",
                    "host_triple": "x86_64-unknown-linux-gnu",
                    "target_triple": target_triple,
                    "host_rustlib_dir": str(self.host_rustlib.relative_to(self.root)),
                    "target_rustlib_dir": str(target_rustlib.relative_to(self.root)),
                }
            )
        )
        return SimpleNamespace(
            prefix=self.root,
            temp_dir=self.temp_build,
            sdist_dir=self.sdist_dir,
            exec_python=Path(sys.executable),
            target_python=Path(sys.executable),
            _layers=None,
            sysconfig_vars={
                "VERSION": "3.12",
                "CC": "/usr/bin/cc",
                "CXX": "/usr/bin/c++",
                "LDFLAGS": "-L/layer/lib -Wl,-rpath,$ORIGIN",
            },
            build_env=dict(build_env or {}),
            bazel_config={
                "layers": [str(rust_layer_json.relative_to(self.root))],
                "extra_files": dict(extra_files or {}),
            },
        )

    def test_preserves_user_rustflags_and_symlinks_rustlib_dirs(self):
        os.chdir(self.sdist_dir)
        ctx = self._make_ctx(
            build_env={
                "RUSTFLAGS": "-C target-feature=+crt-static",
                "CARGO_ENCODED_RUSTFLAGS": "-C\x1ftarget-cpu=generic",
                "ARFLAGS": "rcsD",
            }
        )
        rust_common.configure_rust_env(ctx, Path("."), is_maturin=True)

        self.assertEqual(ctx.build_env["RUSTFLAGS"], "-C target-feature=+crt-static")
        self.assertEqual(ctx.build_env["CARGO_ENCODED_RUSTFLAGS"], "-C\x1ftarget-cpu=generic")
        self.assertNotIn("ARFLAGS", ctx.build_env)

        host_dst = self.temp_build / "sysroot" / "lib" / "rustlib" / "x86_64-unknown-linux-gnu" / "lib"
        target_dst = self.temp_build / "sysroot" / "lib" / "rustlib" / "aarch64-unknown-linux-gnu" / "lib"
        self.assertEqual(host_dst.resolve(), self.host_rustlib.resolve())
        self.assertEqual(target_dst.resolve(), self.target_rustlib.resolve())

    def test_user_injected_cargo_lock_overwrites_existing_subdir_lock(self):
        os.chdir(self.sdist_dir)
        (self.sdist_dir / "Cargo.lock").write_text("user lock")
        subdir = self.sdist_dir / "rust"
        subdir.mkdir()
        (subdir / "Cargo.lock").write_text("stale sdist lock")

        ctx = self._make_ctx(extra_files={"Cargo.lock": "override/Cargo.lock"})
        rust_common.configure_rust_env(ctx, Path("rust"), is_maturin=True)

        self.assertEqual((subdir / "Cargo.lock").read_text(), "user lock")
        self.assertFalse((self.sdist_dir / "Cargo.lock").exists())

    def test_workspace_root_cargo_lock_preserved_and_pyo3_detected(self):
        os.chdir(self.sdist_dir)
        (self.sdist_dir / "Cargo.toml").write_text('[workspace]\nmembers = ["crates/py"]\n')
        (self.sdist_dir / "Cargo.lock").write_text('[[package]]\nname = "pyo3"\nversion = "0.22.0"\n')
        subdir = self.sdist_dir / "crates" / "py"
        subdir.mkdir(parents=True)
        (subdir / "Cargo.toml").write_text('[package]\nname = "py"\nversion = "0.1.0"\n')

        # Sdist-shipped workspace lock stays at workspace root and is still found by get_pyo3_version.
        ctx = self._make_ctx(extra_files={})
        rust_common.configure_rust_env(ctx, Path("crates/py"), is_maturin=True)
        self.assertTrue((self.sdist_dir / "Cargo.lock").exists())
        self.assertFalse((subdir / "Cargo.lock").exists())
        self.assertEqual(rust_common.get_pyo3_version(Path("crates/py")), "0.22.0")

        # User-injected lock on a workspace root also stays at workspace root.
        ctx2 = self._make_ctx(extra_files={"Cargo.lock": "override/Cargo.lock"})
        rust_common.configure_rust_env(ctx2, Path("crates/py"), is_maturin=True)
        self.assertTrue((self.sdist_dir / "Cargo.lock").exists())
        self.assertFalse((subdir / "Cargo.lock").exists())

    def test_rustc_wrapper_probes_exact_target_and_metadata_hash(self):
        os.chdir(self.sdist_dir)
        ctx = self._make_ctx(is_cross=True)
        rust_common.configure_rust_env(ctx, Path("."), is_maturin=True)
        wrapper = self.temp_build / "rustc_wrapper"

        def run_wrapper(args, env_extra=None):
            env = dict(os.environ)
            if env_extra:
                env.update(env_extra)
            out = subprocess.check_output([str(wrapper), str(self.fake_rustc)] + args, env=env, text=True)
            return json.loads(out)

        # Probes (-vV, -Vv, --print=...) must not receive link-arg or codegen-units=1.
        for probe in (["-vV"], ["-Vv"], ["--print=file-names", "--target", "aarch64-unknown-linux-gnu"]):
            probe_args = run_wrapper(probe)
            self.assertNotIn("codegen-units=1", probe_args)
            self.assertFalse(any(a.startswith("link-arg=") for a in probe_args))

        # -v is --verbose (normal compile flag), NOT a version probe.
        verbose_compile = run_wrapper(
            [
                "-v",
                "--crate-name",
                "demo",
                "--target=aarch64-unknown-linux-gnu",
                "-Cmetadata=orig",
            ]
        )
        self.assertIn("codegen-units=1", verbose_compile)
        self.assertIn("link-arg=-L/layer/lib", verbose_compile)
        self.assertFalse(any(a == "-Cmetadata=orig" for a in verbose_compile))

        # Host build script whose path merely mentions target_triple must NOT be treated as target.
        host_args = run_wrapper(
            [
                "--crate-name",
                "build_script_build",
                "--out-dir",
                "/tmp/aarch64-unknown-linux-gnu/build",
                "-C",
                "metadata=orig",
            ],
            {"CARGO_PKG_NAME": "pkg_a", "CARGO_PKG_VERSION": "1.0.0"},
        )
        host_args_b = run_wrapper(
            [
                "--crate-name",
                "build_script_build",
                "--out-dir",
                "/tmp/aarch64-unknown-linux-gnu/build",
                "-C",
                "metadata=orig",
            ],
            {"CARGO_PKG_NAME": "pkg_b", "CARGO_PKG_VERSION": "1.0.0"},
        )
        self.assertNotIn("codegen-units=1", host_args)
        self.assertFalse(any(a.startswith("link-arg=") for a in host_args))

        # Target compile receives link-arg and codegen-units=1, and distinct
        # CARGO_PKG_VERSION / --edition / CARGO_PKG_NAME produce distinct metadata hashes.
        base_cmd = [
            "--crate-name",
            "syn",
            "--crate-type",
            "lib",
            "--target",
            "aarch64-unknown-linux-gnu",
            "-C",
            "metadata=orig",
        ]
        v1_args = run_wrapper(base_cmd + ["--edition=2018"], {"CARGO_PKG_VERSION": "1.0.109"})
        v2_args = run_wrapper(base_cmd + ["--edition=2018"], {"CARGO_PKG_VERSION": "2.0.90"})
        ed2021_args = run_wrapper(base_cmd + ["--edition=2021"], {"CARGO_PKG_VERSION": "2.0.90"})

        self.assertIn("codegen-units=1", v1_args)
        self.assertIn("link-arg=-L/layer/lib", v1_args)

        def get_metadata(argv):
            for idx, tok in enumerate(argv):
                if tok == "-C" and idx + 1 < len(argv) and argv[idx + 1].startswith("metadata="):
                    return argv[idx + 1]
            return None

        m1 = get_metadata(v1_args)
        m2 = get_metadata(v2_args)
        m3 = get_metadata(ed2021_args)
        self.assertIsNotNone(m1)
        self.assertNotEqual(m1, "metadata=orig")
        self.assertNotEqual(m1, m2)
        self.assertNotEqual(m2, m3)
        self.assertNotEqual(get_metadata(host_args), get_metadata(host_args_b))


if __name__ == "__main__":
    unittest.main()
