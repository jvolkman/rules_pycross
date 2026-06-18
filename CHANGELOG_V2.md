# rules_pycross v2 — Changelog

> Comprehensive feature list for the `dev/v2` branch compared to `main`.

---

## Breaking Changes

### Removed: WORKSPACE support

- Deleted `pycross/workspace.bzl`, `pycross/repositories.bzl`, `pycross/private/lock_repo.bzl`, `pycross/private/lock_file_repo.bzl`.
- All `WORKSPACE.bazel` files removed from e2e tests.
- Bzlmod is now the only supported module system.

### Removed: `pycross_wheel_build` rule

- The monolithic `pycross_wheel_build` rule and its backing `wheel_builder.py` (1,087 lines) have been deleted.
- Replaced by the new pluggable backend architecture (see below).

### Removed: `pycross_lock_file` rule

- Deleted `pycross/private/lock_file.bzl`, `pycross/extensions/lock_file.bzl`, `pycross/private/bzlmod/lock_file.bzl`.
- Lock file generation is now handled entirely through `lock_import` + `lock_repos` extensions.

### Removed: `pycross_wheel_zipimport_library` from public API

- No longer re-exported from `pycross/defs.bzl`.

### Removed: `PycrossWheelInfo` provider

- `PycrossWheelInfo` has been removed entirely from all rules and the providers module.
- Builder rules now return `DefaultInfo` with the wheel TreeArtifact as their default output.
- Consumers use `ctx.files.wheel[0]` and branch on `is_directory` for the fast path.

### Removed: `pycross_console_script_binary`

- This rule has been deleted. Use `py_console_script_binary` from `@rules_python//python/entry_points:py_console_script_binary.bzl` instead.
- `pycross_wheel_library` now produces a `:dist_info` output group for compatibility with rules_python's entry point discovery.

### Removed: Conflict check aspect

- The `pycross_conflict_check` aspect has been removed. Cross-workspace version conflicts are now prevented structurally: workspaces share a single backing `package_repo` containing the merged set of `pycross_wheel_library` targets, so conflicting versions cannot exist.

### Changed: Internal dependency format

- Replaced the generated `.lock.bzl` files (`pycross_deps.lock.bzl`, `pycross_deps_core.lock.bzl`) with a human-readable TOML lock file (`pycross/private/pycross_deps.toml`).
- Internal `http_file` repos are now created dynamically from the TOML at module extension time using `@toml.bzl`.

### Changed: Package repo layout

- Packages are now under versioned subdirectories: `<package>/v<version>/BUILD.bazel`.
- Canonical target names changed: `:pkg` (library), `:wheel` (wheel artifact), `:sdist` (sdist file). (Appends `_` on conflict with package name).
- Root aliases (`@repo//:numpy`) still work.
- Old `_wheel/` and `_sdist/` directories available via `legacy_naming = True` flag.

---

## New: Multi-Lock Workspace Support

Support for importing multiple lock files into a shared "workspace", enabling monorepos where different subprojects use different dependencies while benefiting from shared wheel/sdist caching.

### Workspace Architecture

- Lock imports sharing the same `workspace` name (via `import_uv_workspace`, or implicitly from the `repo` name on regular imports) share a single backing `package_repo` (the workspace) containing the merged set of `pycross_wheel_library` targets.
- Each user-facing repo becomes a lightweight `thin_package_repo` facade with its own `requirements.bzl`, `modules_mapping.json`, and pin aliases pointing to the workspace's `_lock/` targets.
- When no explicit workspace is set, each repo implicitly gets its own single-member workspace (named after the repo).

### Example Usage (explicit workspace)

```python
lock_import.import_uv(
    lock_file = "//frontend:uv.lock",
    project_file = "//frontend:pyproject.toml",
    repo = "frontend",
    target_environments = ["@envs//:environments"],
)

lock_import.import_uv(
    lock_file = "//ml:uv.lock",
    project_file = "//ml:pyproject.toml",
    repo = "ml",
    target_environments = ["@envs//:environments"],
)
```

Each repo becomes its own workspace with an isolated `package_repo`. Overlapping packages within a workspace are downloaded and built only once.

---

## New: First-Class UV Workspace Import

A three-tier API for importing UV workspaces that use a single `uv.lock` with multiple workspace members.

### API

```python
# 1. Declare the workspace (shared lock file and settings).
lock_import.import_uv_workspace(
    name = "shared",
    lock_file = "//:uv.lock",
    target_environments = ["@envs//:environments"],
)

# 2. Declare members with a repo naming pattern.
lock_import.uv_workspace_members(
    workspace = "shared",
    repo_pattern = "lock_{member}",  # {member} is replaced with normalized member name
)

# 3. Optionally override individual member settings.
lock_import.uv_workspace_member(
    workspace = "shared",
    project = "project-a",
    repo = "lock_a",  # Override the pattern-generated name
)
```

### Features

