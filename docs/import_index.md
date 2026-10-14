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
        W1["PycrossWheelInstall (Wheel 1..N)"] -->|"writes"| I1["<wheel>.dist_info/index.json"]
        W1 -->|"if native ELF (.so)"| D1["site-packages/.pycross-native[-consumer].json"]
        I1 -->|"pycross_modules_mapping"| G["Gazelle modules_mapping.json"]
    end

    subgraph Runtime["Runtime (Python Startup - Split-File Hybrid)"]
        PTH["pycross_import_index.pth"] -->|"auto_install()"| PF["_bazel_import_index.PathFinder"]
        D1 -->|"0 JSON reads if 0 consumers;\neager or lazy ensure_native_loaded()"| PF
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
   - `native`: ELF metadata (`soname`, `needed`, `rpath`, `runpath`, `ei_class`, `ei_data`, `e_machine`) for every `.so` file in the wheel (parsed via pure-Python [`elf_tools.py`](../pycross/private/tools/elf_tools.py))
2. **In-Root Native Dotfiles (`.pycross-native-consumer.json` / `.pycross-native.json`):**
   When a wheel contains ELF `.so` files (`native` is non-empty), `wheel_index.py` also writes a compact version-2 dotfile (`{"version": 2, "top": [...], "dirs": [...], "native": {...}}`) directly inside `<wheel_target>/site-packages/`:
   - `.pycross-native-consumer.json` if any ELF file in the wheel has an `$ORIGIN` `DT_RPATH` / `DT_RUNPATH` entry that escapes its own wheel directory tree (`compute_escaping_rpaths` is non-empty; e.g., `nvidia-cudnn-cu12`, `nvidia-cusolver-cu12`, `tensorflow`, `torch`, `pyqt5`). The install action precomputes and stores each consumer library's normalized escaping candidate directories and whether they came from `DT_RPATH` or `DT_RUNPATH` under `"escaping"` (`{rel_so: {"rpath": [...], "runpath": [...]}}`), so the runtime only maps those relative directories to provider libraries.
   - `.pycross-native.json` otherwise, when all ELF files in the wheel have no escaping `$ORIGIN` RPATH/RUNPATH (e.g., `numpy`, `scipy`, `nvidia-cublas-cu12`, `pyqt5-qt5`, `pillow`, `h5py`, `grpcio`, `protobuf`, or wheels with only bare-SONAME `DT_NEEDED` entries).
   - Pure-Python wheels have no dotfile at all.
3. **Exact Gazelle `modules_mapping.json`:**
   [`pycross_modules_mapping`](../pycross/private/modules_mapping.bzl) builds `modules_mapping.json` from the post-install per-wheel `index.json` files instead of repo-time `site_paths` heuristics.
4. **Venv Runtime Injection via `PyInfo.venv_symlinks`:**
   When `--@rules_pycross//pycross/settings:venv_import_index` is enabled (`prebuilt` or `scan`), `pycross_wheel_library` includes `pycross_import_index.pth` and `_bazel_import_index.py` in `PyInfo.venv_symlinks`, propagating automatically through arbitrary chains of stock `py_library` targets into any stock `py_binary` or `py_test` without staging `<name>.dist_info/index.json` into runtime runfiles.

### Runtime Finder (`_bazel_import_index.PathFinder`)
At Python startup, `bazel.pth` runs `_bazel_site_init.py` (which populates `sys.path`), and immediately afterward `pycross_import_index.pth` runs `_bazel_import_index.auto_install()`, replacing `importlib.machinery.PathFinder` in `sys.meta_path` with [`_bazel_import_index.PathFinder`](../pycross/private/tools/import_index.py):

