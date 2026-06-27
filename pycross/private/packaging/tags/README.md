# Platform Tags

The logic in this directory is derived from the following upstream projects:

1. **[pypa/packaging](https://github.com/pypa/packaging)**
   * **Purpose**: Core logic for PEP 425 compatibility tags, including platform expansion for macOS, manylinux, musllinux, Android, and iOS.
   * **License**: Dual licensed under the **Apache License, Version 2.0** or the **BSD 2-Clause License**.

2. **[pypa/pip](https://github.com/pypa/pip)**
   * **Purpose**: Wrapper logic for handling custom platform strings and legacy aliases.
   * **License**: **MIT License**.

## Modifications

The original Python implementations have been ported to Starlark (`.bzl`) to allow tag evaluation during Bazel's analysis phase without requiring a Python interpreter. The core algorithms and compatibility rules remain faithful to the upstream implementations.

See individual `.bzl` files for specific upstream sources.