- **Shared workspace**: All members share a single `package_repo` for deduplication — overlapping dependencies are resolved once.
- **`repo_pattern`**: A `string.format` pattern with a `{member}` parameter. The member name is normalized for Bazel repo name usage (lowercase, dashes→underscores).
- **Unique name enforcement**: Errors if multiple repos (across any lock/member) would generate the same repo name.
- **Per-member annotations**: `lock_import.package()` tags target a specific member via the `repo` attribute.
- **Settings inheritance**: Members inherit `target_environments`, `default_alias_single_version`, `squash_extras`, etc. from the workspace tag.

---

## New: Extras Support

Extras (optional dependency groups) are now first-class in the resolver and renderer.

- `EXTRA_PATTERN` regex in the resolver extracts `extra == '...'` from PEP 508 markers.
- `get_dependencies_by_environment()` splits dependencies into base deps and per-extra deps, with per-environment granularity.
- The renderer emits `py_library(name = "[extra_name]")` targets for each extra, with the package itself as a dep plus the extra-specific deps.
- Extra deps support `select()` for environment-specific resolution.
- Example: `@pypi//requests:[security]` pulls in `pyOpenSSL`, `cryptography`, etc.

---

## New: Automatic Cycle Resolution

Circular dependency detection and resolution is now automatic via Tarjan's SCC algorithm.

- **Iterative Tarjan's SCC** — avoids stack overflow on large dependency graphs (replaced recursive version).
- **Content-based cycle group naming** — group names use `group_{sha256[:8]}` for stability across lockfile changes. Adding/removing an unrelated package won't renumber existing groups.
- **Renderer integration** — generates `_cycles/BUILD.bazel` containing `py_library` targets for each cycle group. Cycled packages use `pkg_raw` naming for `pycross_wheel_library` and a wrapping `py_library(name = "pkg")` that depends on both `pkg_raw` and the cycle group.
- Same-cycle dependencies are excluded from individual package dep lists to break the circular reference.

---

## New: pylock.toml Support (PEP 751)

Full translator for the PEP 751 `pylock.toml` lockfile format.

### Basic Translation

- Parses `lock-version = "1.0"` files.
- Extracts packages, versions, dependencies, markers, wheels (with URLs/hashes), and sdists.
- Supports both `hash = "sha256:..."` and `hashes = { sha256 = "..." }` formats.

### Dependency Group Filtering

- `--default-group / --no-default-group` — include/exclude `[project.dependencies]`.
- `--optional-group <name>` — include specific `[project.optional-dependencies]` groups.
- `--all-optional-groups` — include all optional dependency groups.
- `--development-group <name>` — include specific `[dependency-groups]` (PEP 735).
- `--all-development-groups` — include all development groups.
- `include-group` support — resolves `{include-group = "typing"}` references in dependency groups (one level).
- **Graph traversal** — BFS from selected root packages to include only transitive dependencies, pruning unreachable packages from the lockfile.
- Warnings on stderr for missing dependencies and unknown group names.

### Bzlmod Integration

- `pycross_pylock_lock_model` rule for build-time translation.
- `repo_create_pylock_model()` for repository-rule-time translation.
- `lock_repo_model_pylock()` for bzlmod tag encoding.
- All filtering flags plumbed through `PYLOCK_IMPORT_ATTRS` → `lock_import` tag → translator CLI.

---

## New: Venv Compatibility (`site_paths`)

Packages now declare their importable top-level packages and additional installed paths for correct venv site-packages layout with `rules_python`.

### Path Categories

- **`site_paths`** — importable top-level packages, `.pth` files, and standalone modules in `site-packages/`. Formerly called `top_level_packages`.
- **`bin_paths`** — console scripts and executables in `bin/`.
- **`data_paths`** — data files in `data/`.
- **`include_paths`** — C/C++ headers in `include/`.

All four path types are tracked through `PycrossPackageInfo` and populated as `VenvSymlinkEntry` objects when `rules_python` venv support is enabled.

### Wheel Detection

- `_find_top_level_packages_wheel()` — lists directories in the wheel that are not `.dist-info` or `.data`, giving the actual importable package names.

### Sdist Detection

- `_find_top_level_packages_sdist()` — scans sdist archives for directories containing `__init__.py` at depth 2 (standard layout) or depth 3 (src-layout).
- Expanded exclusion list: `bin`, `benchmarks`, `docs`, `examples`, `scripts`, `src`, `test`, `tests`, `testing`, `tools`.
- Requires `__init__.py` presence (not just directory existence) to avoid false positives.

### Namespace Package Detection (PEP 420)

- `_resolve_namespace_packages()` — shared helper used by both wheel and sdist inspection.
- When a top-level directory lacks `__init__.py` (implicit namespace package), descends to find the shallowest concrete sub-packages and reports those instead.
- Prevents venv symlink conflicts when multiple distributions share a namespace root (e.g. `google-cloud-storage` and `google-cloud-bigquery` both installing under `google/`).

### `site_paths` Override

