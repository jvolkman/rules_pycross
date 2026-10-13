# Venv Import Index & Cross-Wheel Native Preloading

This document explains the **Import Index** (`--@rules_pycross//pycross/settings:venv_import_index`) architecture in `rules_pycross`, why it exists, how it resolves Python imports and cross-wheel `$ORIGIN` shared libraries (`DT_NEEDED` and `dlopen`) without symlinking wheel contents into `site-packages`, and how to try it out.

---

## 1. The Problem: Exposing 500+ Wheel `TreeArtifact`s to Python

In `rules_pycross`, each `pycross_wheel_library` target extracts a wheel (or builds an sdist into a wheel and extracts it) as a Bazel directory output (`TreeArtifact`) at `<wheel_target>/site-packages`.

Historically, there were two ways to expose those wheels to a `py_binary` or `py_test` at runtime, and each had fundamental drawbacks at scale:

![Wheel Import Resolution Strategies](images/import_index_layouts.svg)

### Why Plain `sys.path` (`venvs_site_packages=no`) Breaks or Slows Down
1. **$O(N_{\text{wheels}})$ `stat` storm on every import:** With 500 wheels on `sys.path`, importing a first-party module from `<runfiles>/<workspace>` (which sits *after* wheel imports on `sys.path`) or probing a missing module forces CPython's `PathFinder` to `stat()` all 500 wheel directories.
2. **Split regular packages fail (`nvidia.*`):** Wheels like `nvidia-cublas-cu12`, `nvidia-cudnn-cu12`, and `nvidia-nccl-cu12` each ship an empty `nvidia/__init__.py`. With separate `sys.path` entries, `import nvidia` binds to the first wheel on `sys.path` and makes `nvidia.cudnn` / `nvidia.nccl` unimportable (`ModuleNotFoundError`).
3. **Plugin subpackages under another wheel's regular package fail (`azure.*`):** `azure-core` ships `azure/core/tracing/ext/__init__.py` (a regular package), and `azure-core-tracing-opentelemetry` installs `azure/core/tracing/ext/opentelemetry_span` into that directory. Without merging `azure.core.tracing.ext.__path__` across both wheels, the plugin cannot be imported.
4. **Root `.pth` files in wheels are ignored:** Python's `site` module only processes `.pth` files in the venv's own `site-packages` directory, not in extra `sys.path` entries added later by `_bazel_site_init.py` (breaking packages like `rerun-sdk` that rely on `rerun_sdk.pth`).
5. **Cross-wheel `$ORIGIN` RPATHs fail:** An extension or shared library in Wheel A with `DT_RUNPATH: $ORIGIN/../nvidia/cudnn/lib` looks inside `wheel_A/site-packages/nvidia/cudnn/lib`, which does not exist because `libcudnn.so` is in `wheel_B/site-packages/nvidia/cudnn/lib`.

### Why Symlinked Venvs (`venvs_site_packages=yes`) Hit Analysis-Time Limits
1. **Requires repo-time `site_paths` guessing for sdists:** Because Bazel must declare venv symlinks during the **analysis phase** (before any build action runs), `rules_pycross` had to guess what top-level directories an sdist *will* produce before building it. Compiled CFFI/Cython modules generated at build time (e.g., `_nvx_utf8validator.abi3.so` in `autobahn`) or dynamically generated layouts cannot be known statically at repo time.
2. **Opaque `TreeArtifact`s cannot be merged at subpackage granularity during analysis:** When two `TreeArtifact` wheels both provide `nvidia/__init__.py` or `google/cloud/functions/__init__.py`, Bazel analysis cannot inspect the files inside the `TreeArtifact` directories to synthesize a merged directory tree of file symlinks.
3. **Directory symlinks break cross-wheel `$ORIGIN` RPATHs in `glibc`:** When `site-packages/pkg_a` is a directory symlink to `.../wheel_A/site-packages/pkg_a`, `glibc`'s dynamic linker (`ld.so`) resolves `realpath()` on `pkg_a/libuser.so` before expanding `$ORIGIN`, landing back inside `wheel_A`'s isolated `TreeArtifact` instead of the shared venv `site-packages`.