- **Split-file hybrid startup (`_scan_root_with_native`):**
  Every wheel root on `sys.path` is indexed via a single `os.scandir` call (`~3.6 ms` for 94 wheels, `~4.7 ms` for 126 wheels). In that same `os.scandir` loop (zero extra `stat` syscalls), `_Index` records `.pycross-native-consumer.json` and `.pycross-native.json` while ignoring dotfiles as Python modules.
  - **0 consumer wheels $\rightarrow$ 0 JSON reads at startup:** If no wheel in the binary has `.pycross-native-consumer.json`, startup reads **zero** JSON files and matches `scan` mode speed (`3.6 ms` / `4.7 ms`). The native graph (`ensure_native_loaded()`) is loaded lazily only if a wheel or first-party C extension import or wheel `.so` `dlopen` fails with a missing `DT_NEEDED` shared library, or if a bare-name `dlopen` fallback, `ctypes.util.find_library` fallback, or escaped wheel path `dlopen` is encountered at runtime.
  - **$\ge 1$ consumer wheel $\rightarrow$ eager native graph load:** If at least one wheel has `.pycross-native-consumer.json`, `ensure_native_loaded()` runs at startup, reading only the native wheels' dotfiles (`len(native_files)` instead of all $N_{\text{wheels}}$) to populate `preload`, `sonames`, and `native_deps`.
- **`pre` $\rightarrow$ `wheels` ($O(1)$) $\rightarrow$ `post` ordering:**
  `sys.path` is partitioned into `pre` (the Python stdlib and any earlier non-wheel paths), `wheels` (all wheel `site-packages` roots collapsed into one virtual merged directory), and `post` (`<runfiles>/<workspace_name>`, where first-party `py_library` sources live).
  - Because `pre` runs first, an `enum34`-style backport wheel can never shadow the stdlib.
  - Because `wheels` resolves in $O(1)$ from the index dict, importing any **first-party `py_library` module** from `post` skips $O(N_{\text{wheels}})$ `stat` calls and jumps straight to `<runfiles>/<workspace_name>`.
- **Multi-owner package & subpackage merging (`merged` & `sub`):**
  When multiple wheels own the same package directory (`nvidia`, `google.cloud`, `azure.core.tracing.ext`), the finder populates `__path__` with all owner directories in `sys.path` order.
