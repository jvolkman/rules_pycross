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
uv = use_extension("@rules_pycross//pycross/extensions:uv.bzl", "uv")

uv.workspace(
    name = "pypi",
    lock_file = "//:uv.lock",
)
use_repo(uv, "pypi")
```

For a single-project lock file, this is all you need — `rules_pycross` auto-discovers the project from the lock file and creates a repo named `"pypi"` with default dependencies.

To customize which projects or dependency groups are included, add a `uv.repo()` tag:

```python
uv.workspace(
    name = "pypi",
    lock_file = "//:uv.lock",
)
uv.repo(
    dependency_groups = ["default", "optional:grpc"],
    workspace = "pypi",
)
use_repo(uv, "pypi")
```

After this, packages are available as `@pypi//package_name`. A `requirement()` macro is generated in `@pypi//:requirements.bzl`.

Other lock formats work the same way via their respective extensions: `pdm.bzl`, `poetry.bzl`, or `pylock.bzl`.

### Repository Defaults and Auto-Generation

#### The Default Workspace Repository

For simple, single-project lock files, you can omit the `uv.repo()` tag entirely. `rules_pycross` will automatically synthesize a repository for you with the following defaults:

* **Name**: Matches the workspace name (e.g., `@pypi`).
* **Content**: Includes only the `"default"` dependency group of the single discovered project.

To override these defaults (for example, to include optional extras or change the name), explicitly declare one or more `uv.repo()` tags.

#### Project File Discovery

`rules_pycross` automatically discovers your `pyproject.toml` files by inspecting the workspace members defined in the lock file. If it finds none (e.g. for a standalone lock file), it falls back to looking for a `pyproject.toml` next to the lock file.

If you have additional `pyproject.toml` files that aren't part of the lock file's defined workspace members, but contain build settings or dependency definitions you need `rules_pycross` to see, you can explicitly add them using `extra_project_files` on the `workspace()` tag:

```python
uv.workspace(
    name = "pypi",
    lock_file = "//:uv.lock",
    extra_project_files = ["//:pyproject.toml", "//tools:pyproject.toml"],
)
```

These explicitly specified files are appended to the auto-discovered files.

#### Transitive Aliases

By default, `rules_pycross` only generates top-level aliases for packages that are explicitly defined as dependencies in your project. If you want to be able to depend on transitive dependencies directly using `requirement("transitive-package")`, you can enable `create_transitive_aliases` on your `uv.repo()` tag:

```python
uv.repo(
    workspace = "pypi",
    create_transitive_aliases = True,
)
```

If a transitive package has multiple versions in the lock file, `rules_pycross` will print a warning and alias to the highest version.

#### The Internal Build Tools Repository (`__build`)

For every workspace, `rules_pycross` also auto-generates an internal companion repository named `<workspace>__build` (e.g., `@pypi__build`).

* **Purpose**: Provides build-time tools (like `setuptools`, `hatchling`, etc.) required to build source distributions (sdists) hermetically.
* **Content**: Includes all projects and all dependency groups (`*`) from the workspace.

This repository is managed automatically. However, if you need to customize its settings (such as restricting its dependency groups), you can override it by explicitly declaring a repo with the `<workspace>__build` name:

```python
uv.repo(
    name = "pypi__build",
    dependency_groups = ["default", "group:build"],
    workspace = "pypi",
)
```

### Migrating from the legacy two-extension pattern</summary>

The previous approach used `lock_import` / `lock_repos` (or `lock`) extensions. These have been removed.
Migrate by replacing them with the per-format extension:

```python
# Before (removed):
lock_import = use_extension("@rules_pycross//pycross/extensions:lock_import.bzl", "lock_import")
lock_import.import_uv(
    lock_file = "//:uv.lock",
    project_file = "//:pyproject.toml",
    repo = "pypi",
)
lock_import.package(
    name = "numpy",
    always_build = True,
    repo = "pypi",
)
lock_repos = use_extension("@rules_pycross//pycross/extensions:lock_repos.bzl", "lock_repos")
use_repo(lock_repos, "pypi")

# After:
uv = use_extension("@rules_pycross//pycross/extensions:uv.bzl", "uv")
uv.workspace(
    name = "pypi",
    lock_file = "//:uv.lock",
)
uv.repo(
    workspace = "pypi",
)
uv.package(
    name = "numpy",
    always_build = True,
    workspace = "pypi",  # was: repo = "pypi"
)
use_repo(uv, "pypi")
```

> [!TIP]
> If you are migrating from a 1.x target layout where packages were referenced as `@pypi//:package_name` (with a colon), you can enable `legacy_create_root_aliases = True` on your `uv.repo()` tag to generate these aliases in the 2.x repo.

### Toolchain Configuration

Python versions are auto-discovered from registered `rules_python` toolchains, and all supported platforms are included by default. You can restrict or customize this behavior using `pycross.configure_toolchains()` in your `MODULE.bazel`:

```python
pycross = use_extension("@rules_pycross//pycross/extensions:pycross.bzl", "pycross")
pycross.configure_toolchains(
    # Restrict supported platforms
    platforms = [
        "x86_64-unknown-linux-gnu",
        "aarch64-apple-darwin",
    ],
    # Restrict supported Python versions
    python_versions = [
        "3.11",
        "3.12",
    ],
    # Set platform version constraints
    glibc_version = "2.28",
    macos_version = "15.0",
    musl_version = "1.2",
)
```

By default, `rules_pycross` will automatically register toolchains for all configured platforms and versions. You can disable this by setting `register_toolchains = False` if you prefer to register them manually.

### How It Works

A `pip install` operation can be broken down into:

1. Determine the target environment (OS, CPU, Python version)
2. Resolve dependencies from a lock file
3. Select pre-built wheels or source distributions
4. Download and build

`rules_pycross` maps each step to Bazel primitives:

1. **Native Bazel Platforms** — target environments are determined by standard Bazel `@platforms` constraints and `rules_python` toolchain flags, mapped directly to PEP 508 markers at analysis time.
2. **Lock extensions** (`uv`, `pdm`, etc.) — translates a lock file and resolves dependencies into Bazel repository rules: `http_file` for downloads, build rules for source distributions.
3. **Build backends** (`setuptools_build`, `meson_build`, etc.) — build sdists into wheels inside sandboxed Bazel actions with remote execution support.
4. **`pycross_wheel_library`** — extracts a wheel (downloaded or built) and provides it as a `py_library`.

---

## Dependency Groups

The `dependency_groups` attribute on `uv.repo()` controls which dependency groups are included. It accepts a list of group specifiers:

* `"default"` — the project's default dependencies
* `"optional:<name>"` — a specific optional dependency group (`[project.optional-dependencies]`)
* `"group:<name>"` — a specific dependency group (`[dependency-groups]`)
* `"optional:*"` / `"group:*"` — all optional or all dependency groups
* `"*"` — all groups (default + all optional + all development)

The default is `["default"]`.

```python
uv.repo(
    dependency_groups = ["default", "optional:grpc", "group:test"],
    workspace = "pypi",
)
```

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
uv = use_extension("@rules_pycross//pycross/extensions:uv.bzl", "uv")

# 1. Declare the workspace (shared lock file and settings)
uv.workspace(
    name = "shared",
    lock_file = "//:uv.lock",
)

# 2. Import all projects into a single repo
uv.repo(
    name = "lock_all",
    projects = ["*"],
    workspace = "shared",
)
use_repo(uv, "lock_all")
```

All members share a single backing `package_repo` — overlapping packages are downloaded and built only once.

### Per-Member Repos

To create separate repos per workspace member with different dependency selections:

```python
uv.repo(
    name = "lock_a",
    projects = ["project-a"],
    workspace = "shared",
)
uv.repo(
    name = "lock_b",
    projects = ["project-b"],
    dependency_groups = ["default", "optional:grpc", "group:testing"],
    workspace = "shared",
)
use_repo(uv, "lock_a", "lock_b")
```

### Package Annotations in a Workspace

`uv.package()` annotations target a workspace. The `workspace` attribute can be omitted if the module declares only one workspace:

```python
# Apply to all members of the "shared" workspace
uv.package(
    name = "regex",
    install_exclude_globs = ["test_regex.py"],
    workspace = "shared",
)
```

Use `name = "*"` to set defaults for all packages. A specific annotation for a package fully replaces the wildcard:

```python
# Force all packages to build from source by default
uv.package(
    name = "*",
    always_build = True,
    workspace = "shared",
)

