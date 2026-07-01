# `rules_pycross` Changelog

All notable changes to this project will be documented in this file.

## [unreleased]

### Breaking

- **`configure_environments` is deprecated.** Use `configure_toolchains` instead.
  The old name still works but prints a deprecation warning.
- **`pycross_target_environment` rule removed.** Replaced by
  `pycross_target_platform`, which derives platform tags from the active
  `rules_python` toolchain at analysis time.
- **`environments` extension removed.** Platform configuration is now handled
  entirely by `configure_toolchains` and Bazel's native `@platforms` constraints.
- **`pip` is no longer a dependency.** The Python-based target environment
  generator that required pip has been removed.
- **Workspace repo names changed** from `foo_pkgs` to `foo__pkgs` (#245).

### Added

- **Unified `lock` extension.** Added a single `lock` module extension that
  replaces the two-step `lock_import` + `lock_repos` pattern. The new extension
  handles lock file translation, dependency resolution, and repo creation in one
  pass. Legacy extensions are deprecated but remain functional.
- **PEP 508 marker evaluation at analysis time.** Conditional dependencies
  (e.g., `colorama; sys_platform == "win32"`) now generate `select()`
  expressions in the lock file, enabling true cross-platform builds without
  re-running lock import.
- **PEP 425 wheel tag matching.** New `pycross_wheel_chooser` rule selects
  the best-matching wheel at analysis time based on the active Python toolchain,
  with automatic sdist fallback.
- **`pycross_target_platform` rule.** Generates PEP 425-compatible tags
  (interpreter, ABI, platform) from `rules_python` toolchain configuration,
  including libc variant and freethreaded support.
- **`pycross_pep508_evaluator` rule.** Evaluates PEP 508 marker expressions
  against Bazel config settings, producing match/no-match flags for `select()`.
- **Marker-aware cycle resolution.** Cycle group dependencies are now gated
  behind `select()` so platform-specific deps don't trigger eager repo fetches.
  Tarjan's SCC algorithm runs over the full dependency graph for correct
  detection of all cycles.
- **Starlark port of `pypa/packaging`.** Pure-Starlark implementations of
  PEP 440 versions, PEP 508 markers, PEP 425 tags, and specifiers under
  `//pycross/private/pypackaging` (#251, #252).
- **`setuptools-rust` build backend.** Auto-detected via bracket-notation
  matching when `setuptools-rust` appears in `build-system.requires` (#249).
- **Variant resolver layer** for conflict set enforcement (#246).
- **`resource_sets` support** in sdist build rules for better resource
  management during parallel builds (#247).
- **`pycross_library_proxy` and `pycross_file_proxy` rules.** Proxy rules
  that forward Python package providers (PyInfo, PycrossExtractedWheelInfo,
  PycrossPackageInfo, OutputGroupInfo) from a primary target, optionally
  merging additional deps. Replaces `py_library` wrappers in generated lock
  repos to preserve pycross-specific providers.
- **Platform transitions for thin package repos.** New `flags`,
  `constraint_values`, and `platform` attributes on `uv_member`,
  `uv_all_members`, `import_uv`, and equivalent PDM/Poetry/Pylock tags.
  When specified, proxy targets in the thin repo apply a `--platforms`
  transition, enabling variant flags or architecture constraints to be
  locked to a workspace member without per-invocation `--flag` arguments.
  When `flags` are used, a custom `_transition.bzl` is generated in the
  thin repo that sets both `--platforms` and individual flag values directly
  in the transition (since Bazel's `platform(flags=[...])` does not apply
  via Starlark transitions).

### Changed

- Python version, libc variant, and freethreaded status are now read from
  the `rules_python` toolchain at analysis time instead of being pre-declared.
- `configure_toolchains` versions pipe through to `build_setting_default` on
  `string_flag` settings, unifying flag defaults.
- Package name normalization consolidated on `pypackaging.canonicalize_name`.
- Default macOS version bumped to 15.0.
- Updated `repairwheel` to 0.6.2.
- Extras-only packages in the lock repo (e.g., `package[extra]@version`)
  now use `pycross_library_proxy` with `actual` pointing to the base
  package, instead of `py_library`. This preserves pycross-specific
  providers through extra targets.
- Cycle member wrappers and extras aggregate (`[_all_]`) targets in the
  lock repo now use `pycross_library_proxy` instead of `py_library`.

### Fixed

- **Eager fetching of cross-platform repos.** Switched `repo_map` from
  `label_keyed_string_dict` to `string_dict` to prevent Bazel from fetching
  all platform-specific wheel repos at analysis time.
- **Duplicate `build_deps` in sdist builds.** Switched to dict-as-set pattern
  to deduplicate when the same package appears via different requirement
  specifiers.
- **Multi-tag wheel handling.** Fixed resolver to correctly handle compound
  platform tags like `manylinux_2_17_x86_64.manylinux2014_x86_64`.

## [2.0.0-alpha.0]

This is a major release with breaking changes. See the
[README](README.md) for a usage guide.

### Removed

- **WORKSPACE support.** Bzlmod is now the only supported module system. All
  WORKSPACE rules have been removed.
- **lock.bzl vendoring.** It's no longer possible to generate, vendor, and
  load a pycross lock.bzl file. `pycross_lock_file` is removed. Users should
  use the bzlmod extensions for importing supported lock formats directly.
- **`PycrossWheelInfo` provider.** Build rules now return a `TreeArtifact`
  containing the wheel with an appropriate name.

### Added and Changed

- **Pluggable build backend system.** The monolithic `pycross_wheel_build` is
  replaced by modular backends that auto-detect from `pyproject.toml`:
  - `pep517_build` — generic PEP 517 (hatchling, flit_core, pdm.backend,
    poetry.core); the default fallback
  - `setuptools_build` — setuptools with native compilation support
  - `meson_build` — meson-python with cross-compilation via generated
    `cross.ini`
  - `cmake_build` — scikit-build-core / scikit-build
  - `maturin_build` — Rust+Python via maturin (separate
    `rules_pycross_backend_maturin` module)
  - All backends provide some amount of cross compilation support between
    Linux and macOS.
- **Backend authoring API** (`pycross/backend.bzl`). Public API for
  implementing custom build backends: providers, actions, attributes,
  transitions, and override helpers.
- **Backend override extensions.** Per-package build customization via
  `setuptools.override()`, `meson.override()`, `cmake.override()`, and
  `maturin.override()` tags. Supports `copts`, `linkopts`, `native_deps`,
  `build_env`, `config_settings`, `pre_build_hooks`, `post_build_hooks`, and
  more.
- **Automatic build system detection.** `pycross_sdist_repo` reads
  `pyproject.toml` from sdists to detect the build backend and resolve
  `build-system.requires` automatically. Explicit `build_dependencies`
  overrides are no longer necessary for most packages.
- **`uv` workspace import.** Three-tier API for monorepos with a single
  `uv.lock` and multiple workspace members: `import_uv_workspace()`,
  `uv_all_members()`, and `uv_member()`. Members share a single backing
  repository for deduplication.
- ** `uv` conflict support.** Auto-generated config settings allowing selection
  of uv conflict entries. For example, `--@uv_deps//_variants:extra_cu124`,
  `--@uv_deps//_variants:extra_cpu`.
- **Multi-workspace lock import.** Multiple lock files can share a workspace
  for deduplication, or each can get its own isolated workspace.
- **pylock.toml support (PEP 751).** Adds support for the `pylock.toml`
  lockfile format.
- **Extras support.** Extras are first-class: the generated repo exposes
  `@repo//pkg` (all requested extras), `@repo//pkg:[]` (base only), and
  `@repo//pkg:[extra]` (specific extra) targets.
- **Automatic cycle resolution.** Circular dependencies are detected via
  Tarjan's SCC algorithm and resolved automatically with content-based group
  naming for stability.
- **Git package sources.** Full support for packages installed from git
  repositories in `uv.lock`, via a `pycross_git_file` repository rule.
- **`pre_build_patches` annotation.** Patches applied to the sdist source tree
  before the PEP 517 build.
- **`site_hooks` annotation.** Python code snippets executed on interpreter
  startup during builds.
- **`build_backend` annotation.** Explicit backend override per package,
  bypassing pyproject.toml auto-detection.
- **`rules_python` layout compatibility.** Pycross lock repos now provide the
  same (or at least largely compatible) target layout as rules_python.
- **`rules_python` venv integration.** Pycross targets are now symlinked into
  rules_python venvs.
- **Unconditional wheel repair.** `repairwheel` runs on all built wheels.

## [0.8.2]

### Added

- Support for uv workspaces (#214)
- `config_setting_group` to match any pycross environment (#217)
- Pass netrc credentials when downloading from PyPI index (#222)
- Support for Bazel 9

### Fixed

- Fix cross-compilation with rules_python ≥ 1.9.0 (#221)
- Resolve relative wheel URLs returned by PyPI-compatible indexes (#224)
- Process nested `.pth` files for wheel build dependencies (#227)
- Fix `pypi_index` attr name passed to `pypi_file` rule (#223)
- Avoid `sort_key` values when creating pycross internal repo (#226)
- Export json files for `--incompatible_no_implicit_file_export` (#219)
- Prefer newest manylinux wheels by sorting expanded platforms (#218)
- Ignore PDM dependencies with markers not met by any target environment (#146)

## [0.8.1]

### Added

- `post_install_patches` to apply patches after installation of wheels (#198)
- Support for pulling `target_settings` from rules_python platforms (#194)
- Support for dependency-groups in PDM (#173)
- Use project dependencies from uv.lock (#186)

### Fixed

- Normalize package names (#208)
- Fix dependency-groups in uv_translator (#203)
- Fix patch application failures (#202)
- Update repairwheel version to fix issue on macOS hosts (#195)
- Bump DEFAULT_MACOS_VERSION (#190)
- Fix parsing package required python versions from uv.lock (#175)
- Fix `all_optional_groups` for `import_poetry` (#174)
- Fix future warnings from tarfile (#169)
- Add missing `py_test` and provider imports (#179)
- Set LDCXXSHARED for wheel builds

## [0.8.0]

### Added

- When importing a lock file, only consider Python versions that match the lock file's
  `requires-python` (or equivalent) set.

### Fixed

- Correctly detect changes to lock files in Bazel 8
- Improved support for -freethreaded Python builds
- Fix cases when packages don't provide sdists
- Fix stringify bug in exception description
- Properly pass `render_args` to `package_repo`

## [0.7.1]

### Added

- Updates to support Bazel 8.0
- uv translator updates
- Adds support for rules_python musl interpreter builds

### Fixed

- Obtain default Python version for Python hub repo from `versions.bzl` file, falling back to `interpreters.bzl` for backwards compatibility. `DEFAULT_PYTHON_VERSION` was [removed](https://github.com/bazelbuild/rules_python/blob/6a04d3832e82fec0a7b0675e9964b360bc358554/CHANGELOG.md?plain=1#L211) from `interpreters.bzl` in rules_python version 1.0.0.

## [0.6.1]

### Added

- Adds a uv lock translator.
- Adds `default_build_dependencies`.

## [0.6.0]

### Added

- Adds `install_exclude_globs` to exclude certain files during installation of wheels.

### Changed

- **BREAKING** Introduce `package_annotation` which replaces `always_build_packages`, `build_target_overrides`,
  `package_build_dependencies` and `package_ignore_dependencies`.

## [0.5.3]

### Fixed

- Using `local_wheels` in `pycross_lock_repo` or the `lock_import` extension resulted in an invalid `select`
  statement being generated.
- Auto toolchain creation compatibility with rules_python 0.30+.
- Fix `pycross` package imports when using `--experimental_python_import_all_repositories`.

### Changed

- Rely on `cfg = 'exec'` when registering toolchains to limit the combinatorial explosion of
  len(python versions) _ len(target platforms) _ len(exec platforms). With this change, we register
  only len(python versions) toolchains.

## [0.5.2]

### Added

- Adds `requirements.bzl` to `lock_repo` with the standard `requirement` function and
  `all_requirements` list.

### Fixed

- Fixed a toolchain resolution issue if the default version toolchain came before the requested toolchain in
  lexicographical order. E.g., if 3.12.0 was the default, and 3.9.18 was requested, the matched toolchain would
  be 3.12.0.
- Fixed an issue where toolchain resolution would fail if the default python version was configured as X.Y
  instead of X.Y.Z

### Changed

- Set default GLIBC version to `2.28`, using [pep600_compliance]
  (https://github.com/mayeut/pep600_compliance#acceptable-distros-to-build-wheels) as a guide.

## [0.5.1]

### Fixed

- Fixed regressions in some examples.
- Bumped `repairwheel` version to fix wheel builds when targeting linux_aarch64.

## [0.5.0]

### Added

- (pycross_lock_file) `disallow_builds` - fail if any `pycross_wheel_build` targets would be generated.
- (pycross_lock_file) `generate_file_map` - generates a `FILES` constant that contains referenced whl
  and sdist files.
- Adds bzlmod support: see extensions under [pycross/extensions](pycross/extensions/).
- Adds a `pycross_lock_repo` WORKSPACE rule. See [example](examples/lock_repo/).

### Changed

- Self-host dependencies; no more `pip_install` dependency.
- PDM translator no longer depends on PDM itself (which was pulling in a bunch of third-party dependencies).
- `PycrossTargetEnvironmentInfo` is removed; environment JSON files are read directly.
- **BREAKING** The original `pycross_lock_repo` is renamed to `pycross_lock_file_repo`.
- `bzl_lock_generator` is split into two components: `raw_lock_resolver` and `resolved_lock_renderer`.
- **BREAKING** (pycross_poetry_lock_model) `poetry_lock_file` and `poetry_project_file` are renamed to `lock_file` and
  `project_file`, mirroring the PDM translator.
- **BREAKING** package names in lock files use Python's own normalization semantics and are no longer undercased.
  For example, `SQLAlchemy-Utils` becomes `:sqlalchemy-utils`, not `:sqlalchemy_utils`.
- **BREAKING** (pycross_lock_file) most of the `*_prefix` (`package_prefix`, `build_prefix`, etc.) are removed.
- WORKSPACE-specific rules are moved from `pycross/defs.bzl` to `pycross/workspace.bzl`.

### Fixed

- Default `pycross_target_platform` abi to `"none"` and platform to `"any"` when not specified, instead of using
  host values.
- Generated lock files satisfy Buildifier.

## [0.4] - 2023-11-24

(No notes - pre-dates this file.)

## [0.3] - 2023-11-22

(No notes - pre-dates this file.)

## [0.2] - 2023-10-16

(No notes - pre-dates this file.)

## [0.1] - 2022-10-18

(No notes - pre-dates this file.)