---

## 2. How the Import Index Works

The Import Index gives binaries the exact semantics of `pip` installing all wheels into a single merged `site-packages` directory **while keeping every wheel in its own isolated `TreeArtifact` on `sys.path` and creating zero wheel symlinks in `.venv`**:

```mermaid
flowchart LR
    subgraph Build["Build Time (Bazel Execution Phase)"]
        W1["PycrossWheelInstall (Wheel 1)"] -->|"writes"| I1["wheel_1.dist_info/index.json"]
        W2["PycrossWheelInstall (Wheel N)"] -->|"writes"| I2["wheel_N.dist_info/index.json"]
        I1 & I2 -->|"PyMakeVenvIndex"| M["_bazel_import_index.json"]
        I1 & I2 -->|"pycross_modules_mapping"| G["Gazelle modules_mapping.json"]
    end

    subgraph Runtime["Runtime (Python Startup)"]
        PTH["pycross_import_index.pth"] -->|"auto_install()"| PF["_bazel_import_index.PathFinder"]
        M -->|"1 openat() + _json.make_scanner"| PF
        PF -->|"pre -> wheels (O(1)) -> post"| IMP["ModuleSpec + __path__ merge + CDLL preload"]
    end
```

### Build-Time Pipeline
1. **Per-Wheel Index (`<name>.dist_info/index.json`):**
   At the end of every `PycrossWheelInstall` action (after `install_exclude_globs`, `post_install_patches`, and `.pyc` precompilation), [`wheel_index.py`](../pycross/private/tools/wheel_index.py) scans the installed `site-packages` directory and writes a deterministic `<name>.dist_info/index.json` recording:
   - `distribution`: `{"name", "version"}` from `METADATA`
   - `dist_info`: the `.dist-info` directory name
   - `top`: top-level importable module/package names $\rightarrow$ directory entry names
   - `dirs`: all package/subpackage relative directory paths
   - `modules`: leaf modules inside regular packages (for Gazelle)
   - `namespaces`: PEP 420 and `pkgutil`/`pkg_resources` namespace directories
   - `pth` / `pth_paths`: root `.pth` files and relative path entries they add
   - `native`: ELF metadata (`soname`, `needed`, `rpath`, `runpath`) for every `.so` file in the wheel (parsed via pure-Python [`elf_tools.py`](../pycross/private/tools/elf_tools.py))
2. **Exact Gazelle `modules_mapping.json`:**
   [`pycross_modules_mapping`](../pycross/private/modules_mapping.bzl) builds `modules_mapping.json` from the post-install per-wheel `index.json` files instead of repo-time `site_paths` heuristics.
3. **Binary Merged Index (`_bazel_import_index.json`):**
   [`venv_import_index_merger.py`](../pycross/private/tools/venv_import_index_merger.py) (`PyMakeVenvIndex`) merges the per-wheel `index.json` files (without staging the wheel `TreeArtifact`s!) into a single `_bazel_import_index.json`.

### Runtime Finder (`_bazel_import_index.PathFinder`)
At Python startup, `bazel.pth` runs `_bazel_site_init.py` (which populates `sys.path`), and immediately afterward `pycross_import_index.pth` runs `_bazel_import_index.auto_install()`, replacing `importlib.machinery.PathFinder` in `sys.meta_path` with [`_bazel_import_index.PathFinder`](../pycross/private/tools/import_index.py):