- New `site_paths` attribute on `lock_import.package()` and `package_annotation()` for user-specified overrides.
- Takes precedence over auto-detection from `inspection.json`.
- Threaded through the full annotation pipeline: `tag_attrs.bzl` → `lock_import.bzl` → `raw_lock_resolver.py` → `package_repo.bzl`.
- Example:

  ```python
  lock_import.package(
      name = "google-cloud-storage",
      site_paths = ["google/cloud/storage"],
  )
  ```

### Conditional Venv Symlinks

- `pycross_wheel_library` only populates `PyInfo.venv_symlinks` when `rules_python`'s `VenvsSitePackages` config setting is enabled.
- `bin_paths`, `data_paths`, and `include_paths` symlinks are gated behind `hasattr(VenvSymlinkKind, "BIN")` / `"DATA"` / `"INCLUDE"` checks for forward-compatible rules_python support.

---

## New: Legacy Naming Flag

Backward-compatible `_wheel/` and `_sdist/` directories for users migrating from v1-style target paths.

- `lock_repos.create(legacy_naming = True)` in MODULE.bazel.
- Generates `_wheel/BUILD.bazel` with:
  - Versioned aliases: `:numpy@1.2.3` → `//numpy/v1.2.3:whl`
  - Unversioned pin aliases: `:numpy` → `//numpy:whl`
- Generates `_sdist/BUILD.bazel` with same pattern (only for packages with sdists).
- Maturin extension updated to use canonical `@repo//pkg:sdist` path (no longer requires legacy naming).

---

## New: Pluggable Build Backend Architecture

The most significant change in v2. The old monolithic `pycross_wheel_build` rule is replaced by a **modular, pluggable backend system**.

### Backend Registry (`backends` extension)

- New bzlmod extension: `@rules_pycross//pycross/extensions:backends.bzl`
- Backends self-register via `backends.register()` with:
  - `name` — rule identifier (e.g., `meson_build`)
  - `rule_bzl` — label of the `.bzl` file containing the build rule
  - `pyproject_backends` — list of `build-system.build-backend` values from pyproject.toml that map to this backend
  - `tool_packages` — PyPI packages needed at build time (auto-added to build deps)
  - `default` — whether this is the fallback backend
  - `override_json` — per-backend override configuration
  - `sdist_hook_bzl` / `sdist_hook_fn` — hooks for sdist repository generation
- Creates `@pycross_backends` hub repository with the full registry.
- Root module registrations always win for duplicate backend names.

### Built-in Backends

#### `pep517_build` (default fallback)

- Generic PEP 517 builder for pure-Python packages.
- Validates `build-system.requires` via `PycrossPackageInfo`.
- No CC toolchain, no repair step.
- Handles: `hatchling`, `flit_core`, `pdm.backend`, `poetry.core.masonry.api`.

#### `setuptools_build`

- For packages using `setuptools.build_meta`.
- Injects setuptools/wheel as build deps from tool_deps.
- Conditional wheel repair (only when `native_deps` present).
- Override extension: `@rules_pycross//pycross/backends:setuptools.bzl`

#### `meson_build`

- For packages using `mesonpy` / `meson-python`.
- Extracts `meson` console script and `ninja` binary from tool deps.
- Generates Meson `cross.ini` files dynamically from CC toolchain info.
- Supports `meson_properties` dict for custom cross-file properties.
- Handles `longdouble_format` detection per platform.
- Override extension: `@rules_pycross//pycross/backends:meson.bzl`

#### `cmake_build`

- For packages using `scikit-build-core` / `scikit-build`.
- Extracts `cmake` console script and `ninja` binary.
- Injects cmake/ninja wheels as both tools and build deps.
- Always repairs (CMake builds always produce native code).
- Override extension: `@rules_pycross//pycross/backends:cmake.bzl`

#### `maturin_build` (separate module: `rules_pycross_backend_maturin`)

- For Rust+Python packages using maturin.
- Lives in `modules/backend_maturin/` as a separate Bazel module.
- Requires `@rules_rust` for Rust toolchain resolution.
- Handles `PYO3_CONFIG_FILE` generation, Rust sysroot setup, `cargo` config.
- Supports `cargo_lock` injection and `vendored_crates` for offline builds.
- Has `pycross_generate_cargo_lock` utility rule.
- Override extension: `@rules_pycross_backend_maturin//extensions:maturin.bzl`

### Public Backend Authoring API

- New file: `pycross/backend.bzl`
- Exports all building blocks for implementing custom backends:
  - Providers: `PycrossExtractedWheelInfo`, `PycrossPackageInfo`
  - Actions: `extract_cc_layer`, `register_pep517_action`, `register_repair_action`, `register_bin_extract_action`
  - Attributes: `COMMON_BUILD_ATTRS`, `CC_BUILD_ATTRS`, `CC_TOOLCHAIN_ATTRS`, `BUILD_SYSTEM_ATTRS`, `CC_BUILD_SYSTEM_ATTRS`
  - Transition: `pycross_exec_platform_transition`
  - Utilities: `get_unzipped_wheel`, `get_wheel_file`, `group_tool_deps`
  - Override helpers: `make_override_extension`, `create_overrides_repo`, `encode_build_system_attrs`

