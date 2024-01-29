# `rules_pycross` Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

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

[unreleased]: https://github.com/jvolkman/rules_pycross/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/jvolkman/rules_pycross/compare/v0.4...v0.5.0
[0.4]: https://github.com/jvolkman/rules_pycross/compare/v0.3...v0.4
[0.3]: https://github.com/jvolkman/rules_pycross/compare/v0.2...v0.3
[0.2]: https://github.com/jvolkman/rules_pycross/compare/0.1...v0.2
[0.1]: https://github.com/jvolkman/rules_pycross/releases/tag/0.1
