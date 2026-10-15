"""Interactive demo of the rules_pycross import index and cross-wheel native preloading.

Try running from `tests/e2e/namespace_pkgs`:

  # 1. Prebuilt index with stock py_binary (merges per-wheel index.json files):
  bazel run --config=index //:demo

  # 2. Verbose finder debug trace (shows index load time, merged dirs, and CDLL preloads):
  RULES_PYTHON_IMPORT_INDEX_DEBUG=1 bazel run --config=index //:demo

  # 3. Compare with scan mode (Python imports pass, but cross-wheel $ORIGIN RPATH fails):
  bazel run --config=scan //:demo

  # 4. Compare with plain sys.path (venvs_site_packages=no, index=off):
  bazel run //:demo --@rules_python//python/config_settings:venvs_site_packages=no
"""

import glob
import importlib
import importlib.metadata
import json
import os
import sys


def _short(path: str) -> str:
    parts = path.replace("\\", "/").split("/")
    if len(parts) > 4:
        return ".../" + "/".join(parts[-4:])
    return path


def _section(title: str) -> None:
    print(f"\n=== {title} ===")


def _try_step(label: str, fn) -> None:
    try:
        result = fn()
        print(f"  [PASS] {label}: {result}")
    except Exception as e:
        print(f"  [FAIL] {label}: {type(e).__name__}: {e}")


def main() -> None:
    _section("1. Venv & Finder Status")
    venv_sp = next(
        (p for p in sys.path if ".venv/" in p.replace("\\", "/") and p.endswith("site-packages")),
        None,
    )
    if venv_sp and os.path.isdir(venv_sp):
        entries = sorted(os.listdir(venv_sp))
        print(f"  venv site-packages: {_short(venv_sp)}")
        print(f"  entries in venv site-packages ({len(entries)}): {entries}")

    finder_mod = sys.modules.get("_bazel_import_index")
    idx = getattr(finder_mod, "_INDEX", None) if finder_mod else None
    meta_finders = [f"{getattr(f, '__module__', '')}.{getattr(f, '__name__', type(f).__name__)}" for f in sys.meta_path]
    print(f"  sys.meta_path: {meta_finders}")

    if idx is None:
        print("  import index active: False (plain PathFinder)")
    else:
        source = (
            "split-file hybrid (os.scandir + in-root .pycross-native*.json dotfiles)"
            if idx.indexed
            else "runtime os.scandir scan"
        )
        print(
            f"  import index active: True ({len(idx.roots)} wheel roots, "
            f"{len(idx.native_files)} native dotfiles, {len(idx.consumer_roots)} consumers)"
        )
        print(f"  index source: {source}")
        print("  cross-wheel ELF preload plan:")
        for pkg, libs in sorted(idx.preload.items()):
            formatted = [f"{_short(root)}/{rel}" for root, rel in libs]
            print(f"    {pkg} -> {formatted}")

    if idx is not None:
        for root, dotfile_path in sorted(idx.native_files.items()):
            if "rpathfixture" in root and os.path.isfile(dotfile_path):
                with open(dotfile_path, encoding="utf-8") as f:
                    rpath_meta = json.load(f).get("native", {})
                _section(f"2. In-Root Native Consumer Dotfile ({os.path.basename(dotfile_path)})")
                for so_path, meta in rpath_meta.items():
                    print(f"  {so_path}: {json.dumps(meta)}")

    _section("3. Live Import & Native Preload Checks")

    def check_rpath():
        import rpathfixture

        cublas_ver, cudnn_ver = rpathfixture.load_and_call()
        return f"eager DT_NEEDED cublas={cublas_ver}, lazy dlopen cudnn={cudnn_ver}"

    _try_step("Cross-wheel $ORIGIN RPATH (rpathfixture -> libuser.so)", check_rpath)

    def check_nvidia():
        loaded = []
        for comp in ("cublas", "cudnn", "nccl"):
            importlib.import_module(f"nvidia.fixture_{comp}")
            loaded.append(f"nvidia.fixture_{comp}")
        so_matches = [
            _short(m)
            for entry in sys.path
            for m in glob.glob(os.path.join(entry, "nvidia", "fixture_*", "lib", "lib*.so.*"))
        ]
        return f"imported {loaded}; sys.path glob found {len(so_matches)} .so files"

    _try_step("Split regular package (nvidia.*) + torch sys.path glob", check_nvidia)

    def check_plugin_and_first_party():
        import first_party_mod
        from azfixture import first_party_ns
        from azfixture.core.tracing.ext import fixture_span

        return (
            f"fixture_span.SPAN={fixture_span.SPAN}, "
            f"first_party_ns={first_party_ns.FIRST_PARTY_NS}, "
            f"first_party_mod={first_party_mod.FIRST_PARTY}"
        )

    _try_step(
        "Plugin under another wheel's package + first-party py_library in shared namespace",
        check_plugin_and_first_party,
    )

    def check_pth():
        import pthfixture_extramod

        return f"pthfixture_extramod.EXTRA={pthfixture_extramod.EXTRA}, _pthfixture_ran={getattr(sys, '_pthfixture_ran', False)}"

    _try_step("Wheel .pth path & import lines (pthfixture.pth)", check_pth)

    def check_real_pypi_namespaces():
        import warnings

        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            from backports import entry_points_selectable  # noqa: F401
            from backports import tarfile  # noqa: F401
            from google.cloud import pubsub  # noqa: F401
            from google.cloud import storage  # noqa: F401
            from zope import event  # noqa: F401
            from zope import interface  # noqa: F401

        return (
            f"google.cloud.{{storage,pubsub}}, zope.{{interface,event}}, "
            f"backports.{{tarfile,entry_points_selectable}} all imported "
            f"(storage={importlib.metadata.version('google-cloud-storage')})"
        )

    _try_step("Real PyPI PEP 420 & pkgutil namespaces", check_real_pypi_namespaces)


if __name__ == "__main__":
    main()