### Override Extension Attributes

Override attrs are organized into composable dictionaries for documentation clarity:

| Dict | Attrs | Purpose |
|---|---|---|
| `BUILD_SYSTEM_ATTRS` | `config_settings`, `tool_deps`, `build_env`, `data`, `pre_build_hooks`, `post_build_hooks` | General build attrs (any backend) |
| `CC_BUILD_SYSTEM_ATTRS` | `copts`, `linkopts`, `native_deps`, `path_tools` | Native/CC compilation attrs |

All four backend override dicts (meson, setuptools, cmake, maturin) compose `CORE_OVERRIDE_ATTRS | BUILD_SYSTEM_ATTRS | CC_BUILD_SYSTEM_ATTRS`.

### Patch Attributes

- `post_install_patches` and `pre_build_patches` are `label_list` attributes.
- Labels are resolved relative to the user's workspace (e.g., `//build:my.patch` works directly without requiring `@//` prefix).

---

## New: Layered Build Action Architecture

The build pipeline is decomposed into composable, reusable actions:

### `extract_cc_layer` action

- Extracts CC/CXX/AR paths, flags, includes, and libraries from Bazel's CC toolchain.
- Detects target OS/CPU from platform constraints.
- Gathers static/shared libs and C++ runtime from `CcInfo` providers.
- Serializes everything as a JSON "layer" for Python-side consumption.
- Handles `libtool` AR detection, `-fPIC` for `CCSHARED`, coverage feature filtering.

### `register_pep517_action` action

- Core action used by ALL build rules to invoke PEP 517 builds.
- Resolves exec/target Python interpreters, site-packages paths, sibling repo layouts.
- Supports pluggable builder executables (each backend provides its own).
- Handles: `config_settings`, `site_hooks`, `tool_executables`, `layers`, `pkg_config_files`, `extra_files`, `pre_build_patches`, `cargo_vendored_sources`.

### `register_repair_action` action

- Post-build wheel repair (auditwheel/delocate equivalent via repairwheel).
- Extracts library paths from `CcInfo` providers.
- Supports user-provided repairwheel via `repair_deps`.
- Handles both tree artifact and staging-dir modes.

### `register_bin_extract_action` / `register_console_script_extract_action`

- Extract binary executables or console scripts from wheel site-packages for use as build tools.

---

## New: Build Lifecycle & Strategy Pattern (Python-side)

### `run_standard_build_lifecycle(config, strategy)`

- Orchestrates the standard build sequence: load context → extract sdist → inject files → apply patches → load sysconfig → setup path tools → setup toolchains → apply CC layer → setup venv → run hooks → pre_build → apply sysconfig overrides → prepare_env → PEP 517 build.

### `BackendStrategy` dataclass

- Each backend customizes the lifecycle via hooks:
  - `setup_toolchains(ctx)` — e.g., Rust toolchain for maturin
  - `setup_venv(ctx)` — standard or crossenv
  - `pre_build(ctx)` — e.g., Meson cross.ini generation, Rust sysroot setup
  - `prepare_env(ctx)` — final environment adjustments

### Build Utilities (`pycross/private/build/tools/utils/`)

- `cc_toolchain.py` — compiler wrapper generation, CC layer application
- `venv_utils.py` — venv creation with polyglot bash/python wrapper (solves shebang length limit)
- `sysconfig_utils.py` — sysconfig variable management for cross-compilation
- `context.py` — `BuildContext` dataclass and loading
- `hooks.py` — pre-build hook execution with bidirectional JSON mutation
- `lifecycle.py` — standard build lifecycle orchestration
- `path_tools.py` — PATH tool management
- `pep517_runner.py` — PEP 517 build invocation
- `sdist.py` — sdist extraction
- `meson_utils.py` — Meson cross.ini generation

---

## New: Cross-Compilation Support

### Exec/Target Platform Transition

- New `pycross_exec_platform_transition` (`pycross/private/build/transitions.bzl`).
- Solves: build deps need TARGET Python version but EXEC platform.
- Switches `--platforms` to host while preserving Python version settings.

### Supported Cross-Compilation Targets

- Linux x86_64 → Linux aarch64 (glibc, musl)
- Linux x86_64 → macOS aarch64 (Apple Silicon)
- macOS → macOS (x86_64 ↔ aarch64)
- Configurable `glibc_version` (default 2.28), `musl_version` (default 1.2), `macos_version` (default 15.0).

### Crossenv Integration

- Cross-compilation venvs use the built-in `crossenv` module.
- Polyglot bash/python wrapper script handles sysconfig overrides and EXT_SUFFIX patching.
- Darwin-specific python script wrapper shebang handling.

### Hermetic Compiler Wrappers

- Generated wrapper scripts for CC/CXX that:
  - Filter incompatible linker flags (`--start-group`, `--end-group`, `--as-needed`)
  - Inject target/sysroot flags
  - Handle `-nostdlibinc` toolchains

---

## New: Providers

### `PycrossExtractedWheelInfo`

