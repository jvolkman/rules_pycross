# `rules_pycross` — Python + cross platform

`rules_pycross` lets you use Python lock files with Bazel, enabling cross-platform, hermetic builds of Python dependencies — including native extensions.

> [!NOTE]
> [#243](https://github.com/jvolkman/rules_pycross/pull/243) merged a major "v2" overhaul. The prior release can be found at
> the [v1](https://github.com/jvolkman/rules_pycross/tree/v1) branch.

### Features

* Import lock files from **uv**, **PDM**, **Poetry**, or **PEP 751 pylock.toml**
* Build source distributions inside Bazel build actions, not during workspace initialization
* Pluggable build backends: setuptools, meson, cmake, maturin, and generic PEP 517
* Cross-platform sdist builds — build wheels for Linux and macOS from either host with an appropriate cross-compilation toolchain (e.g., [toolchains_llvm](https://github.com/bazel-contrib/toolchains_llvm))
* Multi-workspace support for monorepos with shared dependency deduplication
* Conflict/variant resolution for mutually exclusive dependencies (e.g., torch CPU vs. CUDA)
* Compatible with `rules_python` and Gazelle

**Platform support:** Linux and macOS are the primary supported platforms. Windows may work for some use cases but is not tested.

See the [CI results](https://github.com/jvolkman/rules_pycross/actions/workflows/ci.yml) for cross-platform build and test evidence.

## Getting Started

Add your lock file import to `MODULE.bazel`:

```python
lock_import = use_extension("@rules_pycross//pycross/extensions:lock_import.bzl", "lock_import")

lock_import.import_uv(
    lock_file = "//:uv.lock",
    project_file = "//:pyproject.toml",
    repo = "pypi",
)

lock_repos = use_extension("@rules_pycross//pycross/extensions:lock_repos.bzl", "lock_repos")
use_repo(lock_repos, "pypi")
```

After this, packages are available as `@pypi//package_name`. A `requirement()` macro is generated in `@pypi//:requirements.bzl`.

Other lock formats work the same way via `import_pdm`, `import_poetry`, or `import_pylock`.

Python versions are auto-discovered from registered `rules_python` toolchains, and all supported platforms are included by default. To restrict or customize platforms, use `pycross.configure_toolchains()`:

```python
pycross = use_extension("@rules_pycross//pycross/extensions:pycross.bzl", "pycross")
pycross.configure_toolchains(
    platforms = [
        "x86_64-unknown-linux-gnu",
        "aarch64-apple-darwin",
    ],
)
```

### How It Works

A `pip install` operation can be broken down into:

1. Determine the target environment (OS, CPU, Python version)
2. Resolve dependencies from a lock file
3. Select pre-built wheels or source distributions
4. Download and build

`rules_pycross` maps each step to Bazel primitives:

1. **Native Bazel Platforms** — target environments are determined by standard Bazel `@platforms` constraints and `rules_python` toolchain flags, mapped directly to PEP 508 markers at analysis time.
2. **`lock_import`** extension — translates a lock file into Bazel repository rules: `http_file` for downloads, build rules for source distributions.
3. **Build backends** (`setuptools_build`, `meson_build`, etc.) — build sdists into wheels inside sandboxed Bazel actions with remote execution support.
4. **`pycross_wheel_library`** — extracts a wheel (downloaded or built) and provides it as a `py_library`.

---

## Dependency Groups

Each import function supports selecting which dependency groups to include:

* `default_group` — include the project's default dependencies (default: `True`)
* `optional_groups` / `all_optional_groups` — include `[project.optional-dependencies]`
* `development_groups` / `all_development_groups` — include `[dependency-groups]`

---

## Extras

When a dependency is used with extras (e.g., `google-api-core[async_rest,grpc]`), `rules_pycross` generates separate targets for the base package and each extra:

```
@pypi//google_api_core               # Full package with all requested extras
@pypi//google_api_core:[]            # Base package only (no extra dependencies)
@pypi//google_api_core:[async_rest]  # Just the async_rest extra and its dependencies
@pypi//google_api_core:[grpc]        # Just the grpc extra and its dependencies
```

The `requirement()` macro supports this syntax directly:

```python
load("@pypi//:requirements.bzl", "requirement")

py_library(
    name = "my_lib",
    deps = [
        requirement("google-api-core[grpc]"),
    ],
)
```

---

## Multi-Workspace Lock Import

`rules_pycross` supports importing multiple members of a single workspace lock file into a shared backing repository. This is useful for monorepos where different subprojects need different dependency subsets.

### UV Workspace (Single Lock, Multiple Members)

```python
# 1. Declare the workspace (shared lock file and settings)
lock_import.import_uv_workspace(
    name = "shared",
    lock_file = "//:uv.lock",
)

# 2. Auto-discover all members; generate repos with a naming pattern
lock_import.uv_all_members(
    workspace = "shared",
    repo_pattern = "lock_{member}",  # e.g., 'project-a' -> '@lock_project_a'
)

lock_repos = use_extension("@rules_pycross//pycross/extensions:lock_repos.bzl", "lock_repos")
use_repo(lock_repos, "lock_project_a", "lock_project_b")
```

All members share a single backing `package_repo` — overlapping packages are downloaded and built only once.

### Overriding Member Settings

Individual members can override the repo name or dependency groups using `uv_member`:

```python
# Override project-a's repo name (instead of the pattern-generated 'lock_project_a')
lock_import.uv_member(
    workspace = "shared",
    project = "project-a",
    repo = "lock_a",
)

# Include specific optional groups only for project-b
lock_import.uv_member(
    workspace = "shared",
    project = "project-b",
    optional_groups = ["grpc", "testing"],
)
```

### Package Annotations in a Workspace

`lock_import.package()` annotations in a workspace must use the `workspace` attribute (not `repo`):

```python
# Apply to all members of the "shared" workspace
lock_import.package(
    name = "regex",
    install_exclude_globs = ["test_regex.py"],
    workspace = "shared",
)
```

Use `name = "*"` to set defaults for all packages. A specific annotation for a package fully replaces the wildcard:

```python
# Force all packages to build from source by default
lock_import.package(
    name = "*",
    always_build = True,
    workspace = "shared",
)

# Override the wildcard for a specific package
lock_import.package(
    name = "requests",
    always_build = False,
    workspace = "shared",
)
```

### Multiple Independent Lock Files

If your projects use separate lock files (not a shared workspace lock), each `import_uv` call creates its own isolated workspace:

```python
lock_import.import_uv(
    lock_file = "//frontend:uv.lock",
    project_file = "//frontend:pyproject.toml",
    repo = "frontend_deps",
)
lock_import.import_uv(
    lock_file = "//ml:uv.lock",
    project_file = "//ml:pyproject.toml",
    repo = "ml_deps",
)
```

---

## Sdist Builds and Build Overrides

`rules_pycross` uses a pluggable build backend architecture. Build backends are automatically detected from the `build-system.build-backend` value in each package's `pyproject.toml`.

### Supported Backends

| Backend | Detected from `build-backend` | Use case |
|---|---|---|
| `pep517_build` | `hatchling`, `flit_core`, `pdm.backend`, `poetry.core.masonry.api` | Pure-Python packages (default fallback) |
| `setuptools_build` | `setuptools.build_meta` | C extension packages using setuptools |
| `meson_build` | `mesonpy` | Scientific packages (numpy, pandas, etc.) |
| `cmake_build` | `scikit_build_core.build`, `skbuild` | Packages using CMake/scikit-build |
| `maturin_build` | `maturin` | Rust+Python packages |

### Forcing a Package to Build from Source

By default, `rules_pycross` uses pre-built wheels when available. To force building from source, set `always_build = True`:

```python
lock_import.package(
    name = "numpy",
    always_build = True,
    repo = "pypi",
)
```

### Build Overrides

When packages need native dependencies, compiler flags, environment variables, or other build customizations, use the backend-specific override extensions. Use `name = "*"` to set defaults for all packages built with that backend.

#### Setuptools

```python
setuptools = use_extension("@rules_pycross//pycross/backends:setuptools.bzl", "setuptools")

setuptools.override(
    name = "psycopg2",
    repo = "pypi",
    copts = ["-O2"],
    tool_deps = {"pg_config": "@@//deps/psycopg2:pg_config"},
    build_env = {"LDFLAGS": "-L/usr/lib"},
)
```

#### Meson

Building numpy with OpenBLAS, using `pycross_cc_pkg_config` to bridge Bazel CC deps into meson:

```python
load("@rules_pycross//pycross:defs.bzl", "pycross_cc_pkg_config")
load("@pypi//_backend:meson_build.bzl", "meson_build")

# Generate a pkg-config .pc file so meson can find OpenBLAS
pycross_cc_pkg_config(
    name = "gen_openblas_pc_file",
    dep = "//third_party/openblas",
    lib_name = "scipy-openblas",
    version = "0.3.20",
)

meson_build(
    name = "wheel",
    build_deps = [
        "@pypi//meson:pkg",
        "@pypi//ninja:pkg",
        "@pypi//cython:pkg",
    ],
    config_settings = {
        "setup-args": [],
        "compile-args": ["-v"],
    },
    copts = ["-Wl,-s"],
    native_deps = ["//third_party/openblas"],
    path_tools = [":cython"],
    pkg_config_files = [":gen_openblas_pc_file"],
    sdist = "@pypi//numpy:sdist",
)
```

#### Maturin

For Rust+Python packages, use the `rules_pycross_backend_maturin` module:

```python
bazel_dep(name = "rules_pycross_backend_maturin", version = "0.0.0")
bazel_dep(name = "rules_rust", version = "0.68.0")

# Register Rust toolchains
rust = use_extension("@rules_rust//rust:extensions.bzl", "rust")
rust.toolchain(
    edition = "2021",
    extra_target_triples = [
        "aarch64-apple-darwin",
        "aarch64-unknown-linux-gnu",
        "x86_64-unknown-linux-gnu",
    ],
)

# Mark packages for source build
lock_import.package(
    name = "rpds-py",
    always_build = True,
    repo = "pypi",
)
lock_import.package(
    name = "jiter",
    always_build = True,
    repo = "pypi",
)

# Provide a Cargo.lock for jiter (when the sdist doesn't include one)
maturin = use_extension("@rules_pycross_backend_maturin//extensions:maturin.bzl", "maturin")
maturin.override(
    name = "jiter",
    cargo_lock = "//:jiter.lock",
    repo = "pypi",
)
use_repo(maturin, "pypi_cargo")
```

#### Using a Custom Build Target

For full control, provide your own build target:

```python
lock_import.package(
    name = "psycopg2",
    build_target = "@//deps/psycopg2:wheel",
    repo = "pypi",
)
```

---

## Conflict and Variant Resolution

When a project needs mutually exclusive dependency versions—for example, `torch` for CPU vs. CUDA—`rules_pycross` supports `uv`'s conflict declarations.

### Declaring Conflicts

In your `pyproject.toml`:

```toml
[project.optional-dependencies]
cpu = ["torch==2.6.0"]
cu124 = ["torch==2.7.0"]

[tool.uv]
conflicts = [
  [
    { extra = "cpu" },
    { extra = "cu124" },
  ],
]
```

### How Variants Work in Bazel

When `rules_pycross` processes a lock file with conflicts, it generates:

1. **`bool_flag` targets** under `@<repo>//_variants:` — one per conflict member (e.g., `extra_cpu`, `extra_cu124`).
2. **`config_setting` targets** — `@<repo>//_variants:is_extra_cpu`, `@<repo>//_variants:is_extra_cu124`.
3. **`select()` expressions** on the package aliases — so `@<repo>//:torch` resolves to the correct version based on which flag is set.

### Selecting a Variant

Set the variant flag on the command line:

```bash
# Build with CPU torch
bazel build //my:target --@pypi//_variants:extra_cpu=True

# Build with CUDA torch
bazel build //my:target --@pypi//_variants:extra_cu124=True
```

Or embed the flag in a `platform()`:

```python
platform(
    name = "linux_cuda",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    flags = [
        "--@pypi//_variants:extra_cu124=True",
    ],
)
```

Then build with `--platforms=//:linux_cuda`.

### Default Groups

If `uv`'s `default-groups` is set, the corresponding variant is used as the `select()` default—building without flags resolves to that variant. Extras never have a default; building without an explicit flag produces a build error, preventing accidental misresolution.

### Dependency Group Conflicts

Conflicts also work with `[dependency-groups]`:

```toml
[dependency-groups]
test-fast = ["pytest==7.0.0"]
test-slow = ["pytest==8.0.0"]

[tool.uv]
conflicts = [
  [
    { group = "test-fast" },
    { group = "test-slow" },
  ],
]
```

The generated flags follow the pattern `group_<name>` (e.g., `--@pypi//_variants:group_test-fast=True`).

---

## rules_python Compatibility

`rules_pycross` integrates with `rules_python`. The generated target layout (`@<repo>//<package>`) is compatible with `rules_python` conventions.

* **Venv support** — when `rules_python` venvs are enabled, `pycross_wheel_library` populates the symlinks needed for a correct `site-packages` layout. Auto-detected paths can be overridden via `lock_import.package(site_paths = [...])`, and additional path categories (`bin_paths`, `data_paths`, `include_paths`) are also supported.
* **`py_console_script_binary`** — each `pycross_wheel_library` produces a `:dist_info` output group for entry point discovery. Use `py_console_script_binary(pkg = "@pypi//cython", script = "cython")` directly.

---

## Gazelle Integration

`rules_pycross` is compatible with `rules_python_gazelle_plugin`. The target layout (`@<repo>//<package>`) matches the plugin's default label conventions, so no `gazelle:python_label_convention` directives are needed.

The `pycross_modules_mapping` rule generates `modules_mapping.json` from package metadata at build time — wheels do not need to be downloaded or extracted during analysis.

```python
load("@gazelle//:def.bzl", "gazelle")
load("@rules_pycross//pycross:defs.bzl", "pycross_modules_mapping")
load("@rules_python_gazelle_plugin//manifest:defs.bzl", "gazelle_python_manifest")
load("@pypi//:requirements.bzl", "all_requirements")

pycross_modules_mapping(
    name = "modules_map",
    deps = all_requirements,
)

gazelle_python_manifest(
    name = "gazelle_python_manifest",
    modules_mapping = ":modules_map",
    pip_repository_name = "pypi",
)

# gazelle:python_extension enabled
# gazelle:python_root //
gazelle(
    name = "gazelle",
    gazelle = "@rules_python_gazelle_plugin//python:gazelle_binary",
)
```

```bash
> bazel run //:gazelle_python_manifest.update  # Update gazelle_python.yaml
> bazel run //:gazelle                          # Apply BUILD file changes
```

---

See the [API reference docs](docs/) and [e2e tests](tests/e2e/) for more examples.
