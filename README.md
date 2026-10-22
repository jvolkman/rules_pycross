# `rules_pycross` — Python + cross platform

`rules_pycross` lets you use Python lock files with Bazel, enabling cross-platform, hermetic builds of Python dependencies — including native extensions.

> [!NOTE]
> 2.0 is a major overhaul of `rules_pycross` ([#243](https://github.com/jvolkman/rules_pycross/pull/243)); see the
> [CHANGELOG](CHANGELOG.md) for breaking changes and [Migrating from 1.x](#migrating-from-1x) below. The 1.x line lives on the [v1](https://github.com/jvolkman/rules_pycross/tree/v1) branch.

### Features

* Import lock files from **uv**, **PDM**, **Poetry**, or **PEP 751 `pylock.toml`**
* Build source distributions inside sandboxed Bazel build actions, not during workspace initialization
* Pluggable build backends: setuptools, meson, cmake, maturin, setuptools-rust, and generic PEP 517
* Cross-platform sdist builds — build wheels for Linux and macOS from either host with a hermetic cross-compilation toolchain ([hermetic-llvm](https://github.com/hermeticbuild/hermetic-llvm), BCR module `llvm`)
* Multi-workspace support for monorepos with shared dependency deduplication
* Conflict/variant resolution for mutually exclusive dependencies (e.g., `torch` CPU vs. CUDA)
* Compatible with `rules_python` and Gazelle

**Platform support:** Linux and macOS are the primary supported platforms ([CI results](https://github.com/jvolkman/rules_pycross/actions/workflows/ci.yml)). Windows may work for some use cases but is not tested.

### Contents

* [Quickstart](#quickstart)
* [Generated Repositories & Targets](#generated-repositories--targets)
* [Workspaces, Monorepos & Package Configuration](#workspaces-monorepos--package-configuration)
* [Building from Source (Sdists & Native Extensions)](#building-from-source-sdists--native-extensions)
* [Variants, Transitions & Unavailable Packages](#variants-transitions--unavailable-packages)
* [`rules_python` & Gazelle Integration](#rules_python--gazelle-integration)
* [Toolchains, Architecture & Migration](#toolchains-architecture--migration)

---

## Quickstart

### 1. Import a Lock File in `MODULE.bazel`

Add `rules_pycross` and your lock file extension to `MODULE.bazel`:

```python
bazel_dep(name = "rules_pycross", version = "2.0.0")
bazel_dep(name = "rules_python", version = "1.4.1")

uv = use_extension("@rules_pycross//pycross/extensions:uv.bzl", "uv")
uv.workspace(
    name = "pypi",
    lock_file = "//:uv.lock",
)
use_repo(uv, "pypi")
```

For a single-project lock file, `uv.workspace()` automatically discovers your `pyproject.toml` and creates a `@pypi` repository containing the project's `"default"` dependency group. To customize which dependency groups or workspace members are included, add a `uv.repo()` tag:

```python
uv.repo(
    dependency_groups = ["default", "optional:grpc", "group:test;testonly"],
    workspace = "pypi",
)
```

Other lock formats use the same `workspace()` / `repo()` / `package()` API via their respective extensions:

| Lock format | Extension Bzl file | Tag name | Notes |
|---|---|---|---|
| **uv** (`uv.lock`) | `@rules_pycross//pycross/extensions:uv.bzl` | `uv` | Supports workspace members and conflict variants |
| **PDM** (`pdm.lock`) | `@rules_pycross//pycross/extensions:pdm.bzl` | `pdm` | Looks up missing wheel URLs via Simple API |
| **Poetry** (`poetry.lock`) | `@rules_pycross//pycross/extensions:poetry.bzl` | `poetry` | Looks up missing wheel URLs via Simple API |
| **PEP 751** (`pylock.toml`) | `@rules_pycross//pycross/extensions:pylock.bzl` | `pylock` | Graphless locks (from `pip lock` / `uv export`) install all marker-matching packages as a unit |

### 2. Use Dependencies in `BUILD.bazel`

Reference packages directly as `@pypi//<package_name>` (with hyphens normalized to underscores) or via the generated `requirement()` macro:

```python
load("@pypi//:requirements.bzl", "requirement")
load("@rules_python//python:defs.bzl", "py_binary")

py_binary(
    name = "app",
    srcs = ["app.py"],
    deps = [
        "@pypi//requests",
        "@pypi//google_api_core:[grpc]",
        # Or with requirement():
        requirement("google-api-core[grpc]"),
    ],
)
```

### 3. (Optional) Register a C/C++ Toolchain for Native Builds

Building source distributions (sdists) with C/C++ extensions requires a registered C/C++ toolchain. For hermetic native and cross-platform builds, use [hermetic-llvm](https://github.com/hermeticbuild/hermetic-llvm) (BCR module `llvm`):

```python
bazel_dep(name = "llvm", version = "0.8.24")

register_toolchains("@llvm//toolchain:all")
```

Then build for any target platform with `--platforms=@llvm//platforms:linux_aarch64` or `--platforms=@llvm//platforms:macos_aarch64`.

---

## Generated Repositories & Targets

### Target Layout

Each generated repository (e.g., `@pypi`) exposes the following targets:

| Target | Description |
|---|---|
| `@pypi//<pkg>` (or `:pkg`) | Installed wheel as a `py_library`-compatible target (includes any requested extras) |
| `@pypi//<pkg>:[]` | Base package only, without extra dependencies (generated when extras are used) |
| `@pypi//<pkg>:[<extra>]` | Specific extra and its dependencies |
| `@pypi//<pkg>:dist_info` | `.dist-info` directory (for `py_console_script_binary`) |
| `@pypi//<pkg>:data` | Alias for `:pkg` (`rules_python` compatibility; includes `bin/`, `data/`, and `include/`) |
| `@pypi//<pkg>:wheel` | The `.whl` file (downloaded or built from source) |
| `@pypi//<pkg>:sdist` | The source distribution archive (when present in the lock file) |
| `@pypi//:requirements.bzl` | Exports `requirement()`, `all_requirements`, and `all_testonly_requirements` |
| `@pypi//:modules_mapping` | Import-to-package mapping for [Gazelle](#gazelle-integration) |
| `@pypi//:<pkg>` | Legacy 1.x root-package alias for `@pypi//<pkg>` |

### Extras

When a dependency is used with extras (e.g., `google-api-core[async_rest,grpc]`), `rules_pycross` generates separate targets for the base package and each extra (`@pypi//google_api_core:[]`, `@pypi//google_api_core:[async_rest]`, `@pypi//google_api_core:[grpc]`), while `@pypi//google_api_core` includes all requested extras. Both label syntax and `requirement("google-api-core[grpc]")` work interchangeably.

### Dependency Groups & `testonly`

The `dependency_groups` attribute on `repo()` controls which groups from `pyproject.toml` are exposed (default: `["default"]`):

| Specifier | Meaning |
|---|---|
| `"default"` | `[project.dependencies]` |
| `"optional:<name>"` / `"optional:*"` | Specific or all `[project.optional-dependencies]` |
| `"group:<name>"` / `"group:*"` | Specific or all `[dependency-groups]` (PEP 735) |
| `"*"` | All groups (`default` + all `optional:*` + all `group:*`) |
| `"transitive"` | Modifier: also generate top-level `@pypi//<pkg>` aliases for indirect dependencies (not included by `"*"`) |
| `<specifier>;testonly` | Modifier: mark packages from `<specifier>` as `testonly = True` |

```python
uv.repo(
    dependency_groups = [
        "default",
        "optional:grpc",
        "group:test;testonly",
        "transitive;testonly",
    ],
    workspace = "pypi",
)
```

#### Rules for `transitive` and `;testonly`

* **Testonly exports:** Testonly packages are excluded from `all_requirements` in `requirements.bzl` and placed in `all_testonly_requirements` instead.
* **`transitive;testonly` reachability:** Marks a transitive package `testonly` only if it is **exclusively** reachable from testonly roots. Packages shared with non-testonly groups remain non-testonly.
* **Multiple versions under `transitive`:** If a transitive package has multiple locked versions, the alias `select()`s between them when they belong to resolution-marker forks; otherwise `rules_pycross` warns and aliases the highest version.
* **Last-wins precedence:** `"*"` sets the default testonly status for all groups and resets prior overrides; entries after `"*"` override individual groups (e.g., `["*;testonly", "group:dev"]` marks everything testonly except `group:dev`).

---

## Workspaces, Monorepos & Package Configuration

### Workspace Settings (`workspace()`)

* **Project file discovery (`extra_project_files`):** `rules_pycross` auto-discovers `pyproject.toml` files from workspace members in the lock file (or next to the lock file for standalone locks). To append additional `pyproject.toml` files containing build settings or dependency definitions:

  ```python
  uv.workspace(
      name = "pypi",
      lock_file = "//:uv.lock",
      extra_project_files = ["//:pyproject.toml", "//tools:pyproject.toml"],
  )
  ```

* **Custom package indexes (`pypi_indexes`):** Lock entries without a download URL (common with Poetry and PDM) are looked up via the Simple Repository API (PEP 503/691) in the package's recorded index, or in `pypi_indexes` (tried in order, defaulting to PyPI):

  ```python
  uv.workspace(
      name = "pypi",
      lock_file = "//:uv.lock",
      pypi_indexes = ["https://pypi.example.com/simple", "https://pypi.org/simple"],
  )
  ```

### Multi-Project Workspaces & Monorepos

All `repo()` definitions linked to the same `workspace` share a single backing repository—overlapping packages are downloaded and built only once.

```python
uv = use_extension("@rules_pycross//pycross/extensions:uv.bzl", "uv")

# 1. Declare the shared workspace lock file
uv.workspace(
    name = "shared",
    lock_file = "//:uv.lock",
)

# Option A: Import all workspace members into a single repo
uv.repo(
    name = "lock_all",
    projects = ["*"],
    workspace = "shared",
)

# Option B: Create separate repos per member with different dependency groups
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
use_repo(uv, "lock_all", "lock_a", "lock_b")
```

If subprojects use **separate, independent lock files**, declare separate `uv.workspace()` tags instead.

### Package Annotations (`package()`)

Use `uv.package()` (or `pdm.package()`, `poetry.package()`, `pylock.package()`) to customize how individual packages—or all packages via `name = "*"`—are built or installed in a workspace. The `workspace` attribute can be omitted if your module declares only one workspace.

```python
# Set workspace-wide defaults with name = "*"
uv.package(
    name = "*",
    build_mode = "never",  # Wheels only by default
    workspace = "pypi",
)

# Override specific packages (unset fields inherit from "*")
uv.package(
    name = "regex",
    build_mode = "always",
    install_exclude_globs = ["test_regex.py"],
    workspace = "pypi",
)
```

Common `package()` attributes (see the [full `uv.package` reference](docs/ext_uv.md#uv.package)):

| Attribute | Purpose |
|---|---|
| `build_mode` | `"auto"` (wheel if available, else sdist), `"always"` (build from source), or `"never"` (wheels only) |
| `extra_build_tools` | Additional locked package keys (`name@version`) needed when building from source |
| `extra_dependencies` / `ignore_dependencies` | Add or drop runtime dependencies (as package keys) when upstream metadata is incomplete or broken |
| `pre_build_patches` / `post_install_patches` | Patch files applied to the sdist before building or to the wheel after installing |
| `install_exclude_globs` | Glob patterns of files to remove during wheel installation |
| `precompile` | `"auto"` (default), `"enabled"`, or `"disabled"` for `.pyc` precompilation |
| `site_paths`, `bin_paths`, `data_paths`, `include_paths` | Override auto-detected wheel directory paths |
| `build_target` / `build_backend` | Custom wheel build target or explicit backend rule name |

---

## Building from Source (Sdists & Native Extensions)

`rules_pycross` detects each sdist's build backend from `build-system.build-backend` in its `pyproject.toml` and builds wheels inside sandboxed Bazel actions.

### Supported Build Backends

| Backend Rule | Detected from `build-backend` | Typical Use Case |
|---|---|---|
| `pep517_build` | `hatchling.build`, `flit_core.buildapi`, `pdm.backend`, `poetry.core.masonry.api`, or any unknown backend | Pure-Python packages (default fallback) |
| `setuptools_build` | `setuptools.build_meta` | C/C++ extension packages using setuptools |
| `setuptools_rust_build` | `setuptools.build_meta` (with `setuptools-rust` in `build-system.requires`) | Rust + Python packages using `setuptools-rust` |
| `meson_build` | `mesonpy` | Scientific packages (`numpy`, `scipy`, `pandas`, etc.) |
| `cmake_build` | `scikit_build_core.build` | C/C++ packages using CMake / `scikit-build-core` |
| `maturin_build` | `maturin` | Rust + Python packages via `maturin` |

### Build Dependencies (`extra_build_tools` & `__build`)

When building an sdist, `rules_pycross` automatically includes the `build-system.requires` packages declared in the sdist's `pyproject.toml`. If a package needs undeclared Python packages at build time (such as `cython`, `numpy`, or `setuptools-scm`), add them with `extra_build_tools`:

```python
# Optional: provide cython to all sdist builds by default
uv.package(
    name = "*",
    extra_build_tools = ["cython@0.29.36"],
    workspace = "pypi",
)

# Specific extra_build_tools on a package replaces the "*" list
uv.package(
    name = "pandas",
    extra_build_tools = ["cython@0.29.36", "numpy@1.26.4"],
    workspace = "pypi",
)
```

> [!NOTE]
> **How build tools are resolved (`<workspace>__build`):** For every workspace, `rules_pycross` auto-generates an internal companion repo named `<workspace>__build` (e.g., `@pypi__build`) with `dependency_groups = ["*", "transitive"]` to supply build-time tools (`setuptools`, `hatchling`, etc.).
>
> * To restrict which groups are included in `@pypi__build`, declare `uv.repo(name = "pypi__build", workspace = "pypi", dependency_groups = ["default", "group:build", "transitive"])`.
> * To resolve a specific package's build dependencies from another repo created by the same extension, set `uv.package(name = "pkg", build_tools_repo = "other_repo")`.

### Backend Overrides

Use backend-specific override extensions to pass compiler flags (`copts`, `linkopts`), environment variables (`build_env`), native C/C++ dependencies (`native_deps`), or `PATH` binaries (`path_tools`).

`name` accepts `"*"` (all packages on that backend), a package name, or `name@version` (a specific locked version). Matching overrides layer from least to most specific (`*` $\rightarrow$ `name` $\rightarrow$ `name@version`), with set fields replacing less specific ones.

#### Setuptools & `pycross_path_tool`

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

`path_tools` places binaries on `PATH` under their basename. To expose a binary under a different name, wrap it in `pycross_path_tool`:

```python
# deps/psycopg2/BUILD.bazel
load("@rules_pycross//pycross:defs.bzl", "pycross_path_tool")

pycross_path_tool(
    name = "pg_config_tool",
    executable_name = "pg_config",
    tool = "//third_party/postgresql:pg_config_bin",
)
```

#### Customizing Backend `tool_deps` (e.g., CMake)

`tool_deps` replaces specific Python tool packages that a backend injects into every build (e.g., `setuptools`/`wheel` for setuptools; `cmake`/`ninja`/`scikit-build-core` for cmake):

```python
cmake = use_extension("@rules_pycross//pycross/backends:cmake.bzl", "cmake")
cmake.override(
    name = "*",
    workspace = "pypi",
    tool_deps = {"cmake": "@other_deps//cmake:pkg"},
)
```

#### Maturin & Rust Packages

Use the `rules_pycross_backend_maturin` module alongside `rules_rust`:

```python
bazel_dep(name = "rules_pycross_backend_maturin", version = "2.0.0")
bazel_dep(name = "rules_rust", version = "0.68.0")

rust = use_extension("@rules_rust//rust:extensions.bzl", "rust")
rust.toolchain(
    edition = "2021",
    extra_target_triples = [
        "aarch64-apple-darwin",
        "aarch64-unknown-linux-gnu",
        "x86_64-unknown-linux-gnu",
    ],
)

uv.package(
    name = "jiter",
    build_mode = "always",
    workspace = "pypi",
)

# Provide a Cargo.lock when the sdist does not ship one
maturin = use_extension("@rules_pycross_backend_maturin//extensions:maturin.bzl", "maturin")
maturin.override(
    name = "jiter",
    workspace = "pypi",
    cargo_lock = "//:jiter.lock",
)
```

To generate a `Cargo.lock` for an overridden package, run `bazel run @pypi//_cargo:jiter@<version>`.

> [!NOTE]
> When cross-compiling Rust packages (`maturin_build` or `setuptools_rust_build`), Cargo compiles build scripts and proc-macros for the exec platform using the host `cc` on `PATH` rather than the Bazel C/C++ toolchain. Ensure the exec host (or remote execution container) has a working C compiler.

#### Custom Build Targets (e.g., Meson with `pycross_cc_pkg_config`)

For full control over a package's wheel build, define a custom target in a `BUILD.bazel` file and point `uv.package(build_target = ...)` at it:

```python
# MODULE.bazel
uv.package(
    name = "numpy",
    build_target = "@//deps/numpy:wheel",
    workspace = "pypi",
)
```

```python
# deps/numpy/BUILD.bazel
load("@pypi//_backend:meson_build.bzl", "meson_build")
load("@rules_pycross//pycross:defs.bzl", "pycross_cc_pkg_config")

# Generate a pkg-config .pc file so meson can discover a Bazel cc_library
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

---

## Variants, Transitions & Unavailable Packages

### Conflict & Variant Resolution (`uv` Conflicts)

When a project defines mutually exclusive dependency sets in `pyproject.toml` (such as CPU vs. CUDA `torch`), `rules_pycross` maps `uv`'s `conflicts` declarations to Bazel build flags:

```toml
# pyproject.toml
[project.optional-dependencies]
cpu = ["torch==2.6.0"]
cu124 = ["torch==2.7.0"]

[tool.uv]
conflicts = [
  [{ extra = "cpu" }, { extra = "cu124" }],
]
```

Conflicts on `[dependency-groups]` (`{ group = "test-fast" }`) work the same way. For each conflict member, `rules_pycross` generates a `bool_flag` under `@<repo>//_variants:` (`extra_<name>` or `group_<name>`) and wires `@<repo>//<pkg>` through a `select()`.

Select a variant via CLI flag or a `platform()` definition:

```bash
bazel build //my:target --@pypi//_variants:extra_cu124=True
```

```python
platform(
    name = "linux_cuda",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    flags = ["--@pypi//_variants:extra_cu124=True"],
)
```

* **Default variants:** If `uv`'s `default-groups` includes a conflicted group, that variant becomes the `select()` default when no flag is set. Conflicted extras never have a default—building without selecting one fails with an error naming the `@<repo>//_variants:` flags to set.

### Repository Platform & Flag Transitions

To pin a variant flag, compilation option, or target architecture on a generated repo without passing `--flag` on every `bazel build` command, configure a transition on `repo()`:

```python
uv.repo(
    name = "ml-pipeline",
    workspace = "shared",
    # Pin command-line flags or generated variant flags:
    flags = [
        "--@ml-pipeline//_variants:extra_cu124=True",
        "--compilation_mode=opt",
    ],
    # Pin custom Starlark build settings from your module or other modules:
    settings = {
        "@my_flags//:level": "2",
    },
    # Optionally pin target platform constraints:
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)
```

Or transition directly to an existing `platform()` target (mutually exclusive with `flags`, `settings`, and `constraint_values`):

```python
uv.repo(
    name = "ml-pipeline",
    workspace = "shared",
    platform = "@//platforms:linux_cuda",
)
```

| Attribute | Accepts | Notes |
|---|---|---|
| `flags` | `["--<flag>[=<value>]"]` | Built-in Bazel options (`--copt=-O2`) and labels visible to `rules_pycross` (such as `@<repo>//_variants:...`). Repeat entries for list flags (no comma splitting). |
| `settings` | `{label: "value"}` | Starlark build-setting labels resolved from the declaring module. List settings split on commas. |
| `constraint_values` | `[constraint_value, ...]` | Generates an internal platform with the given constraints. Combinable with `flags` and `settings`. |
| `platform` | `Label` | Existing `platform()` target. Cannot be combined with `flags`, `settings`, or `constraint_values`. |

The transition applies to the repo's entire dependency closure, including sdist builds (which inherit transitioned `--copt`, `--linkopt`, and `--compilation_mode` flags in their own configuration).

### Handling Unavailable Packages

A package is unavailable in the target environment when no compatible wheel or sdist exists, no resolution-marker fork matches, or the active conflict variant excludes it. Control how unavailable packages behave with `--@rules_pycross//pycross/settings:unavailable_package_mode`:

| Mode | Behavior | When to Use |
|---|---|---|
| `incompatible` *(default)* | Marks unavailable targets `@platforms//:incompatible`. `bazel build //...` and `bazel test //...` skip dependents; explicit target builds fail at analysis. (`all_requirements` excludes them automatically.) | Standard multi-platform builds relying on Bazel target skipping. |
| `fail_at_execution` | Unavailable targets analyze normally (providing `PyInfo`, etc.) and register an action that fails only if executed. | Running analysis-only aspects (such as type-checking aspects attaching stub packages) or forcing `bazel test //...` to fail loudly instead of skipping targets. |

```ini
# .bazelrc — scope to a config if normal builds rely on target skipping,
# or use `common` so build, test, and cquery share the analysis cache:
common:typecheck --@rules_pycross//pycross/settings:unavailable_package_mode=fail_at_execution
```

> [!NOTE]
> Sdist builds with broken build configurations (e.g., `build-system.requires` missing from the lock file or missing backend tools) always analyze cleanly and fail at execution time, regardless of `unavailable_package_mode`, so `cquery` and aspects continue to work on platforms that never execute the source build.

---

## `rules_python` & Gazelle Integration

### `rules_python` Compatibility

Generated repositories follow `rules_python` conventions (`@<repo>//<package>`) and work directly with standard `py_binary`, `py_test`, and `py_library` rules.

#### Virtual Environments (`venvs_site_packages=yes`)

When `rules_python` virtual environments are enabled (`venvs_site_packages=yes`), `pycross_wheel_library` populates `.venv` symlinks for a standard `site-packages` layout and omits per-wheel `site-packages` entries from `sys.path`.

* **Shared namespace packages:** PEP 420, `pkgutil`-style, and `nvidia.*` namespace packages are linked per subpackage so multiple wheels sharing a namespace do not collide.
* **Customizing wheel paths:** Override auto-detected paths via `uv.package(site_paths = [...])` (as well as `bin_paths`, `data_paths`, and `include_paths`).

#### `.pyc` Precompilation

Precompile `.py` files during wheel installation for faster cold startup—either per package or globally via `rules_python`'s flag:

```python
# Enable on specific large packages (or name = "*" for all packages)
uv.package(
    name = "scipy",
    precompile = "enabled",  # "auto" (default), "enabled", or "disabled"
    workspace = "pypi",
)
```

```ini
# Or enable globally in .bazelrc
build --@rules_python//python/config_settings:precompile=enabled
```

* `force_enabled` and `force_disabled` on `--@rules_python//python/config_settings:precompile` override per-package settings.
* `.pyc` invalidation mode follows `--compilation_mode` (`unchecked_hash` under `opt`, `checked_hash` otherwise), and `.py` sources are always kept in installed wheels (`pyc_collection` on binaries does not strip wheel `.py` files).
* **Cache behavior:** Precompiled wheel installs are keyed per target Python version (whereas uncompiled pure-Python wheels are shared across versions) and re-run on interpreter patch updates. Setting `precompile = "enabled"` selectively on large packages limits that rebuild overhead.

#### Console Scripts & Wheel Data

* **`py_console_script_binary`:** Every package exposes a `:dist_info` target for entry-point discovery:

  ```python
  load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")

  py_console_script_binary(
      name = "cython",
      pkg = "@pypi//cython",
      script = "cython",
  )
  ```

* **`:data` target:** `@<repo>//<package>:data` aliases `:pkg` for `rules_python` label compatibility; the installed wheel's `bin/`, `data/`, and `include/` directories are included with `:pkg`.

### Gazelle Integration

`rules_pycross` matches `rules_python_gazelle_plugin`'s default `@<repo>//<package>` label convention—no `gazelle:python_label_convention` directives are required.

```python
# BUILD.bazel
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

```bash
bazel run //:gazelle_python_manifest.update  # Update gazelle_python.yaml
bazel run //:gazelle                         # Update BUILD files
```

* **How `:modules_mapping` works:** Each generated repo provides a `:modules_mapping` target built by `pycross_modules_mapping` from package metadata at build time (covering all pinned packages, including `testonly` ones)—wheels do not need to be downloaded or extracted during analysis.
* **Custom package sets:** Use `pycross_modules_mapping(deps = ...)` from `@rules_pycross//pycross:defs.bzl` (with `testonly = True` if `deps` includes `all_testonly_requirements`).

---

## Toolchains, Architecture & Migration

### Toolchain Configuration

Python versions are auto-discovered from registered `rules_python` toolchains, and all supported target platforms are enabled by default. Use `pycross.configure_toolchains()` in `MODULE.bazel` to restrict platforms/versions or set default OS/libc compatibility targets:

```python
pycross = use_extension("@rules_pycross//pycross/extensions:pycross.bzl", "pycross")
pycross.configure_toolchains(
    platforms = [
        "x86_64-unknown-linux-gnu",
        "aarch64-apple-darwin",
    ],
    python_versions = ["3.13", "3.14"],
    glibc_version = "2.28",
    macos_version = "15.0",
    musl_version = "1.2",
)
```

* `glibc_version`, `macos_version`, and `musl_version` set the defaults for `@rules_pycross//pycross/settings:{glibc,macos,musl}_version` (which determine compatible `manylinux`, `macosx`, and `musllinux` wheel tags and can be overridden per build).
* Pass `register_toolchains = False` to disable automatic toolchain registration.

### How It Works

`rules_pycross` maps each step of `pip install` to native Bazel primitives:

1. **Target environment (`@platforms` & toolchains):** Standard Bazel `@platforms` constraints and `rules_python` version settings are evaluated against PEP 508 markers at analysis time.
2. **Lock resolution (`uv`, `pdm`, `poetry`, `pylock`):** Module extensions translate lock files into `http_file` downloads for pre-built wheels and sdist build targets for source distributions.
3. **Hermetic sdist builds (`setuptools_build`, `meson_build`, etc.):** Source distributions are compiled into wheels inside sandboxed Bazel actions (with remote execution and cross-compilation support).
4. **Wheel extraction (`pycross_wheel_library`):** Extracts downloaded or built wheels into Bazel `TreeArtifact`s and exposes them as `py_library` targets.

### Migrating from 1.x

The legacy `lock_import` / `lock_repos` extensions have been replaced by per-format extensions (`uv.bzl`, `pdm.bzl`, `poetry.bzl`, `pylock.bzl`):

```python
# Before (1.x - removed):
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

# After (2.0):
uv = use_extension("@rules_pycross//pycross/extensions:uv.bzl", "uv")
uv.workspace(
    name = "pypi",
    lock_file = "//:uv.lock",
)
uv.package(
    name = "numpy",
    build_mode = "always",  # was: always_build = True
    workspace = "pypi",     # was: repo = "pypi"
)
use_repo(uv, "pypi")
```

---

## Reference Documentation

* **Module Extensions:** [uv](docs/ext_uv.md) · [pdm](docs/ext_pdm.md) · [poetry](docs/ext_poetry.md) · [pylock](docs/ext_pylock.md) · [pycross](docs/ext_pycross.md) · [backends](docs/ext_backends.md)
* **Backend Overrides:** [setuptools](docs/ext_setuptools.md) · [meson](docs/ext_meson.md) · [cmake](docs/ext_cmake.md) · [maturin](docs/ext_maturin.md) · [setuptools_rust](docs/ext_setuptools_rust.md) · [pep517](docs/ext_pep517.md)
* **Rules & Internals:** [Core Rules](docs/rules.md) · [Maturin Rules](docs/maturin_rules.md) · [Backend Author API](docs/backend.md) · [Toolchains](docs/toolchain.md)
* **Examples:** See [`tests/e2e/`](tests/e2e/) and [`examples/`](examples/)