- `site_packages` — TreeArtifact of the installed site-packages directory.
- Returned by `pycross_wheel_library`.

### `PycrossPackageInfo`

- `package_name` — normalized package name.
- `package_version` — package version string.
- `site_paths` — list of importable site-packages paths.
- `bin_paths` — list of bin paths.
- `data_paths` — list of data paths.
- `include_paths` — list of include paths.
- Returned by `pycross_wheel_library` when `package_name` is set.
- Used by `pep517_build` to validate `build-system.requires`.

### `PycrossPathToolInfo`

- `executable` — the executable file.
- `name` — the name to use on PATH.
- Returned by `pycross_wheel_library` path tool targets.

---

## New: Utility Rules

### `pycross_cc_pkg_config`

- Generates `.pc` (pkg-config) files from `CcInfo` provider targets.
- Bridges Bazel CC deps into Meson/CMake build systems.
- Attrs: `dep`, `lib_name`, `version`, `description`.

### `pycross_wheel_headers`

- Extracts C/C++ headers from installed wheels (e.g., numpy headers).
- Returns `CcInfo` for downstream native builds.
- Optional `make_variable` for embedding include paths in Meson cross files or config settings.

### `pycross_repaired_wheel`

- Standalone rule for wheel repair (auditwheel/delocate).
- Can be used independently of the build pipeline.

### `pycross_wheel_transform`

- Post-processing rule for arbitrary wheel transformations.
- Takes a user-provided transform tool executable.
- Supports environment variable expansion with make variables and `$(location)`.

### `pycross_console_script_binary` (removed)

- This rule has been removed. Use `py_console_script_binary` from rules_python instead.
- See `@rules_python//python/entry_points:py_console_script_binary.bzl`.

---

## New: Package Annotations

### `pre_build_patches`

- Patches applied to the sdist source tree *before* the PEP 517 build.
- Available on `lock_import.package()` and `package_annotation()`.
- Uses `label_list` type — labels resolve relative to the user's workspace.

### `site_hooks`

- Python code snippets executed on interpreter startup during builds.
- First-class attribute on `lock_import.package()` (previously required `backend_attrs` hack).
- Injected via `_pycross_hooks.py` in the build venv.

### `build_backend`

- Explicit backend override per package (e.g., `build_backend = "meson_build"`).
- Bypasses pyproject.toml auto-detection.

---

## New: Automatic Build System Detection

### `inspect_package.py`

- New tool that reads `pyproject.toml` from sdists to extract `build-system.build-backend` and `build-system.requires`.
- Used at repository rule time by `pycross_sdist_repo`.

### `pycross_sdist_repo` repository rule

- Auto-generates BUILD files for sdist packages.
- Maps pyproject.toml `build-backend` to pycross rules via the backend registry.
- Maps `build-system.requires` to workspace repo targets.
- Applies backend-specific override configs.
- Supports `SDIST_HOOKS` for backend-specific repo generation (e.g., maturin Cargo.lock).

### Auto-detected `build_dependencies`

- Build dependencies from `build-system.requires` in pyproject.toml / uv.lock are now resolved automatically.
- Explicit `build_dependencies` overrides in `lock_import.package()` are no longer necessary for most packages.

---

## New: Lock File Infrastructure

### TOML-based internal lock file

- `pycross_deps.toml` replaces generated `.lock.bzl` files.
- Human-readable, includes pins, package metadata, URLs, and dependency graphs.
- Generated by `toml_lock_generator.py`.

### Pure-Starlark lock rendering

- `resolved_lock_renderer.bzl` renders lock structures in pure Starlark (no Python tool invocation at repo time).
- `package_repo.bzl` rewritten as a pure-Starlark workspace repository rule.
- Versioned subdirectory layout: `<package>/v<version>/BUILD.bazel`.

### Package repo deduplication

- Audited and verified that wheel/sdist repo rules are correctly deduplicated across multiple lock imports.
- Root-level `_sdist` aliases only generated when package actually has an sdist file.

### `patch-ng` bootstrapping

- `patch-ng` is now bundled as a wheel dependency (no more `http_archive` override).
- Available via `@rules_pycross_internal//:patch_ng_whl`.
- Used for `pre_build_patches` and `post_install_patches`.

---

## New: uv Lock Format Freshness (0.9.5)

- Test coverage for uv lock format version 0.9.5.
- Support for top-level `resolution-markers` (forked resolution).
- Handling of `revision` field in lock metadata.
- Tested: forked dependencies (same package, different versions per Python version).

---

## Changed: `pycross_wheel_library` Enhancements

- Now accepts wheels as raw `.whl` files or TreeArtifact directories (auto-detected via `is_directory`).
- Returns `PycrossExtractedWheelInfo` (site-packages tree artifact).
- Returns `PycrossPackageInfo` when `package_name`/`package_version` attrs are set.
- Conditionally populates `PyInfo.venv_symlinks` with `VenvSymlinkEntry` objects when `VenvsSitePackages` is enabled.
- New `site_paths` attribute for explicit importable package declaration (renamed from `top_level_packages`).
- New `bin_paths`, `data_paths`, `include_paths` attributes for additional venv symlink categories.
- `:dist_info` output group for compatibility with rules_python's entry point discovery.

