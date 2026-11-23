# `rules_pycross`

`rules_pycross` imports Python lock files (`uv`, `PDM`, `Poetry`, and PEP 751 `pylock.toml`) into Bazel. It downloads pre-built wheels and builds source distributions, including C, C++, and Rust extensions. Source builds run in Bazel build actions rather than during repository setup.

Paired with [hermetic-llvm](https://github.com/hermeticbuild/hermetic-llvm) (`llvm` on the Bazel Central Registry), `rules_pycross` can cross-compile wheels between Linux and macOS from either host. Linux and macOS are tested in [CI](https://github.com/jvolkman/rules_pycross/actions/workflows/ci.yml); Windows is not tested.

> [!NOTE]
> Version 2.0 overhauled `rules_pycross` ([#243](https://github.com/jvolkman/rules_pycross/pull/243)). See the [CHANGELOG](CHANGELOG.md) for breaking changes and [Migrating from 1.x](#migrating-from-1x) below. The 1.x line remains on the [`v1`](https://github.com/jvolkman/rules_pycross/tree/v1) branch.

## Contents

* [Getting started](#getting-started)
* [Generated targets](#generated-targets)
* [Dependency groups and testonly packages](#dependency-groups-and-testonly-packages)
* [Workspaces and package settings](#workspaces-and-package-settings)
* [Building from source](#building-from-source)
* [Conflicts, variants, and transitions](#conflicts-variants-and-transitions)
* [Unavailable packages](#unavailable-packages)
* [`rules_python` and Gazelle](#rules_python-and-gazelle)
* [Advanced setup and migration](#advanced-setup-and-migration)
* [Reference](#reference)

---

## Getting started

Add `rules_pycross`, `rules_python`, and your lock file extension to `MODULE.bazel`:

```python
bazel_dep(name = "rules_pycross", version = "2.3.0")
bazel_dep(name = "rules_python", version = "1.7.0")

uv = use_extension("@rules_pycross//pycross/extensions:uv.bzl", "uv")
uv.workspace(
    name = "pypi",
    lock_file = "//:uv.lock",
)
use_repo(uv, "pypi")
```

For a single-project lock file, `uv.workspace()` creates a repository named after the workspace (`@pypi` here) containing the project's `"default"` dependencies. Add `uv.repo()` when you want extra groups or a different repository name:

```python
uv.repo(
    dependency_groups = ["default", "optional:grpc", "group:test;testonly"],
    workspace = "pypi",
)
```

In `BUILD.bazel`, depend on `@pypi//<package_name>` (with hyphens replaced by underscores) or use `requirement()`:

```python
load("@pypi//:requirements.bzl", "requirement")
load("@rules_python//python:defs.bzl", "py_binary")

py_binary(
    name = "app",
    srcs = ["app.py"],
    deps = [
        "@pypi//requests",
        requirement("google-api-core[grpc]"),
    ],
)
```

> [!TIP]
> Root aliases like `@pypi//:requests` (with a colon) are also generated so 1.x labels continue to work.

### Other lock formats

PDM, Poetry, and PEP 751 `pylock.toml` use the same `workspace()`, `repo()`, and `package()` tags:

| Lock format | Extension | Tag | Notes |
|---|---|---|---|
| uv (`uv.lock`) | `@rules_pycross//pycross/extensions:uv.bzl` | `uv` | Supports uv workspaces and conflict variants. |
| PDM (`pdm.lock`) | `@rules_pycross//pycross/extensions:pdm.bzl` | `pdm` | Looks up entries without URLs via the Simple API. |
| Poetry (`poetry.lock`) | `@rules_pycross//pycross/extensions:poetry.bzl` | `poetry` | Looks up entries without URLs via the Simple API. |
| PEP 751 (`pylock.toml`) | `@rules_pycross//pycross/extensions:pylock.bzl` | `pylock` | Graphless locks (`pip lock`, `uv export`) install all marker-matching packages together. |

### Native C/C++ toolchain setup

Building source distributions with C or C++ code requires a C/C++ toolchain. For cross-platform builds, register [hermetic-llvm](https://github.com/hermeticbuild/hermetic-llvm) (`llvm` on BCR):

```python
bazel_dep(name = "llvm", version = "0.8.24")

register_toolchains("@llvm//toolchain:all")
```

Pass `--platforms=@llvm//platforms:linux_aarch64` or `--platforms=@llvm//platforms:macos_aarch64` to cross-compile.

---

## Generated targets

Each generated repository exposes these targets:

| Target | Description |
|---|---|
| `@pypi//<pkg>` (or `@pypi//:<pkg>`) | `py_library` for `<pkg>`, including any extras requested by the repo. |
| `@pypi//<pkg>:[]` | Base package without extra dependencies (when `<pkg>` has extras). |
| `@pypi//<pkg>:[<extra>]` | `<pkg>` with `<extra>` and its dependencies (`requirement("pkg[extra]")`). |
| `@pypi//<pkg>:dist_info` | `entry_points.txt` for `rules_python`'s `py_console_script_binary`. |
| `@pypi//<pkg>:data` | Alias to `:pkg` for `rules_python` label compatibility. |
| `@pypi//<pkg>:wheel` | Directory (`TreeArtifact`) containing the `.whl` file. |
| `@pypi//<pkg>:sdist` | Source distribution archive (when present in the lock file). |
| `@pypi//:requirements.bzl` | Exports `requirement()`, `all_requirements`, and `all_testonly_requirements`. |
| `@pypi//:modules_mapping` | Import-to-package JSON manifest for Gazelle. |
| `@pypi//_backend:<rule>.bzl` | Backend build macros preconfigured for the workspace (such as `setuptools_build` and `meson_build`). |

When a project depends on `google-api-core[async_rest,grpc]`, `@pypi//google_api_core` includes both extras. Use `@pypi//google_api_core:[]` for the base package alone, or `@pypi//google_api_core:[grpc]` for a single extra.

---

## Dependency groups and testonly packages

`dependency_groups` on `repo()` selects which project groups are pinned. It defaults to `["default"]`.

| Specifier | Meaning |
|---|---|
| `"default"` | `[project.dependencies]` |
| `"optional:<name>"` | Named extra in `[project.optional-dependencies]` |
| `"group:<name>"` | Named group in `[dependency-groups]` |
| `"optional:*"` / `"group:*"` | All optional extras or all dependency groups |
| `"*"` | `"default"` plus all optional extras and dependency groups |
| `"transitive"` | Expose `@<repo>//<pkg>` aliases for indirect dependencies |
| `<spec>;testonly` | Mark targets from `<spec>` as `testonly = True` |

### Transitive package aliases

`"*"` does not include `"transitive"`. Add `"transitive"` explicitly when you want `@pypi//<pkg>` labels for indirect dependencies:

```python
uv.repo(
    dependency_groups = ["default", "transitive"],
    workspace = "pypi",
)
```

If the lock file has several versions of an indirect dependency, its alias chooses between them with a `select()` on the resolution markers. When markers cannot tell them apart, `rules_pycross` warns and uses the highest version.

### Testonly dependencies and precedence

Appending `;testonly` marks those generated targets `testonly = True`. It also moves them from `all_requirements` into `all_testonly_requirements` in `requirements.bzl`.

`"transitive;testonly"` marks only indirect packages that are reachable exclusively from `testonly` groups. Packages shared with production groups stay non-testonly:

```python
uv.repo(
    dependency_groups = ["default", "group:test;testonly", "transitive;testonly"],
    workspace = "pypi",
)
```

Specifiers apply in order, and later entries win. `"*"` sets the `testonly` state for every group and clears earlier overrides:

```python
# Everything is testonly except group:dev
uv.repo(
    dependency_groups = ["*;testonly", "group:dev"],
    workspace = "pypi",
)

# Only group:test is testonly
uv.repo(
    dependency_groups = ["*", "group:test;testonly"],
    workspace = "pypi",
)

# The trailing "*" clears the earlier testonly mark on group:dev
uv.repo(
    dependency_groups = ["group:dev;testonly", "*"],
    workspace = "pypi",
)
```

---

## Workspaces and package settings

### Monorepos and multiple lock files

A workspace lock file can feed one shared repository or separate repositories per member. Repositories in the same `workspace()` share one backing package repository, so common wheels and source builds run once:

```python
uv = use_extension("@rules_pycross//pycross/extensions:uv.bzl", "uv")

uv.workspace(
    name = "shared",
    lock_file = "//:uv.lock",
)

# All workspace members in one repo:
uv.repo(
    name = "lock_all",
    projects = ["*"],
    workspace = "shared",
)

# Or separate repos per member:
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

When a repository covers multiple projects, each group in `dependency_groups` only needs to exist in one of them.

For independent lock files, declare separate `workspace()` tags:

```python
uv.workspace(
    name = "frontend_deps",
    lock_file = "//frontend:uv.lock",
)
uv.workspace(
    name = "ml_deps",
    lock_file = "//ml:uv.lock",
)
use_repo(uv, "frontend_deps", "ml_deps")
```

### Project files and custom indexes

`rules_pycross` discovers member `pyproject.toml` files from paths in the lock file (relative to the lock file's directory), or falls back to a `pyproject.toml` next to the lock file.

Use `extra_project_files` to add `pyproject.toml` files that are not listed as workspace members:

```python
uv.workspace(
    name = "pypi",
    lock_file = "//:uv.lock",
    extra_project_files = ["//:pyproject.toml", "//tools:pyproject.toml"],
)
```

Lock entries without download URLs (common in Poetry and PDM) are looked up through the Simple Repository API (PEP 691/503) in the index that the lock file records for that entry, if any. Otherwise `rules_pycross` tries `pypi_indexes` in order, defaulting to PyPI only:

```python
uv.workspace(
    name = "pypi",
    lock_file = "//:uv.lock",
    pypi_indexes = [
        "https://pypi.example.com/simple",
        "https://pypi.org/simple",
    ],
)
```

### Per-package settings

`package()` configures how a package (or `"*"` for workspace defaults) builds, patches, or installs. Specific entries inherit unset fields from `"*"`. You can omit `workspace` when the module has only one workspace.

```python
# Require pre-built wheels by default:
uv.package(
    name = "*",
    build_mode = "never",
    workspace = "shared",
)

# Build regex from source and exclude a file when installing:
uv.package(
    name = "regex",
    build_mode = "always",
    install_exclude_globs = ["test_regex.py"],
    workspace = "shared",
)

# Patch matplotlib after wheel installation:
uv.package(
    name = "matplotlib",
    post_install_patches = ["//:matplotlib.patch"],
    workspace = "shared",
)
```

Common `package()` attributes (see [`docs/ext_uv.md`](docs/ext_uv.md) for the full list):

| Attribute | Purpose |
|---|---|
| `build_mode` | `"auto"` (prefer wheel, else sdist), `"always"` (build from source), or `"never"` (wheels only; a `build_target` is still used). |
| `pre_build_patches`, `post_install_patches` | Unified diff patches applied atomically before building or after installing (supports git renames, copies, mode changes, and empty files). |
| `ignore_dependencies`, `extra_dependencies` | Drop or add runtime dependency keys when upstream metadata is wrong. |
| `install_exclude_globs` | File globs to skip during wheel installation. |
| `site_paths`, `bin_paths`, `data_paths`, `include_paths` | Override auto-detected wheel paths. |
| `precompile` | `"auto"`, `"enabled"`, or `"disabled"` for `.pyc` compilation. |
| `extra_build_tools`, `build_backend`, `build_target`, `build_tools_repo` | Source-build configuration (see [Building from source](#building-from-source)). |

---

## Building from source

### Build backends

`rules_pycross` selects a build rule from `build-system.build-backend` in each sdist's `pyproject.toml` (override the rule choice with `package(build_backend = ...)`):

| Build rule | Matched `build-backend` | Typical packages |
|---|---|---|
| `pep517_build` | `hatchling.build`, `flit_core.buildapi`, `pdm.backend`, `poetry.core.masonry.api`, or unmatched | Pure-Python packages (default) |
| `setuptools_build` | `setuptools.build_meta` | C/C++ extensions using setuptools |
| `setuptools_rust_build` | `setuptools.build_meta` (with `setuptools-rust` in `build-system.requires`) | Rust extensions using `setuptools-rust` |
| `meson_build` | `mesonpy` | `meson-python` packages (`numpy`, `scipy`, `pandas`) |
| `cmake_build` | `scikit_build_core.build` | `scikit-build-core` / CMake packages |
| `maturin_build` | `maturin` | Maturin Rust packages (`rules_pycross_backend_maturin`) |

### Build-time Python dependencies

Sdist builds automatically include the sdist's `build-system.requires`. List extra build-time packages (such as `cython` or `setuptools-scm`) in `extra_build_tools` as locked package keys:

```python
uv.package(
    name = "*",
    extra_build_tools = ["cython@0.29.36"],
    workspace = "pypi",
)

# Replaces the "*" list for numpy:
uv.package(
    name = "numpy",
    extra_build_tools = ["cython@0.29.36", "oldest-supported-numpy@0.9"],
    workspace = "pypi",
)
```

Build tools resolve from an auto-generated `<workspace>__build` repository, which includes `["*", "transitive"]` across all projects by default. Declare `uv.repo(name = "pypi__build", ...)` to customize its groups, or set `package(build_tools_repo = ...)` on a single package:

```python
uv.repo(
    name = "pypi__build",
    dependency_groups = ["default", "group:build", "transitive"],
    workspace = "pypi",
)
```

An overridden `pypi__build` repository must still provide every required build tool. Keep `"transitive"` unless every build tool from `build-system.requires`, backend defaults, and `extra_build_tools` is pinned directly.

### Backend overrides and native libraries

Use backend override extensions (`setuptools`, `meson`, `cmake`, `maturin`, `setuptools_rust`) to pass compiler flags, environment variables, native libraries, or `PATH` tools:

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

`name` accepts `"*"`, `"<pkg>"`, or `"<pkg>@<version>"`. When several entries match a package, more specific entries override less specific ones field by field.

`path_tools` exposes binaries on `PATH` under their file basename. Wrap a binary in `pycross_path_tool` to rename it:

```python
# deps/psycopg2/BUILD.bazel
load("@rules_pycross//pycross:defs.bzl", "pycross_path_tool")

pycross_path_tool(
    name = "pg_config_tool",
    executable_name = "pg_config",
    tool = "//third_party/postgresql:pg_config_bin",
)
```

`tool_deps` replaces individual Python tool packages that a backend adds by default (for example, `setuptools` and `wheel` for `setuptools`, or `cmake`, `ninja`, and `scikit-build-core` for `cmake`). Unlisted tools keep their defaults:

```python
cmake = use_extension("@rules_pycross//pycross/backends:cmake.bzl", "cmake")

cmake.override(
    name = "*",
    workspace = "pypi",
    tool_deps = {"cmake": "@other_deps//cmake:pkg"},
)
```

For full control, write a custom build target and point `package(build_target = "@//deps/numpy:wheel")` at it. `pycross_cc_pkg_config` generates a `.pc` file so Meson or CMake can find a Bazel `cc_library`:

```python
# deps/numpy/BUILD.bazel
load("@pypi//_backend:meson_build.bzl", "meson_build")
load("@rules_pycross//pycross:defs.bzl", "pycross_cc_pkg_config")

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

### Linking against libraries in other wheels

When an sdist links against C/C++ libraries shipped inside another wheel (such as `torch`, `pyarrow`, `numpy`, or `nvidia-*`), wrap that wheel target in `pycross_wheel_cc_import` and add it to `native_deps`:

```python
load("@pypi//_backend:setuptools_build.bzl", "setuptools_build")
load("@rules_pycross//pycross:defs.bzl", "pycross_wheel_cc_import")

pycross_wheel_cc_import(
    name = "libtorch",
    wheel_library = "//deps/torch:wheel_library",  # a pycross_wheel_library
    includes = ["torch/include"],
    shared_library = "torch/lib/libtorch.so",
)

setuptools_build(
    name = "wheel",
    native_deps = [":libtorch"],
    sdist = "@pypi//my-torch-extension:sdist",
)
```

Paths are relative to the wheel's `site-packages`. Versioned files such as `libcudart.so.12` still link with `-lcudart`. For headers alone, use `pycross_wheel_headers`.

Wheel repair locates shared libraries from `pycross_wheel_cc_import` targets, including through `cc_library` wrappers, without bundling a duplicate copy. The built extension still needs to find the library at runtime, for example because the other package loads it first, or through an `$ORIGIN` RPATH.

### Rust packages (Maturin and setuptools-rust)

Add `rules_pycross_backend_maturin` and `rules_rust` to build Rust extensions from source:

```python
bazel_dep(name = "rules_pycross_backend_maturin", version = "2.3.0")
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

# Supply a Cargo.lock when the sdist omits one:
maturin = use_extension("@rules_pycross_backend_maturin//extensions:maturin.bzl", "maturin")
maturin.override(
    name = "jiter",
    workspace = "pypi",
    cargo_lock = "//:jiter.lock",
)
```

Run `bazel run @pypi//_cargo:jiter@<version>` to generate `Cargo.lock` for an overridden package.

> [!NOTE]
> During Rust cross-builds, Cargo links host proc-macros and build scripts with `cc` from `PATH` rather than the Bazel C/C++ toolchain. Make sure the execution host or container has a C compiler installed.

---

## Conflicts, variants, and transitions

### `uv` conflicts and variants

`rules_pycross` turns `[tool.uv] conflicts` declarations (such as CPU vs. CUDA `torch`) into Bazel flags under `@<repo>//_variants:`:

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

Select a variant on the command line or inside a `platform()`:

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
    flags = [
        "--@pypi//_variants:extra_cu124=True",
    ],
)
```

Then build with `--platforms=//:linux_cuda`. Each flag also has a matching `@<repo>//_variants:is_<flag>` `config_setting`, such as `@pypi//_variants:is_extra_cu124`, for `select()` expressions.

Every repo with variants also exposes a `@<repo>//_variants` `string_flag` accepting a variant name or a comma-separated list across conflict sets (for example `--@pypi//_variants=extra_cu124` or `--@pypi//_variants=extra_cu124,group_test`). Because it is a string setting, it also works directly with `rules_python`'s per-target `config_settings` transition when you want targets in one build to pick different variants from the same repo:

```python
# MODULE.bazel
config = use_extension("@rules_python//python/extensions:config.bzl", "config")
config.add_transition_setting(setting = "@pypi//_variants")
```

```python
# BUILD.bazel
py_test(
    name = "cuda_test",
    srcs = ["cuda_test.py"],
    config_settings = {"@pypi//_variants": "extra_cu124"},
    deps = ["@pypi//torch"],
)
```

When pairing per-target `config_settings` with a default in `.bazelrc` or on the command line, set the default with `--@pypi//_variants=<flag>` rather than `--@pypi//_variants:<flag>=True` so the target's transition replaces it instead of conflicting with the `bool_flag`.

Conflict flags also cover dependency groups and conflicting workspace members:

* `extra_<name>` and `group_<name>` enable that extra or group across every project in the repo that declares it.
* `extra_<project>_<name>` and `group_<project>_<name>` target one project in a multi-project repo. Use these when same-named groups in two projects conflict.
* `package_<project>` selects one member when whole projects conflict (`{ package = "app-a" }`, a `uv` preview feature). A repo covering several conflicting projects must set `package_<project>`, or it fails with `No uv conflict variant selected`.

A repo that requests exactly one item of a conflict set selects that item automatically, as `uv sync --extra cpu` or `uv sync --package app-a --group test` does. For example, a repo with `dependency_groups = ["default", "optional:cpu"]` always uses the `cpu` variant without any flag, and a single-project repo always selects its own project.

The repo's targets transition to that selection. A package that doesn't depend on the selection is still installed once for all repos, as long as it comes from a wheel. Packages with variant-dependent dependencies are built once per selection. The generated `<workspace>__build` repo never selects automatically.

If a repo requests several items of a set, and `[tool.uv] default-groups` names exactly one of them, that repo defaults to it when no flag is set. Single-project repos read the member's `pyproject.toml`, and multi-project repos read the workspace root's. Each repo applies its own default, so two repos can default to different groups in the same build.

Extras are never a default, so a repo that requests several conflicting extras fails unless a flag selects one. Precedence from highest to lowest is: the repo's automatic selection or a `repo(flags / settings)` pin, command-line `_variants` flags, then `default-groups`. A `repo(flags / settings)` pin that disagrees with the automatic selection is an error. Inside a repo that has its own transition, `_variants` flags meant for other repos don't activate items that the repo didn't request or that conflict with its pins.

### Repository transitions

Set `flags`, `settings`, `constraint_values`, or `platform` on `uv.repo()`, `pdm.repo()`, `poetry.repo()`, or `pylock.repo()` to transition all targets in that repository:

```python
# Pin flags and module-scoped Starlark settings (keeps incoming --platforms):
uv.repo(
    name = "ml-pipeline",
    workspace = "shared",
    flags = [
        "--compilation_mode=opt",
        "--@ml-pipeline//_variants:extra_cu124=True",
    ],
    settings = {
        "@my_flags//:level": "2",
    },
)

# Or combine with platform constraints:
uv.repo(
    name = "linux-x86-deps",
    workspace = "shared",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)
```

| Attribute | When to use |
|---|---|
| `flags` | Built-in options (`--compilation_mode=opt`, repeated `--copt=...`) and labels visible to `rules_pycross` (`--@ml-pipeline//_variants:...`, root `//pkg:flag`). `--platforms` is not allowed here; use `platform` or `constraint_values`. |
| `settings` | `{label: value}` build settings resolved from the declaring module (comma-separated for list settings). |
| `constraint_values` | `@platforms` constraints for a generated platform (combinable with `flags` and `settings`). |
| `platform` | Existing `platform()` target (mutually exclusive with the three attributes above). |

When a repo transitions to a `platform`, Bazel ignores that platform's `flags`, so pin variant or compiler flags with `repo(flags = ...)` or `repo(settings = ...)`.

Transitions apply to the repository's whole dependency closure, including sdist builds, so each transitioned repository compiles its sdists in a separate configuration. See [`docs/ext_uv.md`](docs/ext_uv.md) for flag syntax details.

---

## Unavailable packages

A package is unavailable in the target environment when any of these apply:

* No compatible wheel is available, and there is no sdist to build.
* No resolution-marker fork matches the target environment.
* The selected conflict variant excludes the package.

`--@rules_pycross//pycross/settings:unavailable_package_mode` controls how unavailable packages behave:

| Mode | Behavior |
|---|---|
| `incompatible` (default) | Marks the package [incompatible](https://bazel.build/extending/platforms#skipping-incompatible-targets): `bazel build //...` skips dependents, explicit builds fail analysis, and `all_requirements` omits platform-only packages. |
| `fail_at_execution` | Analyzes normally with `PyInfo` and fails with `No compatible wheel is available ...` only if an action builds the package. |

Use `fail_at_execution` for analysis-only tools such as type-checking aspects, or when you want `bazel build //...` to fail instead of skipping targets:

```text
# .bazelrc (use common so build, test, and cquery share the analysis cache)
common --@rules_pycross//pycross/settings:unavailable_package_mode=fail_at_execution
```

> [!WARNING]
> `fail_at_execution` makes `bazel build //...` and `bazel test //...` fail on targets whose dependencies do not support the current platform. Scope it to a config like `common:typecheck` if normal builds rely on incompatible target skipping.

Unselected `uv` conflicts without a default always fail with a message naming the `_variants` flags to set. This happens at analysis time by default, or at execution time under `fail_at_execution`.

Broken sdist configurations, such as missing `build-system.requires` packages in the lock file or missing `meson`, `cmake`, `ninja`, or `maturin` in `tool_deps`, always analyze normally. They fail at execution time with `Cannot build <sdist> from source: ...` so `cquery` and aspects keep working.

---

## `rules_python` and Gazelle

### `rules_python`

Generated repositories follow `rules_python`'s `@<repo>//<package>` layout.

#### Virtual environments

With `--@rules_python//python/config_settings:venvs_site_packages=yes`, `pycross_wheel_library` populates `site-packages` symlinks without adding wheel directories to `sys.path`. Namespace packages (PEP 420, `pkgutil`, and `nvidia`) link per subpackage so multiple wheels can share a namespace.

#### `.pyc` precompilation

Enable `.pyc` compilation during wheel installation globally or per package:

```python
# Or pass --@rules_python//python/config_settings:precompile=enabled
uv.package(
    name = "scipy",
    precompile = "enabled",
    workspace = "pypi",
)
```

Precompiled installs are tied to one Python version, and an interpreter patch release re-runs them. Uncompiled pure-Python installs are shared across Python versions. Enable `precompile` on the large packages that need it rather than globally to limit that rebuild cost. Pass `--@rules_pycross//pycross/settings:precompile_invalidation_mode=unchecked_hash` to share precompiled installs between target fastbuild and exec opt builds under path mapping. See [`pycross_wheel_library`](docs/rules.md#pycross_wheel_library) for invalidation details.

#### Console scripts

Each package exposes `:dist_info` for `rules_python`'s `py_console_script_binary`:

```python
load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")

py_console_script_binary(
    name = "cython",
    pkg = "@pypi//cython",
    script = "cython",
)
```

### Gazelle

Generated repositories match `rules_python_gazelle_plugin`'s default `@<repo>//<package>` layout, so no `gazelle:python_label_convention` directives are needed. Point `gazelle_python_manifest` at `@pypi//:modules_mapping`:

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
bazel run //:gazelle_python_manifest.update
bazel run //:gazelle
```

`:modules_mapping` is built from lock metadata and covers all pinned packages, including `testonly` ones, without downloading wheels during analysis.

For a custom package list, use `pycross_modules_mapping(deps = ...)` from `@rules_pycross//pycross:defs.bzl`. Set `testonly = True` when `deps` includes `all_testonly_requirements`.

---

## Advanced setup and migration

### Toolchain configuration

`rules_pycross` discovers Python versions from registered `rules_python` toolchains by default. Use `pycross.configure_toolchains()` to restrict Python versions or set default OS/libc compatibility versions:

```python
pycross = use_extension("@rules_pycross//pycross/extensions:pycross.bzl", "pycross")
pycross.configure_toolchains(
    python_versions = [
        "3.13",
        "3.14",
    ],
    glibc_version = "2.28",
    macos_version = "15.0",
    musl_version = "1.2",
)
```

The OS and libc versions set defaults for `@rules_pycross//pycross/settings:{glibc,macos,musl}_version` (`manylinux`, `macosx`, and `musllinux` wheel compatibility) and can be overridden per build. Pass `register_toolchains = False` to skip automatic toolchain registration.

### How it works

1. During analysis, `rules_pycross` maps Bazel `@platforms` constraints and `rules_python` flags to PEP 508 marker values and evaluates the lock file's markers against them.
2. Lock extensions (`uv`, `pdm`, `poetry`, `pylock`) turn lock files into wheel downloads and sdist build targets.
3. Backend rules (`setuptools_build`, `meson_build`, `cmake_build`, `maturin_build`, `pep517_build`) compile sdists into wheels inside sandboxed Bazel actions.
4. `pycross_wheel_library` unpacks each wheel into a `TreeArtifact` and provides it as a `py_library`.

### Migrating from 1.x

Version 2.0 replaced `lock_import` and `lock_repos` with per-format extensions (`uv.bzl`, `pdm.bzl`, `poetry.bzl`, `pylock.bzl`):

```python
# Before (1.x, removed):
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

## Reference

* Module extensions: [`uv`](docs/ext_uv.md), [`pdm`](docs/ext_pdm.md), [`poetry`](docs/ext_poetry.md), [`pylock`](docs/ext_pylock.md), [`pycross`](docs/ext_pycross.md), [`backends`](docs/ext_backends.md)
* Backend overrides and rules: [`setuptools`](docs/ext_setuptools.md), [`meson`](docs/ext_meson.md), [`cmake`](docs/ext_cmake.md), [`maturin`](docs/ext_maturin.md), [`setuptools_rust`](docs/ext_setuptools_rust.md), [`pep517`](docs/ext_pep517.md)
* Core rules and backend API: [rules](docs/rules.md), [maturin rules](docs/maturin_rules.md), [backend author API](docs/backend.md), [toolchains](docs/toolchain.md)
* Working examples: [`examples/`](examples/) and [`tests/e2e/`](tests/e2e/)
