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

Add `rules_pycross` and your lock file import to `MODULE.bazel`:

```python
bazel_dep(name = "rules_pycross", version = "2.0.0")

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

Other lock formats work the same way via their respective extensions: `pdm.bzl`, `poetry.bzl`, or `pylock.bzl`. A `pylock.toml` without a dependency graph (as written by `pip lock` and `uv export`) is installed as a whole, like PEP 751 installers do: each pinned package depends on every locked package whose marker matches the target.

Building sdists that contain native code needs a registered C/C++ toolchain; use a hermetic one (e.g. [toolchains_llvm](https://github.com/bazel-contrib/toolchains_llvm)) for cross builds. BUILD files that use `py_binary`/`py_test` also need a `bazel_dep` on `rules_python`.

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

#### Package Indexes

Lock entries without a download URL (common with Poetry and PDM) are looked up by filename through the Simple Repository API (PEP 691/503), in the package's own index if the lock records one. Otherwise, set `pypi_indexes` on the `workspace()` tag to use other indexes; they are tried in order and default to PyPI:

```python
uv.workspace(
    name = "pypi",
    lock_file = "//:uv.lock",
    pypi_indexes = ["https://pypi.example.com/simple", "https://pypi.org/simple"],
)
```

#### The Internal Build Tools Repository (`__build`)

For every workspace, `rules_pycross` also auto-generates an internal companion repository named `<workspace>__build` (e.g., `@pypi__build`).

* **Purpose**: Provides build-time tools (like `setuptools`, `hatchling`, etc.) required to build source distributions (sdists) hermetically.
* **Content**: Includes all projects, all dependency groups and their transitive packages (`["*", "transitive"]`) from the workspace.

This repository is managed automatically. However, if you need to customize its settings (such as restricting its dependency groups), you can override it by explicitly declaring a repo with the `<workspace>__build` name:

```python
uv.repo(
    name = "pypi__build",
    dependency_groups = ["default", "group:build", "transitive"],
    workspace = "pypi",
)
```

An overridden build repo must still provide every package needed to build sdists (`build-system.requires`, backend tools, `extra_build_tools`), so keep `"transitive"` unless those are all pinned directly.

### Migrating from the legacy two-extension pattern

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
    build_mode = "always",  # was: always_build = True
    workspace = "pypi",  # was: repo = "pypi"
)
use_repo(uv, "pypi")
```

> [!TIP]
> 1.x-style labels such as `@pypi//:package_name` (with a colon) keep working: every generated repo also contains these root aliases.

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

The libc and macOS versions set the defaults of the `@rules_pycross//pycross/settings:glibc_version`, `musl_version` and `macos_version` flags, which can override them per build.

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
* `"*"` — all groups (default + all optional + all dependency groups)

The default is `["default"]`.

```python
uv.repo(
    dependency_groups = ["default", "optional:grpc", "group:test"],
    workspace = "pypi",
)
```

### Transitive Aliases

By adding `"transitive"` to `dependency_groups`, `rules_pycross` will generate aliases for all transitively resolved packages — not just those directly pinned by your selected groups. This lets you reference any package in the lock file via `@pypi//package_name`, even if it's only an indirect dependency.

```python
uv.repo(
    dependency_groups = ["default", "transitive"],
    workspace = "pypi",
)
```

If a transitive package has multiple versions in the lock file, the alias `select()`s between them when they belong to resolution-marker forks; otherwise `rules_pycross` prints a warning and aliases to the highest version.

> **Note:** `"transitive"` is a modifier, not a dependency group — it is _not_ included by the `*` wildcard. You must list it explicitly.

### Testonly Dependencies

Append `;testonly` to any group specifier to mark its packages as `testonly` in the generated Bazel targets. This is useful for test frameworks and other packages that should not be depended upon by production code:

```python
uv.repo(
    dependency_groups = ["default", "group:test;testonly"],
    workspace = "pypi",
)
```

Testonly packages are left out of `all_requirements` in the generated `requirements.bzl` and listed in `all_testonly_requirements` instead.

With `transitive;testonly`, `rules_pycross` performs reachability analysis to determine which transitive packages are **exclusively** reachable from testonly roots. Packages reachable from both testonly and non-testonly groups remain non-testonly:

```python
uv.repo(
    dependency_groups = ["default", "group:test;testonly", "transitive;testonly"],
    workspace = "pypi",
)
```

### Wildcards and Precedence

The `*` wildcard and `;testonly` modifier follow **last-wins** precedence. When `*` appears, it sets the default testonly status for all groups and resets any prior specific overrides. Specific entries after `*` override individual groups:

```python
# Everything testonly except group:dev
uv.repo(
    dependency_groups = ["*;testonly", "group:dev"],
    workspace = "pypi",
)

# Only group:test is testonly
uv.repo(
    dependency_groups = ["*", "group:test;testonly"],
    workspace = "pypi",
)

# group:dev;testonly is overridden by the later *
uv.repo(
    dependency_groups = ["group:dev;testonly", "*"],
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

`ignore_dependencies` and `extra_dependencies` drop or add runtime dependencies (as package keys) when a package's metadata is wrong. See the [API reference](docs/ext_uv.md) for all annotation fields.

Use `name = "*"` to set defaults for all packages. Fields left unset on a specific `package()` entry inherit the wildcard's value; fields set on it replace the wildcard's value:

```python
# Wheels only: never build sdists in this workspace
uv.package(
    name = "*",
    build_mode = "never",
    workspace = "shared",
)

# ...except for this package, which always builds from source
uv.package(
    name = "regex",
    build_mode = "always",
    workspace = "shared",
)

# ...and this one, which uses a wheel if one matches and builds otherwise
uv.package(
    name = "requests",
    build_mode = "auto",
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
| `pep517_build` | `hatchling.build`, `flit_core.buildapi`, `pdm.backend`, `poetry.core.masonry.api`, and any other backend | Pure-Python packages (default fallback) |
| `setuptools_build` | `setuptools.build_meta` | C extension packages using setuptools |
| `setuptools_rust_build` | `setuptools.build_meta` (when `setuptools-rust` is in `build-system.requires`) | Rust+Python packages using setuptools-rust |
| `meson_build` | `mesonpy` | Scientific packages (numpy, pandas, etc.) |
| `cmake_build` | `scikit_build_core.build` | Packages using CMake/scikit-build-core |
| `maturin_build` | `maturin` | Rust+Python packages via maturin |

### Choosing Between Wheels and Sdists

`package(build_mode = ...)` controls whether a package is built from source:

* `auto` (default): use a matching pre-built wheel if there is one; otherwise build the sdist.
* `always`: always build from source.
* `never`: never build the sdist. Building fails if no wheel matches. A `build_target` is still used.

Set it on `name = "*"` to apply it to a whole workspace (for example, `build_mode = "never"` for wheels-only).

```python
uv.package(
    name = "numpy",
    build_mode = "always",
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

By default, build tools are resolved from the internal `<workspace>__build` repository. If a specific package needs to resolve its build dependencies from a different repository (declared with the same extension), you can specify `build_tools_repo` in its `package()` annotation:

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

When packages need native dependencies, compiler flags, environment variables, or other build customizations, use the backend-specific override extensions. `name` is a package name, `name@version` (for one locked version, e.g. one side of a fork), or `"*"` for all packages built with that backend. For a given package, matching entries are layered from least to most specific: `*`, then `name`, then `name@version`. Each field set on a more specific entry replaces the less specific value.

#### Setuptools

```python
setuptools = use_extension("@rules_pycross//pycross/backends:setuptools.bzl", "setuptools")

setuptools.override(
    name = "psycopg2",
    workspace = "pypi",
    copts = ["-O2"],
    path_tools = ["//deps/psycopg2:pg_config_tool"],
    build_env = {"LDFLAGS": "-L/usr/lib"},
)
```

`path_tools` puts binaries on `PATH` under their basename. To use a different name, wrap the binary in `pycross_path_tool`:

```python
# deps/psycopg2/BUILD.bazel
load("@rules_pycross//pycross:defs.bzl", "pycross_path_tool")

pycross_path_tool(
    name = "pg_config_tool",
    executable_name = "pg_config",
    tool = "//third_party/postgresql:pg_config_bin",
)
```

`tool_deps` replaces the Python tool packages the backend adds to every build (for setuptools: `setuptools` and `wheel`; for cmake: `cmake`, `ninja` and `scikit-build-core`). Keys are tool package names; other tools keep their defaults:

```python
cmake = use_extension("@rules_pycross//pycross/backends:cmake.bzl", "cmake")

cmake.override(
    name = "*",
    workspace = "pypi",
    tool_deps = {"cmake": "@other_deps//cmake:pkg"},
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
bazel_dep(name = "rules_pycross_backend_maturin", version = "2.0.0")
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
    build_mode = "always",
    workspace = "pypi",
)
uv.package(
    name = "jiter",
    build_mode = "always",
    workspace = "pypi",
)

# Provide a Cargo.lock for jiter (when the sdist doesn't include one)
maturin = use_extension("@rules_pycross_backend_maturin//extensions:maturin.bzl", "maturin")
maturin.override(
    name = "jiter",
    workspace = "pypi",
    cargo_lock = "//:jiter.lock",
)
```

To generate a Cargo.lock for an overridden package, run `bazel run @pypi//_cargo:jiter@<version>`.

> [!NOTE]
> When cross-compiling Rust packages (`maturin_build` or `setuptools_rust_build` with a target triple that differs from the exec platform), cargo builds build scripts and proc-macros for the exec platform and links them with the system `cc` found on `PATH`, not the Bazel C/C++ toolchain. The exec host (or remote execution image) needs a working C toolchain for these builds.

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
3. **`select()` expressions** on the package aliases — so `@<repo>//torch` resolves to the correct version based on which flag is set.

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

When a workspace member needs to be built under a specific configuration—for example, to pin a variant flag or target a particular architecture—you can declare a transition on its `repo()` tag. All proxy targets in the thin repo then apply a Bazel transition, so the backing workspace targets are analyzed under the specified platform and flags.

There are three ways to specify the transition:

**1. Using `flags` — pin `--flag=value` settings for the repo's targets:**

```python
uv.repo(
    workspace = "shared",
    name = "ml-pipeline",
    flags = [
        "--@ml-pipeline//_variants:extra_cu124=True",
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
> `flags`, `settings` and `constraint_values` can be combined, but `platform` is mutually exclusive with all of them. With `flags`/`settings` alone, the incoming `--platforms` is kept.

These attributes are available on `uv.repo()` and its PDM/Poetry/Pylock equivalents.

When `constraint_values` are specified, `rules_pycross` generates an internal `platform()` target and uses `pycross_transitioning_library_proxy` / `pycross_transitioning_file_proxy` at each package level to apply the `--platforms` transition.

When `flags` or `settings` are specified, `rules_pycross` additionally generates a custom `_transition.bzl` in the thin repo. This is necessary because Bazel's `platform(flags=[...])` mechanism only applies during top-level platform mapping — it does **not** take effect when `--platforms` is set via a Starlark transition. The generated transition directly sets the individual flag values (and `--platforms`, when `constraint_values` are given). Root-level targets become transitioning proxies so that `select()` expressions in per-package BUILD files resolve in the transitioned configuration where the flags are set.

Each `flags` entry is written like a command-line flag, `--<flag>[=<value>]` (a missing value means `True`):

* Built-in options use their plain names, e.g. `--compilation_mode=opt` or `--copt=-O2`.
* Repeat an entry to pass multiple values to a list setting such as `--copt`; each entry is one element (values are not split on commas).
* Labels are resolved from inside the generated repo: use `@<repo>//...` for generated repos such as `@ml-pipeline//_variants:...`. In the root module, `//pkg:flag` and `:flag` refer to your main repository. Other `@repo` labels must be visible to `rules_pycross`.
* `--platforms` is not allowed; use `platform` or `constraint_values`.

`settings` takes build-setting labels keyed to their values, resolved from the module that declares the repo:

```python
uv.repo(
    workspace = "shared",
    name = "ml-pipeline",
    flags = ["--compilation_mode=opt"],
    settings = {"@my_flags//:level": "2"},
)
```

Use `flags` for built-in options and labels `rules_pycross` can see (such as its generated repos), and `settings` for build settings from your own or other modules; list-valued settings split on commas.

This is particularly useful for locking variant selections to a member without requiring `--flag` arguments on every `bazel build` invocation.

The transition applies to the repo's whole closure, including sdist builds from the workspace: these read the configured `--copt`/`--linkopt`/`--compilation_mode`, so such flags reach native compiles. Each transitioned repo therefore builds its sdists in a separate configuration, with no sharing with the untransitioned build.

---

## Handling Unavailable Packages

A package is unavailable in the selected target environment when it has no compatible wheel (and no sdist to fall back to), when no resolution-marker fork matches, or when the selected conflict variant doesn't include it. (Selecting no variant from a conflict set that has no default is still an analysis error; see [Default Groups](#default-groups).) The `--@rules_pycross//pycross/settings:unavailable_package_mode` flag controls how such packages behave:

* **`incompatible` (default)** — unavailable packages are marked [incompatible](https://bazel.build/extending/platforms#skipping-incompatible-targets): targets that depend on them are skipped by `bazel build //...` and `bazel test //...`, and fail analysis when requested explicitly. (`all_requirements` and other platform-conditional `:maybe` aggregates exclude such packages instead.)
* **`fail_at_execution`** — unavailable packages analyze successfully and provide the usual providers (`PyInfo`, etc.), registering an action that fails only when executed. Building anything that actually needs the package fails with a `No compatible wheel is available ...` error.

`fail_at_execution` is useful when running consumers that only *analyze* dependencies—such as type-checking aspects that attach stub packages via implicit attributes, which otherwise see a target without the usual providers and fail even when the package is never built—or when you want wildcard `bazel build //...` / `bazel test //...` runs to fail loudly instead of silently skipping targets with unavailable dependencies:

```
# .bazelrc
common --@rules_pycross//pycross/settings:unavailable_package_mode=fail_at_execution
```

> [!WARNING]
> Under `unavailable_package_mode=fail_at_execution`, unavailable packages are no longer incompatible, so `bazel build //...` and `bazel test //...` will **fail** (rather than skip) targets that depend on a package unavailable for the current platform or Python version. If you rely on incompatible-target skipping for normal builds, scope the setting to a config instead (e.g. `common:typecheck --@rules_pycross//pycross/settings:unavailable_package_mode=fail_at_execution`, used with `--config=typecheck`).

Set the flag with `common` rather than `build` so that `build`, `test`, and `cquery` share a configuration; changing a build setting between commands discards Bazel's analysis cache.

Independently of this setting, sdist builds whose configuration is known to be broken at analysis time (e.g. `build-system.requires` packages missing from the lock file, or no `meson`/`cmake`/`ninja`/`maturin` in `tool_deps`) always analyze successfully and fail at execution with `Cannot build <sdist file> from source: ...`. This keeps aspects and `cquery` working on platforms where such a package would fall back to a source build that is never actually run.

---

## rules_python Compatibility

`rules_pycross` integrates with `rules_python`. The generated target layout (`@<repo>//<package>`) is compatible with `rules_python` conventions.

* **Venv support** — when `rules_python` venvs are enabled, `pycross_wheel_library` populates the symlinks needed for a correct `site-packages` layout. Auto-detected paths can be overridden via `uv.package(site_paths = [...])`, and additional path categories (`bin_paths`, `data_paths`, `include_paths`) are also supported.
* **`.pyc` precompilation** — setting `--@rules_python//python/config_settings:precompile=enabled` (or `force_enabled`) or `package(precompile = "enabled")` (on individual packages or `name = "*"`; default `"auto"` follows the flag) precompiles `.py` files in installed wheels during the install action for faster cold startup, using the target Python version's interpreter from the registered `pycross` toolchain. Like `rules_python`, `force_enabled`/`force_disabled` override per-package settings, the `.pyc` invalidation mode follows `--compilation_mode` (`unchecked_hash` under `opt`, `checked_hash` otherwise), and `.py` sources are always kept (a binary's `pyc_collection` attribute does not apply to installed wheels). Note for cache-sensitive builds: precompiled wheel installs are keyed per Python version (whereas uncompiled pure-Python wheel installs are shared across versions), staging part of the interpreter as action inputs means an interpreter patch release re-runs compiled installs, and setting `package(precompile = "enabled")` on specific large packages limits that overhead to those packages.
* **`py_console_script_binary`** — each generated package has a `@<repo>//<package>:dist_info` target for entry point discovery. Use `py_console_script_binary(pkg = "@pypi//cython", script = "cython")` directly.
* **`:data`** — `@<repo>//<package>:data` aliases `:pkg` for `rules_python` label compatibility; the installed wheel directory (with `bin/`, `data/` and `include/`) and its runfiles come with it.

---

## Gazelle Integration

`rules_pycross` is compatible with `rules_python_gazelle_plugin`. The target layout (`@<repo>//<package>`) matches the plugin's default label conventions, so no `gazelle:python_label_convention` directives are needed.

Each generated repo provides a `:modules_mapping` target, built by the `pycross_modules_mapping` rule from package metadata at build time — wheels do not need to be downloaded or extracted during analysis. It covers every pinned package, including testonly ones.

```python
load("@gazelle//:def.bzl", "gazelle")
load("@rules_python_gazelle_plugin//manifest:defs.bzl", "gazelle_python_manifest")

gazelle_python_manifest(
    name = "gazelle_python_manifest",
    modules_mapping = "@pypi//:modules_mapping",
    pip_repository_name = "pypi",
)

# gazelle:python_extension enabled
# gazelle:python_root //
gazelle(
    name = "gazelle",
    gazelle = "@rules_python_gazelle_plugin//python:gazelle_binary",
)
```

To map a custom set of packages, use `pycross_modules_mapping(deps = ...)` from `@rules_pycross//pycross:defs.bzl` (set `testonly = True` if `deps` include `all_testonly_requirements`).

```bash
> bazel run //:gazelle_python_manifest.update  # Update gazelle_python.yaml
> bazel run //:gazelle                          # Apply BUILD file changes
```

---

See the [API reference docs](docs/) and [e2e tests](tests/e2e/) for more examples.