---

## Changed: Environment Configuration

### Environments V2: Per-Platform Version Configuration

New `platform()` and `python()` tag classes on the `environments` extension, inspired by llvm's `exec()`/`target()` tag pattern.

#### Auto-discover Python versions (common case)

```python
environments = use_extension("@rules_pycross//pycross/extensions:environments.bzl", "environments")

environments.create_for_python_toolchains(
    glibc_version = "2.28",   # default
    macos_version = "15.0",   # default
)

# Per-platform overrides — cross-product with discovered Python versions is generated.
environments.platform(target = "x86_64-unknown-linux-gnu", glibc_version = "2.35")
environments.platform(target = "aarch64-unknown-linux-gnu")  # inherits glibc 2.28
environments.platform(target = "aarch64-apple-darwin")

use_repo(environments, "pycross_environments")
```

#### Explicit Python versions (BYOT)

```python
environments.create(
    name = "my_envs",
    glibc_version = "2.28",
)

environments.python(envs = "my_envs", version = "3.11.6")
environments.python(envs = "my_envs", version = "3.12.0")

environments.platform(envs = "my_envs", target = "x86_64-unknown-linux-gnu", glibc_version = "2.35")
environments.platform(envs = "my_envs", target = "aarch64-apple-darwin")

use_repo(environments, "my_envs")
```

#### Key Design Points

- `platform()` tags are mutually exclusive with the `platforms` list on `create_for_python_toolchains` — use one or the other.
- `envs` attribute defaults to `"pycross_environments"` — optional for the common single-repo case.
- `create()` with `python()` tags supports BYOT (bring your own toolchain) scenarios.
- Backwards compatible: existing `create_for_python_toolchains` with `platforms` list continues to work.

### Other Environment Changes

- `configure_environments` now supports `macos_version` (default 15.0).
- Default `glibc_version` is now 2.28 (was unspecified).
- Default Python version for internal tooling bumped to 3.13.

---

## New: `pycross_wheel_dir` Rule & Whldir Convention

- New `pycross_wheel_dir` rule wraps a `.whl` file into a TreeArtifact directory named `{name}-{version}.whldir`.
- Pre-built wheels now get consistent TreeArtifact output like sdist-built wheels.
- Hub repo `_wheel/` package uses `pycross_wheel_dir` to wrap on demand; `pycross_wheel_file` exposes the raw `.whl` again (no unnecessary copy actions).
- Renamed `wheelhouse` → `whldir` globally: CLI args, Python fields, Starlark variables, struct fields, and config JSON keys.
- New `whldir_name` attribute in `COMMON_BUILD_ATTRS`.

---

## New: E2E Test Suite

### Reorganized test structure

- Old `e2e/build_wheel/` replaced by focused test directories:
  - `e2e/build_cmake/` — iminuit (scikit-build-core)
  - `e2e/build_maturin/` — rpds-py, jiter (Rust)
  - `e2e/build_meson/` — numpy, pandas, contourpy, pywavelets
  - `e2e/build_pure_python/` — tomli, filelock, pyproject-metadata
  - `e2e/build_setuptools/` — psycopg2, setproctitle, pyyaml, zstandard
  - `e2e/patches_and_hooks/` — setproctitle with pre/post patches and site_hooks
  - `e2e/sdist_repo/` — sdist repository rule e2e test
  - `e2e/requirements/` — top-level package imports, `requirement()` macro
  - `e2e/uv_workspace/` — UV workspace import with multi-member lock, per-member overrides
  - `e2e/namespace_pkgs/` — namespace package resolution across multiple packages
  - `e2e/squash_extras/` — extras squashing behavior
  - `e2e/always_build/` — always-build flag behavior
  - `e2e/gazelle_integration/` — Gazelle modules_mapping integration
  - `e2e/local_wheel/` — local wheel files
  - `e2e/generate_lock/` — lock file generation
- Shared configuration via `e2e/shared/` with common `.bazelrc`, overrides, and utilities.
- `collect_wheels.bzl` macro for cross-platform wheel collection.
- `compare_wheels.py` tool for wheel comparison.
- `test_top_level_packages.py` — verifies dist→import name mapping, importability, and site-packages layout.

---

## New: Unit Test Coverage

### 101 Python unit tests + 5 Starlark analysis tests = 106 total

| Area | Tests | Files |
|------|-------|-------|
| uv translator | 15 | `uv_translator_test.py` |
| pdm translator | 2 | `pdm_translator_test.py` |
| poetry translator | 5 | `poetry_translator_test.py` |
| pylock translator | 15 | `pylock_translator_test.py` |
| translator_utils | 12 | `translator_utils_test.py` |
| Raw lock resolver | 23 | `raw_lock_resolver_test.py` |
| Resolved lock renderer (Python) | 4 | `resolved_lock_renderer_test.py` |
| Resolved lock renderer (Starlark) | 5 | `test_resolved_lock_renderer.bzl` |
| inspect_package | 14 | `inspect_package_test.py` |
| Build utils (cc_toolchain, hooks, lifecycle, meson, venv) | 14 | various `*_test.py` |
| TOML lock generator | 1 | `toml_lock_generator_test.py` |
| Starlark unit tests | 8 | `test_common_attrs.bzl`, `test_override_helpers.bzl` |
| Starlark analysis tests | 15 | `tests/analysis/*.bzl` (including conflict_check_aspect) |

