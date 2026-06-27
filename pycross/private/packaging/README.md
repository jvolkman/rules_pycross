# Python Packaging Utilities in Starlark

The logic in this directory is derived from the following upstream projects:

1. **[pypa/packaging](https://github.com/pypa/packaging)**
   * **Baseline**: Derived from release **26.2**.
   * **Purpose**: Core logic for PEP 440 versions, specifiers, PEP 508 markers, and PEP 425 compatibility tags (including platform expansion for macOS, manylinux, musllinux, Android, and iOS).
   * **License**: Dual licensed under the **Apache License, Version 2.0** or the **BSD 2-Clause License**.

2. **[pypa/pip](https://github.com/pypa/pip)**
   * **Purpose**: Wrapper logic for handling custom platform strings and legacy aliases in tag generation.
   * **License**: **MIT License**.

## Directory Structure

* **`version/`**: PEP 440 version parsing and comparison.
* **`specifiers/`**: PEP 440 version specifiers (`==`, `>=`, `~=`, etc.).
* **`markers/`**: PEP 508 environment markers parsing and evaluation.
* **`tags/`**: PEP 425 platform tag generation and expansion.

## Modifications

The original Python implementations have been ported to Starlark (`.bzl`) to allow evaluation during Bazel's analysis phase without requiring a Python interpreter. The core algorithms and compatibility rules remain faithful to the upstream implementations.

See individual `.bzl` files for specific upstream sources and detailed documentation.
