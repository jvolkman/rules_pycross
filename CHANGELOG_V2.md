# rules_pycross v2 — Changelog

> Comprehensive feature list for the `dev/v2` branch compared to `main`.
> 97 commits, 326 files changed, +11,289 / −5,891 lines.

---

## Breaking Changes

### Removed: WORKSPACE support

- Deleted `pycross/workspace.bzl`, `pycross/repositories.bzl`, `pycross/private/lock_repo.bzl`, `pycross/private/lock_file_repo.bzl`.
- All `WORKSPACE.bazel` files removed from e2e tests.
- Bzlmod is now the only supported module system.

### Removed: `pycross_wheel_build` rule

- The monolithic `pycross_wheel_build` rule ([wheel_build.bzl](file:///usr/local/google/home/volkman/repos/rules_pycross/pycross/private/wheel_build.bzl)) and its backing `wheel_builder.py` (1,087 lines) have been deleted.
- Replaced by the new pluggable backend architecture (see below).

### Removed: `pycross_lock_file` rule

- Deleted `pycross/private/lock_file.bzl`, `pycross/extensions/lock_file.bzl`, `pycross/private/bzlmod/lock_file.bzl`.
- Lock file generation is now handled entirely through `lock_import` + `lock_repos` extensions.

### Removed: `pycross_wheel_zipimport_library` from public API

- No longer re-exported from `pycross/defs.bzl`.

### Removed: `PycrossWheelInfo` from `pycross_wheel_library` outputs

- `pycross_wheel_library` no longer returns `PycrossWheelInfo` in its providers list.
- It now strictly represents an *installed* wheel and returns `PycrossExtractedWheelInfo`, `DefaultInfo`, `PyInfo`, and optionally `PycrossPackageInfo`.
- Upstream builder rules (e.g. `pep517_build`, `meson_build`) still return `PycrossWheelInfo` for the raw `.whl` file.

### Changed: `pycross_console_script_binary` API

- The `wheel` attribute has been removed. The rule now requires `pkg` (a target providing `PycrossExtractedWheelInfo`).
- The macro now wraps the extracted script in a real `py_binary`, inheriting all deps from the package.
- New optional `deps` argument for injecting additional dependencies (e.g., plugins).

### Changed: Internal dependency format

- Replaced the generated `.lock.bzl` files (`pycross_deps.lock.bzl`, `pycross_deps_core.lock.bzl`) with a human-readable TOML lock file ([pycross_deps.toml](file:///usr/local/google/home/volkman/repos/rules_pycross/pycross/private/pycross_deps.toml)).
- Internal `http_file` repos are now created dynamically from the TOML at module extension time using `@toml.bzl`.

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

- New file: [pycross/backend.bzl](file:///usr/local/google/home/volkman/repos/rules_pycross/pycross/backend.bzl)
- Exports all building blocks for implementing custom backends:
  - Providers: `PycrossWheelInfo`, `PycrossExtractedWheelInfo`, `PycrossPackageInfo`
  - Actions: `extract_cc_layer`, `register_pep517_action`, `register_repair_action`, `register_bin_extract_action`
  - Attributes: `COMMON_BUILD_ATTRS`, `CC_BUILD_ATTRS`, `CC_TOOLCHAIN_ATTRS`
  - Transition: `pycross_exec_platform_transition`
  - Utilities: `get_unzipped_wheel`, `get_wheel_file`, `group_tool_deps`
  - Override helpers: `make_override_extension`, `create_overrides_repo`, `encode_build_system_attrs`

### Override Extensions (per-backend)

- Factory pattern via `make_override_extension()` — each backend creates its override extension with minimal boilerplate.
- Override tags: `name`, `repo`, plus backend-specific build system attrs (`copts`, `linkopts`, `native_deps`, `config_settings`, `tool_deps`).
- Overrides stored as JSON, applied at sdist repo resolution time.

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

- New `pycross_exec_platform_transition` ([transitions.bzl](file:///usr/local/google/home/volkman/repos/rules_pycross/pycross/private/build/transitions.bzl)).
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
- Returned by `pycross_wheel_library` when `package_name` is set.
- Used by `pep517_build` to validate `build-system.requires`.

### `PycrossWheelInfo` (enhanced)

- Added `wheel_directory` field — TreeArtifact containing the wheel file under its proper name.

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

### `pycross_console_script_binary` (rewritten)

- Now wraps extracted scripts in a proper `py_binary`.
- Inherits all dependencies from the source package.
- New `deps` argument for additional dependencies (plugin discovery).
- Usable directly via `bazel run`.

---

## New: Package Annotations

### `pre_build_patches`

- Patches applied to the sdist source tree *before* the PEP 517 build.
- Available on `lock_import.package()` and `package_annotation()`.

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
- Maps `build-system.requires` to hub repo targets.
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
- `package_repo.bzl` rewritten as a pure-Starlark hub repository rule.

### `patch-ng` bootstrapping

- `patch-ng` is now bundled as a wheel dependency (no more `http_archive` override).
- Available via `@rules_pycross_internal//:patch_ng_whl`.
- Used for `pre_build_patches` and `post_install_patches`.

---

## New: E2E Test Suite

### Reorganized test structure

- Old `e2e/build_wheel/` replaced by focused test directories:
  - `e2e/build_cmake/` — iminuit (scikit-build-core)
  - `e2e/build_maturin/` — rpds-py, captcha-rs (Rust)
  - `e2e/build_meson/` — numpy, pandas, contourpy, pywavelets
  - `e2e/build_pure_python/` — tomli, filelock, pyproject-metadata
  - `e2e/build_setuptools/` — psycopg2, setproctitle, pyyaml, zstandard
  - `e2e/patches_and_hooks/` — setproctitle with pre/post patches and site_hooks

- Shared configuration via `e2e/shared/` with common `.bazelrc`, overrides, and utilities.
- `collect_wheels.bzl` macro for cross-platform wheel collection.
- `compare_wheels.py` tool for wheel comparison.

### CI improvements

- New `cross-build.yml` workflow for cross-compilation CI.
- Collapsed e2e test and repro matrices.
- Removed WORKSPACE-mode testing.

---

## Changed: `pycross_wheel_library` Enhancements

- Now accepts wheels from `PycrossWheelInfo` targets *or* raw `.whl` files (via `allow_files = True`).
- Supports `wheel_directory` TreeArtifact from `PycrossWheelInfo`.
- Returns `PycrossExtractedWheelInfo` (site-packages tree artifact).
- Returns `PycrossPackageInfo` when `package_name`/`package_version` attrs are set.
- No longer returns `PycrossWheelInfo` (separation of concerns: installed vs. raw).

---

## Changed: Environment Configuration

- `configure_environments` now supports `macos_version` (default 15.0).
- Default `glibc_version` is now 2.28 (was unspecified).
- Default Python version for internal tooling bumped to 3.13.

---

## Internal / Infrastructure

- Added `@toml.bzl` dependency for TOML parsing in Starlark.
- Docs isolated into a separate Bazel module (`docs/MODULE.bazel`) to fix dependency cycle.
- Added gazelle setup for `backend_maturin` submodule.
- Pre-commit hooks: added `gazelle`, `docs-update`, bumped `buildifier`.
- Removed `stardoc` dev dep from root MODULE (moved to docs module).