### Key coverage areas

- **Extras support** — regex parsing, per-env deps, renderer `[extra]` targets
- **Cycle detection** — 2-node, 3-node, multi-cycle, stable naming, no-cycle case
- **pylock group filtering** — `--no-default-group`, optional/dev groups, `include-group`, graph traversal
- **site_paths** — wheel/sdist detection, src-layout, excluded dirs, `__init__.py` requirement
- **Renderer layout** — versioned paths, env config_settings, cycle `_cycles/` dir, extras targets

---

## Internal / Infrastructure

- Added `@toml.bzl` dependency for TOML parsing in Starlark.
- Docs isolated into a separate Bazel module (`docs/MODULE.bazel`) to fix dependency cycle.
- Added gazelle setup for `backend_maturin` submodule.
- Pre-commit hooks: added `gazelle`, `docs-update`, bumped `buildifier`.
- Removed `stardoc` dev dep from root MODULE (moved to docs module).
- `EXTRA_PATTERN` regex and `import re` moved to module level in resolver.
- Missing dependency warnings in pylock translator (instead of silent skip).

---

## New: V1 Backward Compatibility

- `pycross_wheel_build` has been restored as a backward-compatible wrapper macro (defaulting to `setuptools_build`).
- V1 compatibility attributes are now fully supported across all V2 build backends: `build_env`, `data`, `pre_build_hooks`, `post_build_hooks`, and `path_tools`.
- Backward-compatible macro `requirement()` is provided in generated repositories. The legacy `all_whl_requirements` list has been removed because rules_pycross compiles source distributions and cannot guarantee a homogeneous list of raw `.whl` files.
- E2E tests guarantee V1 attribute compatibility under the V2 architecture.

---

## Changed: Always-Repair Wheels

- Wheel repair (`repairwheel` wrapper over `auditwheel`/`delocate`) is now run unconditionally across all build backends (`pep517_build`, `setuptools_build`, `meson_build`, `cmake_build`, `maturin_build`), rather than only when `native_deps` are present.
- This ensures maximum reproducibility (consistent timestamps, compression, ordering) for all built wheels, even pure-Python ones.

---

## New: Git Packages and URL Subdirectory Sources

- **Git sources**: Full support for packages installed directly from git repositories in `uv.lock`. Handled via a new `pycross_git_file` repository rule that natively creates deterministic `.tar.gz` source distributions.
- **URL subdirectories**: Support for URL-based sdists that use a `#subdirectory=` fragment (common in monorepos where the buildable package is not at the repo root).
- Supported transparently via translation in the lock model, threading the `source_dir` down to the PEP 517 build context.

---

## Changed: Lock Repo Layout and Extras

- **Underscore naming**: Generated package pin directories now strictly replace dashes with underscores, avoiding Bazel label validation issues in certain configurations.
- **Root extras aliases**: Generated repositories now expose aliases for extras directly at the root (e.g., `@repo//:pkg[extra]`).
- **`--squash-extras`**: A new flag has been added to the lock resolver and model generation. This allows users to squash all extra dependencies into the base package target, providing a flatter dependency graph for environments migrating from V1.

---

## Changed: Sysconfig Base Prefix Resolution

- Fixed an issue where `sys.base_prefix` resolved incorrectly when using `rules_python` hermetic interpreter wrappers (pointing to the wrapper directory instead of the actual python installation root).
- Pycross now interrogates the target interpreter directly for its `installed_base` and `installed_platbase` sysconfig variables, ensuring C extensions and native builds correctly locate Python headers (`Python.h`).

---

## New: Gazelle Integration Improvements

- **`pycross_modules_mapping`**: A new rule that aggregates `modules_mapping.json` for `rules_python_gazelle_plugin`. It reads directly from the `PycrossPackageInfo.site_paths` metadata, completely eliminating the need to extract wheels at analysis time.
- V2 target layout aligns perfectly with `rules_python_gazelle_plugin`'s default label conventions, removing the need for custom `gazelle:python_label_convention` directives.

---

## Changed: Hermeticity, Mnemonics, and Path Mapping