- **First-party + wheel shared namespaces:**
  PEP 420 namespaces shared between first-party `py_library` targets and wheels accumulate portions across `pre`, `wheels`, and `post` (even if Bazel's `legacy_create_init` synthesizes an empty `__init__.py` in `<runfiles>/_main`).
- **$O(1)$ `importlib.metadata` with memoized `read_text()`:**
  Distribution lookups by name (`importlib.metadata.version("...")`) resolve in $O(1)$ from the index, and `PathDistribution.read_text()` is cached in memory for `METADATA`, `PKG-INFO`, and `entry_points.txt`.

---

## 3. Cross-Wheel Native Library Preloading & Dynamic Loader Hooks

Many native Python wheels (such as `tensorflow` + `nvidia-*-cu12`, `onnxruntime-gpu`, or split C++/CUDA wheel families) rely on shared libraries distributed across separate wheels. When each wheel lives in its own Bazel `TreeArtifact`, three cross-wheel native loading patterns break without assistance:

1. **Escaping `$ORIGIN` RPATHs:** An extension or library in Wheel A has `DT_RPATH` / `DT_RUNPATH` set to `$ORIGIN/../nvidia/cudnn/lib`, which resolves inside Wheel A's `TreeArtifact` instead of Wheel B's.
2. **Unsatisfied cross-wheel `DT_NEEDED` by bare SONAME:** A plugin `.so` in Wheel A (such as `libonnxruntime_providers_cuda.so`) has `DT_NEEDED: ["libcublas.so.12", "libcudnn.so.9"]` with no escaping `$ORIGIN` RPATH, expecting its dependencies to be preloaded or on `LD_LIBRARY_PATH`.
3. **Python-level `ctypes` / `cffi` path computation and bare-SONAME `dlopen`:** Python initialization code constructs `os.path.join(os.path.dirname(__file__), "..", "nvidia", ...)` or calls `ctypes.CDLL("libcudnn.so.9")` / `ctypes.util.find_library("cublas")` / `ffi.dlopen("cublas")`.

Instead of patching ELF binaries on disk (which would couple wheel install actions across dependencies) or setting `LD_LIBRARY_PATH` (which leaks into subprocesses), the Import Index handles these via **index-driven preloading and lazy loader hooks**:

![Cross-Wheel Native Library Preloading Pipeline](images/import_index_preload.svg)

### 3.1 Build-Time / Startup Dependency Graph (`_compute_native`)
1. During per-wheel indexing, [`elf_tools.py`](../pycross/private/tools/elf_tools.py) records `{soname, needed, rpath, runpath, ei_class, ei_data, e_machine}` for every ELF `.so` file and SONAME symlink in the wheel, and `compute_escaping_rpaths()` precomputes each consumer library's normalized escaping `$ORIGIN` candidate directories (`{"rpath": [...], "runpath": [...]}`, honoring `DT_RPATH` only when the object has no `DT_RUNPATH`).
2. When building the cross-wheel native graph (`ensure_native_loaded()` at runtime or [`merge_wheel_indexes()`](../pycross/private/tools/import_index.py)), `_compute_native()` builds a cross-wheel SONAME table (`"sonames"`) and RPATH-reachable dependency closures (`"preload"` and `"native_deps"`):
   - **The loader decides (no Python host-check layer):** Instead of probing `/etc/ld.so.cache`, default system library directories, or `RTLD_NOLOAD` in Python, the real dynamic linker decides whether a library is already satisfied on the host:
     - Eager preloads (consumer wheels at startup, and `"native_deps"` closures used by the escaped-path rewrite and retry) follow **only RPATH-reachable edges**: own-wheel dependencies reached by the library's own `DT_RPATH` / `DT_RUNPATH`, and cross-wheel dependencies reached by the precomputed `"escaping"` `$ORIGIN` directories.
     - Unsatisfied bare-SONAME `DT_NEEDED` entries (without an escaping RPATH), bare-name `dlopen` / `cffi`, and `ctypes.util.find_library` are **never** preloaded eagerly; the real dynamic linker or system lookup runs first, and `"sonames"` is consulted only as a fallback if that lookup fails.
   - **`DT_RPATH` vs `LD_LIBRARY_PATH` vs `DT_RUNPATH` ordering:** Matching `pip` and ELF dynamic linker semantics, `DT_RPATH` (only honored when the object has no `DT_RUNPATH`) beats `LD_LIBRARY_PATH`, and `LD_LIBRARY_PATH` beats `DT_RUNPATH`. When an eager target comes from a `DT_RUNPATH` entry, it is skipped if `LD_LIBRARY_PATH` (snapshotted at `install()` time, since `glibc` reads `LD_LIBRARY_PATH` only at process startup) contains a file for that SONAME matching the current process's 32/64-bit ELF class (`_elf_matches_process_class`, a 5-byte header check).
   - **Trigger keys:** Preload lists are keyed by the owning top-level package, by every importable top-level name when libraries live in `<pkg>.libs/` (`auditwheel` layout), or by the single-owner subpackage in `"sub"` (such as `"nvidia.cudnn"`) when the top-level namespace is shared across wheels.
   - **Topological sort:** A post-order DFS orders transitive RPATH-reachable `DT_NEEDED` and escaping RPATH dependencies before dependents.

### 3.2 `glibc` vs `musl` Preload Backends
- **`glibc`:** In `glibc` (`elf/dl-load.c`, `_dl_map_object`), whenever the dynamic linker resolves a library by bare SONAME—whether via `DT_NEEDED` or `dlopen("libcudnn.so.9", RTLD_NOW)`—it checks the `DT_SONAME` of every library already in the process's `link_map` *before* searching `DT_RPATH`, `LD_LIBRARY_PATH`, or `DT_RUNPATH`. Calling `ctypes.CDLL(abs_path)` in topological order registers each library's `DT_SONAME` in `link_map`.
- **`musl` (Alpine Linux):** In `musl` (`ldso/dynlink.c`), `dlopen("/abs/path/to/libfoo.so.1")` leaves `p->shortname` unset (`NULL`) because the argument contains `'/'`, so a subsequent `DT_NEEDED` or bare-name `dlopen("libfoo.so.1")` will not match the already-loaded library unless `p->shortname` is populated via a `DT_RPATH` + bare-name load. On `musl`, `_load_native_path()` synthesizes a tiny (~360-byte) in-memory ELF64 `ET_DYN` stub (`PT_LOAD` `PF_R | PF_W`, `DT_RPATH = dirname(abs_path)`, `DT_NEEDED = soname or basename(abs_path)`) using `soname`, `ei_class`, `ei_data`, and `e_machine` recorded in the wheel dotfile (without opening the target `.so` file in Python) via `os.memfd_create("pycross_stub", MFD_CLOEXEC | MFD_NOEXEC_SEAL)` (falling back to `NamedTemporaryFile` if `memfd_create` or `/proc/self/fd` is unavailable, or directly to `_raw_dlopen(abs_path)` on 32-bit ELF or if `filename != DT_SONAME` and no matching `DT_SONAME` symlink exists in the directory) and loads it via `/proc/self/fd/<fd>`, which causes `musl` to resolve the library by shortname through `DT_RPATH` and populate `p->shortname`.

### 3.3 Lazy Retry-on-Failure & `ctypes` / `cffi` Hooks
- **Lazy retry on unsatisfied `DT_NEEDED` (`ExtensionFileLoader.create_module` & wheel-path `dlopen`):**
  Because `.pycross-native-consumer.json` only marks wheels with escaping `$ORIGIN` RPATH/RUNPATH entries, a binary whose wheels have no escaping `$ORIGIN` RPATHs reads **0** native dotfiles at startup. And in normal (non-`verify`) operation, `_bazel_import_index` never opens or parses wheel or first-party ELF files in Python. If any non-stdlib C/C++ extension (`ExtensionFileLoader.create_module`, whether in a wheel or a first-party target) or a `ctypes`/`cffi` load of a wheel `.so` path raises `ImportError` / `OSError` due to an unsatisfied cross-wheel `DT_NEEDED` (`"...: cannot open shared object file"` on `glibc` or `"Error loading shared library ..."` on `musl`), the wrapper parses the missing SONAME, calls `ensure_native_loaded()`, preloads the provider library and its transitive `"native_deps"` closure, and retries the load.
- **Zero-startup-cost `ctypes` / `cffi` hooks:**
  When `_ctypes`, `ctypes`, `ctypes.util`, or `_cffi_backend` is imported, `PathFinder.find_spec` wraps the module loader to install lightweight resolvers (costing `0 ms` when those modules are not imported):
  - **`_ctypes.dlopen` & `_cffi_backend` (`load_library`, `FFI.dlopen`):**
    - If a path containing `'/'` does not exist on disk and escaped a wheel root in `_INDEX.roots` via `..` (e.g., `<torch_wheel>/site-packages/torch/../nvidia/cudnn/lib/libcudnn.so.9`), rewrites it to the owning wheel root's path and preloads its `"native_deps"` closure before calling `dlopen`.
    - For bare library names (no `'/'`), calls the original `dlopen` / `load_library` **first** (preserving `LD_LIBRARY_PATH`, `/etc/ld.so.cache`, host GPU drivers, and system library directories) and only falls back to `"sonames"` if the original call raises `OSError`.
  - **`ctypes.util.find_library`:** Calls the original `find_library(name)` first and only falls back to non-host wheel `"sonames"` (`<name>`, `lib<name>.so`, or `lib<name>.so.*`) when the system lookup returns `None`.

### 3.4 Remaining Scope & Known Limitations
- **Native code that finds CUDA tools and data relative to its own file:** XLA (jaxlib, TensorFlow) builds its CUDA search roots in `tsl::CandidateCudaRoots()` (`xla/tsl/platform/default/cuda_root_path.cc`). It calls `dladdr` on itself and adds `<dir>/../nvidia/cuda_nvcc` and `<dir>/../../nvidia/cuda_nvcc` (`nvidia/cu13` for CUDA 13) to find `ptxas`, `nvlink` and `libdevice.10.bc`. With the import index, `<dir>` is inside the jaxlib or tensorflow wheel, so those candidates don't exist, and XLA falls back to `CUDA_HOME`, `/usr/local/cuda` and `/opt/cuda`. These are file lookups, not `dlopen` calls, so no loader hook sees them. Setting `RULES_PYTHON_IMPORT_INDEX_SET_CUDA_ENV=1` (opt-in, default off) sets `CUDA_HOME` and prepends `<wheel_root>/nvidia/<cuda_nvcc|cu13>/bin` to `PATH` when `nvidia.cuda_nvcc` or `nvidia.cu13` is in the index, which covers this case. No package is known to build such an escaped path for `dlopen` itself; loads by bare SONAME are covered by preloading.
- **Subprocesses:** Python subprocesses started with `sys.executable`, including `multiprocessing` spawn, run the same venv interpreter, so `site` processes `pycross_import_index.pth` and they get the same index and hooks (they inherit `RUNFILES_DIR`). Native executables such as `ptxas` and `nvcc` get none of this. Python code that locates them from module paths (e.g. `nvidia.cuda_nvcc.__file__`) works, because modules resolve to the real wheel directories; native lookups like XLA's above need `RULES_PYTHON_IMPORT_INDEX_SET_CUDA_ENV`.
- **`bootstrap_impl=system_python` on Bazel 7:** On Bazel 8+, `rules_python` creates the full venv (`pycross_import_index.pth`) under both `bootstrap_impl=script` and `bootstrap_impl=system_python`. On Bazel 7 with `bootstrap_impl=system_python`, `.pth` files in the venv are not processed unless `bootstrap_impl=script` is enabled.
- **macOS (`dyld`) and Windows (`LoadLibraryExW`):** `auto_install()` is a no-op on Windows. On macOS the import finder is installed, but the native metadata parser only reads ELF, so cross-wheel Mach-O dependencies (`@rpath` / `@loader_path` into another wheel, e.g. PyQt5 → PyQt5-Qt5) aren't preloaded, and Windows `.dll` directories aren't indexed.

---

## 4. Understanding the Merged Import Index Schema

When `merge_wheel_indexes()` merges the per-wheel `<wheel>.dist_info/index.json` files at startup, wheel root paths are listed once in the `"roots"` array, and all other sections reference wheels by their **0-based integer index into `"roots"`**:

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
| `"preload"` | Maps package/subpackage trigger key $\rightarrow$ `[[root_idx, rel_so_path], ...]` in topological load order for cross-wheel `$ORIGIN` and `DT_NEEDED` native libraries. |
| `"sonames"` | Maps library SONAME (or filename for libraries without `DT_SONAME`) $\rightarrow$ `[root_idx, rel_so_path]` for runtime `dlopen` / `find_library` / first-party extension resolution. |
| `"native_deps"` | Maps `"<root_idx>:<rel_so_path>"` $\rightarrow$ `[[dep_root_idx, dep_rel_so_path], ...]` in topological order for on-demand preloading when a library is loaded directly via `dlopen` or a first-party extension. |
| `"pth"` | Sorted `[[pth_filename, root_idx], ...]` executed via `site.addpackage` at startup. |
| `"dists"` | Maps normalized distribution name $\rightarrow$ `[[root_idx, dist_info_dirname], ...]` for $O(1)$ `importlib.metadata` lookups. |

---

## 5. Benchmarks (Production Monorepo & 600-Wheel Scaling)

![Measured Performance Impact](images/import_index_benchmarks.svg)

| Metric | `off` (Plain `sys.path`) | `scan` (Startup `scandir`) | `prebuilt` (Split-File Hybrid) | Improvement (`prebuilt` vs `off`) |
|---|---:|---:|---:|---:|
| **`service_a` (94 wheels) `stat` syscalls** | 23,281 | 14,314 | **13,662** | **$-41.3\%$** |
| **`service_a` (94 wheels) `getdents64` syscalls** | 1,414 | 1,226 | **984** | **$-30.4\%$** |
| **`service_b` (126 wheels) `stat` syscalls** | 32,190 | 19,919 | **19,216** | **$-40.3\%$** |
| **`service_b` (126 wheels) `getdents64` syscalls** | 3,270 | 1,940 | **1,608** | **$-50.8\%$** |
| **`service_a` (94 wheels, 17 native, 0 consumers) index init** | — | 3.58 ms | **3.60 ms** (0 JSON reads) | **$4.9\times$ faster than full JSON merge** |
| **`service_b` (126 wheels, 23 native, 0 consumers) index init** | — | 4.77 ms | **4.73 ms** (0 JSON reads) | **$5.9\times$ faster than full JSON merge** |
| **50 missing-module `find_spec` probes (126 wheels)** | 71.0 ms | 4.2 ms | **4.2 ms** | **$16.9\times$ faster** |
| **7 subpackages under merged `google.*`/`opentelemetry.*`** | 6.36 ms | 4.79 ms | **2.07 ms** | **$3.1\times$ faster** |
| **Cold `importlib.metadata.version()` lookup** | 63.4 ms | 18.1 ms | **16.4 ms** | **$3.9\times$ faster** |
| **600-wheel synthetic total import benchmark** | 3,487.3 ms | 420.3 ms | **418.6 ms** | **$8.3\times$ faster** |

---

## 6. Usage & Interactive Demo

The Import Index works with **unmodified stock `@rules_python//python:defs.bzl` `py_binary` and `py_test` targets** on released `rules_python` with zero `BUILD` file changes and no `rules_python` fork required.

### Flags

Enable the index via `--@rules_pycross//pycross/settings:venv_import_index`:
```bash
# Split-file hybrid (`os.scandir` + consumer-driven native dotfiles, recommended):
build --@rules_python//python/config_settings:bootstrap_impl=script
build --@rules_pycross//pycross/settings:venv_import_index=prebuilt

# Or startup directory scan (for pure-Python wheels without native preloading):
build --@rules_pycross//pycross/settings:venv_import_index=scan
```

How it works on stock `py_binary` / `py_test`:
- `pycross_wheel_library` automatically injects `pycross_import_index.pth` and `_bazel_import_index.py` into the venv via `PyInfo.venv_symlinks` (even through arbitrary chains of stock first-party `py_library` targets).
- At startup, `_Index` scans each wheel root via `os.scandir` (`_scan_root_with_native`) and detects any `.pycross-native-consumer.json` or `.pycross-native.json` dotfiles in the same pass. If $\ge 1$ wheel has `.pycross-native-consumer.json`, `ensure_native_loaded()` eagerly reads the native dotfiles and computes `"preload"`, `"sonames"`, and `"native_deps"`; otherwise **0** JSON files are read at startup and `ensure_native_loaded()` runs lazily on first need.

### Runtime Environment Variables
- `RULES_PYTHON_IMPORT_INDEX=off|scan|prebuilt|verify`: Override the index mode at runtime. `verify` cross-checks the wheel roots and native dotfiles (`.pycross-native-consumer.json` / `.pycross-native.json`) against a live `os.scandir` + ELF walk of all wheel roots and exits non-zero on any discrepancy.
- `RULES_PYTHON_IMPORT_INDEX_DEBUG=1`: Log index load timing, merged packages, `find_spec` resolutions, `ctypes.CDLL` preloads, and `dlopen` rewrites to `stderr`.
- `RULES_PYTHON_IMPORT_INDEX_SET_CUDA_ENV=0|1` (default `0`): Opt in to setting `CUDA_HOME` and prepending `<wheel_root>/nvidia/<cuda_nvcc|cu13>/bin` to `PATH` when `nvidia.cuda_nvcc` or `nvidia.cu13` is present in the wheel index and `CUDA_HOME` / `CUDA_PATH` are unset.
- `RULES_PYTHON_IMPORT_INDEX_LIBC=glibc|musl`: Override automatic libc detection (`os.confstr("CS_GNU_LIBC_VERSION")`) for testing the `glibc` direct `CDLL` vs `musl` `memfd` stub ELF loader backend.

### Running the Interactive Demo (`tests/e2e/namespace_pkgs`)

```bash
cd tests/e2e/namespace_pkgs

# 1. Prebuilt index with stock py_binary (all 5 checks pass):
bazel run --config=index //:demo

# 2. Debug trace showing startup timing and ctypes.CDLL preloads:
RULES_PYTHON_IMPORT_INDEX_DEBUG=1 bazel run --config=index //:demo

# 3. Verify mode (asserts prebuilt index matches disk 100%):
RULES_PYTHON_IMPORT_INDEX=verify bazel run --config=index //:demo

# 4. Compare with scan mode (Python imports pass, cross-wheel $ORIGIN RPATH fails):
bazel run --config=scan //:demo

# 5. Compare with plain sys.path (4 of 5 checks fail):
bazel run //:demo --@rules_python//python/config_settings:venvs_site_packages=no
```