- **`pre` $\rightarrow$ `wheels` ($O(1)$) $\rightarrow$ `post` ordering:**
  `sys.path` is partitioned into `pre` (the Python stdlib and any earlier non-wheel paths), `wheels` (all wheel `site-packages` roots collapsed into one virtual merged directory), and `post` (`<runfiles>/<workspace_name>`, where first-party `py_library` sources live).
  - Because `pre` runs first, an `enum34`-style backport wheel can never shadow the stdlib.
  - Because `wheels` resolves in $O(1)$ from the index dict, importing any **first-party `py_library` module** from `post` skips $O(N_{\text{wheels}})$ `stat` calls and jumps straight to `<runfiles>/<workspace_name>`.
- **Multi-owner package & subpackage merging (`merged` & `sub`):**
  When multiple wheels own the same package directory (`nvidia`, `google.cloud`, `azure.core.tracing.ext`), the finder populates `__path__` with all owner directories in `sys.path` order and resolves single-owner subpackages (`sub`) in $O(1)$ without scanning parent directories.
- **First-party + wheel shared namespaces:**
  PEP 420 namespaces shared between first-party `py_library` targets and wheels accumulate portions across `pre`, `wheels`, and `post` (even if Bazel's `legacy_create_init` synthesizes an empty `__init__.py` in `<runfiles>/_main`).
- **$O(1)$ `importlib.metadata` with memoized `read_text()`:**
  Distribution lookups by name (`importlib.metadata.version("...")`) resolve in $O(1)$ from the index, and `PathDistribution.read_text()` is cached in memory for `METADATA`, `PKG-INFO`, and `entry_points.txt`.

---

## 3. Cross-Wheel Native Library (`$ORIGIN` RPATH) Preloading

Many native Python wheels (such as `tensorflow` + `nvidia-*-cu12`, or split C++/CUDA wheel families) compile shared libraries with relative RPATHs like `$ORIGIN/../nvidia/cudnn/lib` or `$ORIGIN/../../cublas/lib`, assuming all wheels are unpacked into one flat `site-packages` directory.

When each wheel lives in its own Bazel `TreeArtifact`, `$ORIGIN/../nvidia/cudnn/lib` resolves inside the *consuming* wheel's `TreeArtifact` and fails to find libraries in sibling wheels.

Instead of patching ELF binaries on disk (which would require coupling wheel install actions across dependencies) or setting `LD_LIBRARY_PATH` (which leaks into subprocesses), the Import Index solves this via **index-driven `ctypes.CDLL` preloading**:

![Cross-Wheel Native Library Preloading Pipeline](images/import_index_preload.svg)

### Why Preloading Works for Both `DT_NEEDED` and Lazy `dlopen("libfoo.so.1")`
In `glibc` (`elf/dl-load.c`, `_dl_map_object`), whenever the dynamic linker loads a shared object by bare SONAME—whether via an eager `DT_NEEDED` entry when importing a C extension or via a lazy `dlopen("libcudnn.so.9", RTLD_NOW)` call inside C++ code—**`glibc` checks the `DT_SONAME` of every library already loaded in the process's `link_map` *before* searching `DT_RPATH`, `LD_LIBRARY_PATH`, or `DT_RUNPATH`**.

1. During index merging, [`_compute_preload()`](../pycross/private/tools/import_index.py) inspects the `"native"` ELF metadata of every wheel in the binary's closure.
2. Whenever an ELF file in top-level package `P` (Wheel A) has an `$ORIGIN/...` `rpath` or `runpath` entry that escapes Wheel A and matches a directory owned by Wheel B, `_compute_preload()` collects all `.so` files with a `soname` in that target directory (covering both `DT_NEEDED` dependencies and lazy `dlopen` targets).
3. It performs a post-order DFS over `needed` SONAMEs and transitive escaping RPATHs so dependencies are ordered before dependents, emitting `"preload": {"<top_pkg>": [[wheel_idx, "<rel_so_path>"], ...]}`.
4. At runtime, the first time `PathFinder.find_spec` resolves `<top_pkg>`, [`_preload_native()`](../pycross/private/tools/import_index.py) pops `preload["<top_pkg>"]` and calls `ctypes.CDLL` on each path in topological order before returning the module spec.

---

## 4. Understanding the `_bazel_import_index.json` Format

To keep `_bazel_import_index.json` compact (~28 KB for ~100 wheels), wheel root paths are listed once in the `"roots"` array, and all other sections reference wheels by their **0-based integer index into `"roots"`**:

```json
{
  "version": 1,
  "roots": [
    "rules_pycross++uv+uv__pkgs/_lock/backports-entry-points-selectable@1.3.0/site-packages",
    "rules_pycross++uv+uv__pkgs/_lock/backports-tarfile@1.2.0/site-packages",
    "...",
    "_main/fixtures/nvidia_fixture_cublas/site-packages",
    "_main/fixtures/nvidia_fixture_cudnn/site-packages",
    "_main/fixtures/nvidia_fixture_nccl/site-packages",
    "_main/fixtures/pthfixture/site-packages",
    "_main/fixtures/rpathfixture/site-packages"
  ],
  "top": {
    "nvidia": [[34, ["nvidia"]], [35, ["nvidia"]], [36, ["nvidia"]]],
    "typing_extensions": [[17, ["typing_extensions.py"]]]
  },
  "merged": {
    "nvidia": [34, 35, 36],
    "google.cloud": [9, 24, 25, 28]
  },
  "sub": {
    "nvidia.fixture_cublas": 34,
    "nvidia.fixture_cudnn": 35,
    "google.cloud.storage": 28
  },
  "preload": {
    "rpathfixture": [
      [34, "nvidia/fixture_cublas/lib/libfixture_cublas.so.12"],
      [35, "nvidia/fixture_cudnn/lib/libfixture_cudnn.so.12"]
    ]
  },
  "pth": [
    ["pthfixture.pth", 37]
  ]
}
```

| Field | Meaning |
|---|---|
| `"roots"` | Ordered list of runfiles-relative wheel `site-packages` paths. Every integer `i` elsewhere in the file refers to `roots[i]`. |
| `"top"` | Maps top-level import name $\rightarrow$ `[[root_idx, [filenames]], ...]` in `sys.path` order. |
| `"merged"` | Maps dotted package directory $\rightarrow$ `[root_idx, ...]` for directories present in $\ge 2$ wheels. |
| `"sub"` | Maps dotted subpackage directory $\rightarrow$ `root_idx` for single-owner subdirectories whose parent is in `"merged"`, enabling $O(1)$ subpackage resolution without `stat`ting parent directories. |
| `"preload"` | Maps top-level package $\rightarrow$ `[[root_idx, rel_so_path], ...]` in topological load order for cross-wheel `$ORIGIN` native libraries. |
| `"pth"` | Sorted `[[pth_filename, root_idx], ...]` executed via `site.addpackage` at startup. |
| `"dists"` | Maps normalized distribution name $\rightarrow$ `[[root_idx, dist_info_dirname], ...]` for $O(1)$ `importlib.metadata` lookups. |

---

## 5. Benchmarks (Production Monorepo & 600-Wheel Scaling)

![Measured Performance Impact](images/import_index_benchmarks.svg)

| Metric | `off` (Plain `sys.path`) | `scan` (Startup `scandir`) | `prebuilt` (JSON Index) | Improvement (`prebuilt` vs `off`) |
|---|---:|---:|---:|---:|
| **`service_a` (94 wheels) `stat` syscalls** | 23,281 | 14,314 | **13,662** | **$-41.3\%$** |
| **`service_a` (94 wheels) `getdents64` syscalls** | 1,414 | 1,226 | **984** | **$-30.4\%$** |
| **`service_b` (126 wheels) `stat` syscalls** | 32,190 | 19,919 | **19,216** | **$-40.3\%$** |
| **`service_b` (126 wheels) `getdents64` syscalls** | 3,270 | 1,940 | **1,608** | **$-50.8\%$** |
| **50 missing-module `find_spec` probes (126 wheels)** | 71.0 ms | 4.2 ms | **4.2 ms** | **$16.9\times$ faster** |
| **7 subpackages under merged `google.*`/`opentelemetry.*`** | 6.36 ms | 4.79 ms | **2.07 ms** | **$3.1\times$ faster** |
| **Cold `importlib.metadata.version()` lookup** | 63.4 ms | 18.1 ms | **16.4 ms** | **$3.9\times$ faster** |
| **Index initialization time (94 wheels)** | — | 4.1 ms | **0.6 ms** | **$6.8\times$ faster than `scan`** |
| **600-wheel synthetic total import benchmark** | 3,487.3 ms | 420.3 ms | **418.6 ms** | **$8.3\times$ faster** |

---

## 6. Usage & Interactive Demo

The Import Index works on **stock released `rules_python`** with no `rules_python` fork required.

### Flags & Rules

Enable the index via `--@rules_pycross//pycross/settings:venv_import_index`:
```bash
# Build-time index + cross-wheel native preloading (recommended):
build --@rules_python//python/config_settings:bootstrap_impl=script
build --@rules_pycross//pycross/settings:venv_import_index=prebuilt

# Or startup directory scan (no index merge action):
build --@rules_pycross//pycross/settings:venv_import_index=scan
```

Two target styles are supported:
1. **Unmodified stock `@rules_python//python:defs.bzl` `py_binary` / `py_test` (zero `BUILD` changes):**
   - `pycross_wheel_library` automatically injects `pycross_import_index.pth` and `_bazel_import_index.py` into the venv via `PyInfo.venv_symlinks` (even through arbitrary chains of stock first-party `py_library` targets).
   - At startup, `_load_per_wheel_prebuilt()` reads the per-wheel `<wheel>.dist_info/index.json` files from runfiles and computes the merged index + `"preload"` table in memory.
2. **`pycross_py_binary` / `pycross_py_test` (or `pycross_venv_import_index` in `deps`):**
   ```starlark
   load("@rules_pycross//pycross:defs.bzl", "pycross_py_binary", "pycross_py_test")
   ```
   - Runs a `PyMakeVenvIndex` build action to pre-merge all transitive wheel indexes into a single `_bazel_import_index.json` file inside the venv's `site-packages/`, reducing startup index loading to **1 `openat()` call (`~0.6 ms`)**.

### Runtime Environment Variables
- `RULES_PYTHON_IMPORT_INDEX=off|scan|prebuilt|verify`: Override the index mode at runtime. `verify` cross-checks the prebuilt index against a live `os.scandir` walk of all wheel roots and exits non-zero on any discrepancy.
- `RULES_PYTHON_IMPORT_INDEX_DEBUG=1`: Log index load timing, merged packages, `find_spec` resolutions, and `ctypes.CDLL` preloads to `stderr`.

### Running the Interactive Demo (`tests/e2e/namespace_pkgs`)

```bash
cd tests/e2e/namespace_pkgs

# 1. Pre-merged _bazel_import_index.json via pycross_py_binary (all 5 checks pass):
bazel run --config=index //:demo

# 2. Stock py_binary loading per-wheel index.json files from runfiles (all 5 checks pass):
bazel run --config=index //:demo_stock

# 3. Debug trace showing startup timing and ctypes.CDLL preloads:
RULES_PYTHON_IMPORT_INDEX_DEBUG=1 bazel run --config=index //:demo

# 4. Verify mode (asserts prebuilt index matches disk 100%):
RULES_PYTHON_IMPORT_INDEX=verify bazel run --config=index //:demo

# 5. Compare with scan mode (Python imports pass, cross-wheel $ORIGIN RPATH fails):
bazel run --config=scan //:demo

# 6. Compare with plain sys.path (4 of 5 checks fail):
bazel run //:demo --@rules_python//python/config_settings:venvs_site_packages=no
```