- **Strict Hermeticity**: Replaced all non-hermetic `run_shell` actions (which used host `cp`, `mkdir`, `chmod`) with pure-Python tooling scripts (`copy_file.py`, `extract_wheel_bin.py`).
- **Environment Scrubbing**: Systematically scrubbed Bazel's `py_binary` launcher variables (`PYTHONSAFEPATH`, `PYTHONPATH`, `PYTHONHOME`, `RUNFILES_DIR`, etc.) from all subprocess environments (`pep517_build`, `repairwheel`) to prevent host environment leaks.
- **Action Mnemonics**: Renamed all action mnemonics to use a standard `Pycross*` prefix (e.g., `PycrossPep517Build`, `PycrossWheelInstall`) for better cache filtering and profiling readability.
- **Path Mapping**: Opted all executing actions into `execution_requirements = {"supports-path-mapping": "1"}` to improve caching hit rates across differently-named execution environments.

---

## New: `.pth` Files and Namespace Packages Support

- **`.pth` files**: `inspect_package.py` now recognizes root-level `.pth` files in wheels/sdists and includes them in `site_paths`, ensuring `rules_python` symlinks them into the venv `site-packages`.
- **Implicit Namespace Packages**: Expanded E2E test coverage validating that packages sharing implicit PEP 420 namespace packages (e.g., `google-cloud-storage` and `google-cloud-bigquery`) resolve seamlessly in `rules_python` venvs without symlink collisions.

---

## Changed: Lazy Wheel Metadata and Modules Mapping

Eliminated a major repository fetching bottleneck. Previously, `package_repo` eagerly fetched every wheel repository at repo generation time to read `inspection.json` for `site_paths` and to generate `modules_mapping.json`. This caused sequential fetching of all wheels.

### New Architecture

- **`pycross_wheel_metadata` rule**: A lightweight Starlark rule that wraps a wheel file and provides `PycrossPackageInfo` (including `site_paths`) without requiring the wheel to be fetched at repo generation time.
- **Provider-based metadata**: `pycross_wheel_library` now reads `site_paths` from the wheel's `PycrossPackageInfo` provider at build time, falling back to the explicit `site_paths` attribute.
- **Build-time `modules_mapping`**: The `pycross_modules_mapping` rule generates `modules_mapping.json` lazily during Gazelle builds instead of eagerly at repo generation time.
- **Wheel repos**: `pycross_wheel_file` now instantiates `pycross_wheel_metadata` in its BUILD file, embedding `site_paths` from the local `inspection.json`.
- **Sdist repos**: `pycross_sdist_repo` wraps the backend build output with `pycross_wheel_metadata` for consistent provider propagation.

### Impact

- Wheel repositories are now fetched on-demand (in parallel) rather than sequentially during repo generation.
- `modules_mapping.json` is only computed when a Gazelle target is built, not on every `bazel build`.

---

## Changed: Extra Squashing at the Alias Layer

Previously, `--squash-extras` was applied at translation time, mutating the lock data to merge all extra dependencies into the base package. This made the resolved lock non-canonical and complicated workspace merging.

### New Approach

- The lock resolver now emits a `squash_extras` boolean flag alongside the canonical (un-squashed) dependency graph.
- The lock renderer generates `py_library(name = "<pkg_key>[_all_]@<version>")` targets that aggregate the base package and all its extras.
- `package_repo.bzl` and `thin_package_repo.bzl` read `squash_extras` and point their aliases to the `[_all_]` variant when enabled.
- Extra aliases (`[extra_name]`) also point to the squashed target when squashing is active.

This preserves the canonical dependency graph in the lock, enabling correct workspace merging while letting each repo decide its squashing policy at the alias layer.

---

## New: Shared Translator Logic (`translator_utils`)

Extracted the common dependency graph resolution algorithm from the uv, pdm, and poetry translators into `translator_utils.py`.

- **`PackageProtocol`**: A `runtime_checkable` Protocol defining the interface each translator's `Package` class must implement (`satisfies_dependency`, `satisfies_pin`, `add_resolved_dependency`, `to_lock_package`).
- **`resolve_lock_graph()`**: The shared function that groups packages by name, resolves dependencies (newest-first), pins packages, elides local packages, and produces the final `RawLockSet`.
- Net reduction of ~22 lines despite adding a new module.
- Dedicated unit tests in `translator_utils_test.py`.

---

## Tips: Extracting Files from Wheel TreeArtifacts

The `:pkg` target for each package produces a TreeArtifact containing the full extracted wheel layout:

```
<pkg>/
├── site-packages/      # Python modules (purelib + platlib)
├── bin/                # Console scripts and entry points
├── include/            # C/C++ headers
└── data/               # Data files
```

To extract individual files (e.g., a binary like `ruff`), use [`@aspect_bazel_lib`](https://github.com/bazel-contrib/bazel-lib)'s `directory_path` and `copy_file`:

```python
load("@aspect_bazel_lib//lib:directory_path.bzl", "directory_path")
load("@aspect_bazel_lib//lib:copy_file.bzl", "copy_file")

directory_path(
    name = "_ruff_binary_path",
    directory = "@pypi//ruff:pkg",
    path = "bin/ruff",
)

copy_file(
    name = "_ruff_exe",
    src = ":_ruff_binary_path",
    out = "ruff_exe",
    is_executable = True,
    visibility = ["//visibility:public"],
)
```

This is the pycross equivalent of rules_python's `select_file` + `extracted_whl_files` pattern.