# Override the wildcard for a specific package
uv.package(
    name = "requests",
    always_build = False,
    workspace = "shared",
)
```

### Multiple Independent Lock Files

If your projects use separate lock files (not a shared workspace lock), declare separate workspaces:

```python
uv.workspace(
    name = "frontend_deps",
    lock_file = "//frontend:uv.lock",
)
uv.repo(
    workspace = "frontend_deps",
)
uv.workspace(
    name = "ml_deps",
    lock_file = "//ml:uv.lock",
)
uv.repo(
    workspace = "ml_deps",
)
use_repo(uv, "frontend_deps", "ml_deps")
```

---

## Sdist Builds and Build Overrides

`rules_pycross` uses a pluggable build backend architecture. Build backends are automatically detected from the `build-system.build-backend` value in each package's `pyproject.toml`.

### Supported Backends

| Backend | Detected from `build-backend` | Use case |
|---|---|---|
| `pep517_build` | `hatchling`, `flit_core`, `pdm.backend`, `poetry.core.masonry.api` | Pure-Python packages (default fallback) |
| `setuptools_build` | `setuptools.build_meta` | C extension packages using setuptools |
| `setuptools_rust_build` | `setuptools.build_meta` (when `setuptools-rust` is in `build-system.requires`) | Rust+Python packages using setuptools-rust |
| `meson_build` | `mesonpy` | Scientific packages (numpy, pandas, etc.) |
| `cmake_build` | `scikit_build_core.build`, `skbuild` | Packages using CMake/scikit-build |
| `maturin_build` | `maturin` | Rust+Python packages via maturin |

### Forcing a Package to Build from Source

By default, `rules_pycross` uses pre-built wheels when available. To force building from source, set `always_build = True`:

```python
uv.package(
    name = "numpy",
    always_build = True,
    workspace = "pypi",
)
```

### Extra Build Tools

When building a package from source, `rules_pycross` automatically includes the `build-system.requires` packages from the sdist's `pyproject.toml`. If a package needs additional Python packages at build time (e.g., `cython`, `numpy`, `setuptools-scm`), declare them with `extra_build_tools`:

```python
uv.package(
    name = "pandas",
    extra_build_tools = ["cython@0.29.36", "numpy@1.26.4"],
    workspace = "pypi",
)
```

These package keys must match entries in the lock file. Only packages that aren't already runtime dependencies are added as build-only deps.

#### Custom Build Tools Repository

By default, build tools are resolved from the internal `<workspace>__build` repository. If a specific package needs to resolve its build dependencies from a different repository, you can specify `build_tools_repo` in its `package()` annotation:

```python
uv.package(
    name = "my-complex-package",
    build_tools_repo = "my_custom_build_deps",
    workspace = "pypi",
)
```

#### Default Extra Build Tools

Use `name = "*"` to set default extra build tools for all packages in a workspace. A specific `extra_build_tools` on an individual package fully replaces the wildcard:

```python
# Default: every sdist build gets cython available
uv.package(
    name = "*",
    extra_build_tools = ["cython@0.29.36"],
    workspace = "pypi",
)

# numpy gets its own specific set instead
uv.package(
    name = "numpy",
    extra_build_tools = ["cython@0.29.36", "oldest-supported-numpy@0.9"],
    workspace = "pypi",
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
uv.package(
    name = "rpds-py",
    always_build = True,
    workspace = "pypi",
)
uv.package(
    name = "jiter",
    always_build = True,
    workspace = "pypi",
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
uv.package(
    name = "psycopg2",
    build_target = "@//deps/psycopg2:wheel",
    workspace = "pypi",
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

### Platform Transitions

When a workspace member needs to be built under a specific platform configuration—for example, to pin a variant flag or target a particular architecture—you can declare a platform transition on the member import. This causes all proxy targets in the thin repo to apply a Bazel `--platforms` transition, ensuring the backing workspace targets are analyzed under the specified platform.

There are three ways to specify the transition:

**1. Using `flags` — embed `--flag=value` settings into a generated platform:**

```python
uv.repo(
    workspace = "shared",
    name = "ml-pipeline",
    flags = [
        "--@pypi//_variants:extra_cu124=True",
    ],
)
```

**2. Using `constraint_values` — generate a platform with specific constraints:**

```python
uv.repo(
    workspace = "shared",
    name = "ml-pipeline",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)
```

**3. Using `platform` — reference an existing platform target directly:**

```python
uv.repo(
    workspace = "shared",
    name = "ml-pipeline",
    platform = "@//platforms:linux_cuda",
)
```

> [!NOTE]
> `flags` and `constraint_values` can be combined (they are merged into a single generated platform), but `platform` is mutually exclusive with both.

These attributes are available on `uv.repo()` and its PDM/Poetry/Pylock equivalents.

When `constraint_values` alone are specified, `rules_pycross` generates an internal `platform()` target and uses `pycross_transitioning_library_proxy` / `pycross_transitioning_file_proxy` at each package level to apply the `--platforms` transition.

When `flags` are specified (with or without `constraint_values`), `rules_pycross` additionally generates a custom `_transition.bzl` in the thin repo. This is necessary because Bazel's `platform(flags=[...])` mechanism only applies during top-level platform mapping — it does **not** take effect when `--platforms` is set via a Starlark transition. The generated transition directly sets both `--platforms` and the individual flag values. Root-level targets become transitioning proxies so that `select()` expressions in per-package BUILD files resolve in the transitioned configuration where the flags are set.

This is particularly useful for locking variant selections to a member without requiring `--flag` arguments on every `bazel build` invocation.

---

## rules_python Compatibility

`rules_pycross` integrates with `rules_python`. The generated target layout (`@<repo>//<package>`) is compatible with `rules_python` conventions.

* **Venv support** — when `rules_python` venvs are enabled, `pycross_wheel_library` populates the symlinks needed for a correct `site-packages` layout. Auto-detected paths can be overridden via `uv.package(site_paths = [...])`, and additional path categories (`bin_paths`, `data_paths`, `include_paths`) are also supported.
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
