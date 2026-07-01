# Raw Lock Model Format

This document describes the internal JSON format used by `rules_pycross` to represent locked dependencies. This format is produced by translators (e.g., PDM, Poetry, UV, Pylock) and consumed by the lock resolver.

## Overview

The raw lock model is a JSON object containing information about packages, pins (top-level dependencies), supported Python versions, and optional variants.

## Top-Level Fields

- `python_versions`: (String) A PEP 440 specifier string indicating the supported Python versions for this lock file (e.g., `>=3.8`).
- `packages`: (Object) A dictionary mapping package keys to Package objects.
- `pins`: (Object) A dictionary mapping canonical package names to Pin values.
- `variants`: (Array of VariantSet Objects, Optional) A list of variant sets (used by UV).

---

## Package Key

Package keys are strings in the format `name@version`, where `name` is the canonicalized package name (normalized per PEP 503).

Example: `requests@2.31.0`, `urllib3[socks]@2.2.3`

---

## Package Object

A Package object represents a specific version of a Python package and its dependencies.

### Fields

- `name`: (String) The canonicalized name of the package. May include extras in brackets (e.g., `requests` or `urllib3[socks]`).
- `version`: (String) The version of the package.
- `python_versions`: (String) PEP 440 specifier string for supported Python versions for this package.
- `dependencies`: (Array of Dependency Objects) List of dependencies required by this package.
- `files`: (Array of File Objects) List of files (wheels, sdists) available for this package.
- `python_version_specifiers`: (Array of Strings, Optional) List of PEP 440 specifier strings derived from resolution markers.
- `source_dir`: (String, Optional) Subdirectory within the source (e.g., for git dependencies).

---

## Dependency Object

Represents a dependency of a package.

### Fields

- `name`: (String) The canonicalized name of the dependent package. May include extras.
- `version`: (String) The version or specifier of the dependency (e.g., `2.31.0` or `==2.31.0`).
- `marker`: (String) PEP 508 environment marker string (e.g., `python_version >= '3.10'`, `sys_platform == 'linux'`). May be empty.
- `specifier`: (String) PEP 440 specifier string.

---

## File Object

Represents a file (wheel or sdist) associated with a package.

### Fields

- `name`: (String) The filename (e.g., `requests-2.31.0-py3-none-any.whl`).
- `sha256`: (String) The SHA256 hash of the file (without `sha256:` prefix).
- `urls`: (Array of Strings, Optional) List of URLs where the file can be downloaded.

---

## Pin Value

Top-level pins identify the root dependencies of the project.

- For **unconditional** dependencies, the pin value is a simple string (the Package Key).
  - Example: `"requests": "requests@2.31.0"`
- For **conditional/conflicting** dependencies (variants), the pin value is an Object mapping constraint names to Package Keys.
  - Example:

    ```json
    "torch": {
      "extra_cpu": "torch@2.6.0",
      "extra_cu124": "torch@2.7.0"
    }
    ```

---

## VariantSet Object (UV Only)

Represents a set of mutually exclusive variant items (conflicts).

### Fields

- `items`: (Array of VariantItem Objects) List of items participating in the conflict.

---

## VariantItem Object

### Fields

- `package`: (String) The workspace member name this variant belongs to.
- `kind`: (String) One of `"extra"`, `"group"`, or `"project"`.
- `name`: (String, Optional) The extra or group name. Empty for project-level variants.
- `default`: (Boolean, Optional) True if this item is a default selection.
