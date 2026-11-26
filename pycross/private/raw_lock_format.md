# Raw Lock Model Format

This document describes the internal JSON format used by `rules_pycross` to represent locked dependencies. This format is produced by translators (e.g., PDM, Poetry, UV, Pylock) and consumed by the lock resolver.

## Overview

The raw lock model is a JSON object containing information about packages, pins (top-level dependencies), testonly pins, and optional resolution-marker expressions, root dependency markers, and variants.

## Top-Level Fields

- `packages`: (Object) A dictionary mapping package keys to Package objects.
- `pins`: (Object) A dictionary mapping canonical package names to Pin values.
- `testonly_pins`: (Array of Strings) Sorted list of pin names that are exclusively reachable from testonly dependency groups.
- `variants`: (Array of VariantSet Objects, Optional) A list of variant sets (used by UV).
- `resolution_marker_exprs`: (Object, Optional) A dictionary mapping constraint names for resolution-marker forks (or UV conflict edge splits) to PEP 508 marker expression strings, or to compound `{"variant": ..., "marker": ...}` objects combining a UV variant constraint with a marker constraint.
- `root_dependency_markers`: (Object, Optional) A dictionary mapping root pin names (including extras) to lists of PEP 508 environment marker strings under which root projects request them. Only pins that are exclusively requested under markers appear here.

---

## Package Key

Package keys are strings in the format `name@version` (or `name@version~tag` when multiple locked entries share the same `(name, version)` from distinct sources), where `name` is the canonicalized package name (normalized per PEP 503).

Example: `requests@2.31.0`, `urllib3[socks]@2.2.3`, `torch@2.9.1~a1b2c3d4`

---

## Package Object

A Package object represents a specific version of a Python package and its dependencies.

### Fields

- `name`: (String) The canonicalized name of the package. May include extras in brackets (e.g., `requests` or `urllib3[socks]`).
- `version`: (String) The version of the package.
- `dependencies`: (Array of Dependency Objects) List of dependencies required by this package.
- `files`: (Array of File Objects) List of files (wheels, sdists) available for this package.
- `source_dir`: (String, Optional) Subdirectory within the source (e.g., for git dependencies).
- `source`: (String, Optional) Human-readable source identifier (e.g., index or git URL) present on source-disambiguated (`~tag`) packages.

---

## Dependency Object

Represents a dependency of a package.

### Fields

- `name`: (String) The canonicalized name of the dependent package. May include extras.
- `version`: (String) The resolved version of the dependency (e.g., `2.31.0`).
- `marker`: (String) PEP 508 environment marker string (e.g., `python_version >= '3.10'`, `sys_platform == 'linux'`). May be empty.
- `key`: (String, Optional) Full target package key (including `~tag`) when referencing a source-disambiguated package.

---

## File Object

Represents a file (wheel or sdist) associated with a package.

### Fields

- `name`: (String) The filename (e.g., `requests-2.31.0-py3-none-any.whl`).
- `sha256`: (String) The SHA256 hash of the file (without `sha256:` prefix).
- `package_name`: (String) The canonicalized name of the package this file belongs to.
- `package_version`: (String) The version of the package this file belongs to.
- `urls`: (Array of Strings, Optional) List of URLs where the file can be downloaded.
- `index`: (String, Optional) Simple Repository API index URL for this file (e.g., `https://pypi.org/simple`), when recorded by the lock file.

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
- `repo_pin`: (String, Optional) The internal name of the only item of the set that the repo generated from this lock requests (e.g. `package_<package>`, `extra_<package>_<name>`, or `group_<package>_<name>`). The repo's transition pins it, as `uv sync --package <package>` or `uv sync --extra <name>` selects that item. Never set for the workspace's `__build` repo.
- `repo_requested`: (Array of Strings, Optional) The internal names of the items of the set that the repo generated from this lock requests. The repo uses it to ignore other repos' flags for items it can't use.
- `repo_default`: (String, Optional) When the repo requests several items of the set, the internal name of the item it selects by default: a group from the selected pyproject's `[tool.uv] default-groups` (`group_<package>_<name>`), or, in a mixed `{package = ...}` set, the one project whose default dependencies the repo requests (`package_<package>`). The repo's transition applies it.

---

## VariantItem Object

### Fields

- `package`: (String) The workspace member name this variant belongs to.
- `kind`: (String) One of `"extra"`, `"group"`, or `"project"`.
- `name`: (String, Optional) The extra or group name. Empty for project-level variants.
- `flags`: (Array of Strings, Optional) The `@<repo>//_variants` flags that enable this item in the repo generated from this lock: `<kind>_<name>` (e.g. `group_test`, shared by all of the repo's projects that declare that extra/group) and `<kind>_<package>_<name>` (e.g. `group_app-a_test`, this item only), or `package_<package>` for project items. Only set for items declared by the repo's own projects.
