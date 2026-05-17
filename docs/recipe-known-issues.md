# Recipe System — Known Issues & Design Cracks

Tracking document for issues discovered during initial implementation.
Check items off as they're resolved.

---

## High Priority

### ~~1. `-shared` leaks into Meson cross-file `c_link_args`~~ ✅ RESOLVED

**Fix:** Switched from parsing `LDSHARED` (Python sysconfig, contains
`cc -shared <toolchain flags>`) to reading `LDFLAGS` (just `-L` paths
for native deps). The CC wrapper already has all toolchain link flags
baked in, so `c_link_args` only needs extra library search paths.
Removed `_strip_leading_compiler()` entirely.

- [x] Use LDFLAGS instead of LDSHARED in meson_cross_file_hook.py

### ~~2. `required_dep_names` is never validated~~ ✅ RESOLVED

**Fix:** Moved validation to build-time in `wheel_builder.py` using
`importlib.metadata` and `packaging.requirements`. The Starlark rule passes
`--require-dep` args to the builder, which shells out to the build venv's
Python to check each requirement. This properly validates against the actual
installed packages (not fragile Bazel label parsing) and supports full PEP 508
version specifiers (e.g., `"setuptools>=68.0"`, `"cython>=3.0,<4.0"`).

- [x] Implement validation of required_dep_names
- [x] Support PEP 508 version specifiers

### ~~3. Hook environment is too permissive~~ ✅ RESOLVED

**Fix:** Cleaned up environment leaking by thoroughly popping off implementation details from the rules_python stub/launcher (e.g., `PYTHONHOME`, `PYTHONPATH`, `RUNFILES_*`, `PYTHON_RUNFILES`). Corrected the pre-build hook environment creation to use the sanitized `build_env` dictionary rather than re-overlaying `os.environ` (which previously un-stripped the sanitized variables). Removed Meson-specific hardcoded `NINJA` propagation, transferring the discovery cleanly to the Meson cross-file hook.

- [x] Curate and sanitize the hook subprocess environment
- [x] Eliminate redundant rules_python launcher environment variables

---

## Medium Priority

### ~~4. `longdouble_format` is NumPy-specific, not a Meson concept~~ ✅ RESOLVED

**File:** `pycross/private/tools/meson_cross_file_hook.py`

`longdouble_format` is a NumPy custom property read via
`meson.get_external_property()` — not a Meson built-in. It doesn't
belong in the generic meson cross-file hook. SciPy also uses it, but
pandas, scikit-learn, and other Meson packages do not.

The auto-detection lookup table is also incomplete for:
- `i686` (should be `INTEL_EXTENDED_12_BYTES_LE`)
- `ppc64le` (`IEEE_QUAD_LE` on modern glibc, `IBM_DOUBLE_DOUBLE_LE` on older)
- `s390x` (`IEEE_QUAD_BE`)
- `riscv64` (`IEEE_QUAD_LE`)

**Fix:** Extract `longdouble_format` from the generic meson hook. The
meson hook should support injecting arbitrary `[properties]` via the
recipe data file mechanism (see #11). NumPy/SciPy recipes declare
`longdouble_format` through recipe data; the meson hook reads it and
writes it to the cross-file `[properties]` section. Auto-detection can
remain as a convenience default for common architectures.

- [x] Extract `longdouble_format` to NumPy recipe data
- [x] Add generic `[properties]` injection to meson hook via recipe data
- [x] Expand architecture coverage for auto-detection default

### ~~5. `-L` as a wrapper flag is a blunt instrument~~ ✅ RESOLVED

**Fix:** Split the pre-classified wrapper flag prefixes list into a common wrapper flags list and a linker-specific list (`_LINKER_WRAPPER_FLAG_PREFIXES` which includes `-L`). Added an `is_linker` boolean flag to `classify_flags` in Starlark, passing `is_linker = True` only when classifying `cxx_linker_shared` linker flags. This ensures any `-L` flags in compiler parameters remain unmodified in compile flags like `CFLAGS` and `CXXFLAGS`, avoiding issues with setuptools-backed packages that parse `CFLAGS` for library paths.

- [x] Evaluate and resolve `-L` in CFLAGS breaking setuptools-backed packages
- [x] Implement per-action wrapper flag classification in Starlark

### 6. Cross-file is all-or-nothing

**File:** `pycross/private/tools/meson_cross_file_hook.py`

The hook either generates a full cross-file (cross) or does nothing
(native). Missing middle ground:

- **Same-OS different-arch** (x86_64 → aarch64 Linux with QEMU): could
  use `exe_wrapper = 'qemu-aarch64-static'` instead of
  `needs_exe_wrapper = true`.
- **Native with overrides**: user might want a native file to override
  specific Meson settings without entering cross mode.

- [ ] Support `exe_wrapper` configuration
- [ ] Consider native-file generation for non-cross builds

### ~~7. Recipe `build_env` can't use `$(location)`~~ ✅ RESOLVED (by investigation)

**Finding:** `$(location)` expansion already works in recipe `build_env`.
The recipe stores raw strings with `$(location ...)` placeholders, and
expansion happens in `pycross_wheel_build`'s `ctx` at
`_handle_build_env()` (line 302 of `wheel_build.bzl`). The only
requirement is that referenced targets must appear in the consuming
`pycross_wheel_build`'s `data` attribute.

This was a documentation gap, not an architectural limitation. For
structured data (not env vars), see #11.

- [x] Confirmed `$(location)` works in recipe `build_env`
- [ ] Document the `data` dependency requirement

---

## Low Priority / Watch Items

### 8. `--sysroot=/dev/null` dependency

The entire linking story relies on the Bazel LLVM toolchain providing
explicit `-L` and `-B` paths to compensate for `--sysroot=/dev/null`.
If the toolchain changes its glibc/CRT packaging (different directory
layout, tree artifacts), builds break with cryptic linker errors. We also
assume sandbox absolute paths remain valid inside wheel_builder
subprocesses — true today but an implementation detail of `linux-sandbox`.

### 9. No automated tests

Zero tests for:
- `classify_flags()` flag classification
- `flatten_recipe_chain()` chain merging
- `meson_cross_file_hook.py` cross-file generation
- Hook environment propagation
- Runfiles propagation through recipe chains

The only "test" is "does numpy build." A Bazel upgrade changing flag
ordering or sandbox behavior won't be caught until a user reports it.

- [ ] Add Starlark unit tests for `classify_flags` and `flatten_recipe_chain`
- [ ] Add Python unit tests for meson hook
- [ ] Add integration test for recipe-based wheel build

### ~~10. `RECIPE_ATTRS` sharing is incomplete~~ ✅ RESOLVED

**Fix:** Imported `RECIPE_ATTRS` from `build_recipe.bzl` directly into
`wheel_build.bzl` and updated the attributes dictionary in
`pycross_wheel_build = rule(...)` using `_PYCROSS_WHEEL_BUILD_ATTRS.update(RECIPE_ATTRS)`.
This keeps both definitions in sync automatically and avoids attribute drift.

- [x] Have `wheel_build.bzl` consume `RECIPE_ATTRS` directly

---

## Architectural / v2

### ~~11. Recipe data files (keyed file mapping)~~ ✅ RESOLVED

Recipes need a way to pass structured data to hooks beyond flat env
vars. Current workarounds (JSON-in-env-vars, magic naming conventions)
are fragile and don't compose well across recipe types.

**Design:** Add a `recipe_data` attribute to `RECIPE_ATTRS` as a
`label_keyed_string_dict`. Each entry maps a file target to a logical
name. `flatten_recipe_chain` merges them (child overrides parent for
same name). `pycross_wheel_build` stages these files and exposes them
via `PYCROSS_RECIPE_DATA_DIR`.

```starlark
pycross_build_recipe(
    name = "numpy_recipe",
    parent = "//pycross/recipes:meson",
    recipe_data = {
        ":cross_properties.json": "meson/cross_properties.json",
    },
)
```

Hooks read files by convention from `$PYCROSS_RECIPE_DATA_DIR`:
```python
props = Path(os.environ["PYCROSS_RECIPE_DATA_DIR"]) / "meson/cross_properties.json"
```

This solves:
- **#4**: meson hook reads `meson/cross_properties.json` for `longdouble_format`
  and other custom `[properties]`, keeping the hook generic.
- **#7 (data aspect)**: recipes can reference files with predictable names
  without encoding paths into env vars.
- **Future recipes**: CMake recipes contribute `cmake/toolchain.cmake`,
  Maturin recipes contribute `rust/config.toml`, etc.

- [x] Add `recipe_data` (`label_keyed_string_dict`) to `RECIPE_ATTRS`
- [x] Add `recipe_data` field to `PycrossBuildRecipeInfo` provider
- [x] Merge recipe_data in `flatten_recipe_chain`
- [x] Stage files and set `PYCROSS_RECIPE_DATA_DIR` in `wheel_builder.py`
- [x] Migrate `longdouble_format` to use recipe_data

### 12. Split post-build hooks into separate Bazel actions

Currently the entire wheel build (extract sdist → pre-hooks → PEP 517
build → post-hooks) is one monolithic Bazel action. This means changing
a post-build hook (e.g., adding `repair_wheel`) re-triggers the entire
expensive wheel build.

**Design:** Split post-build hooks into independent Bazel actions that
each take a wheel file in and produce a wheel file out. The action graph
becomes:

```
[Action 1: prepare + build]
  extract sdist → run pre-hooks (subprocess) → PEP 517 build → raw.whl

[Action 2: post-hook 1]
  raw.whl → repaired.whl

[Action 3: post-hook 2]
  repaired.whl → final.whl
```

Pre-build hooks stay as subprocesses within the build action because
they may modify the extracted sdist in-place, which would require tree
artifacts at the boundary. Post-build hooks are pure file→file
transforms with no shared state — ideal for separate actions.

A generic `pycross_wheel_hook` rule wraps user-provided hook binaries:
```starlark
pycross_wheel_hook(
    name = "repair_numpy",
    binary = "@rules_pycross//pycross/hooks:repair_wheel",
    wheel = ":numpy_build",
)
```

**Benefits:**
- Post-hook changes don't rebuild the wheel (the main caching win)
- Each post-hook step visible in `bazel aquery`
- Independent post-hooks can parallelize
- Users still write simple Python scripts — just also a one-line rule

- [ ] Design `pycross_wheel_hook` rule interface
- [ ] Define hook I/O contract (env vars, input/output paths)
- [ ] Prototype with `repair_wheel` as first separate action
- [ ] Evaluate migration path from current hook protocol

---

## Packages That Will Stress-Test This

| Package | Build System | Challenge |
|---|---|---|
| SciPy | Meson | Fortran compiler needed — no Fortran in hermetic toolchain |
| Pillow | setuptools | Native deps (zlib, libjpeg) — exercises native dep linking |
| cryptography | maturin | Rust toolchain — completely different build system, needs its own recipe |
| PyArrow | CMake | Needs a CMake recipe, not Meson |
| pandas | Meson + Cython | Cython + Meson interaction |
| grpcio | custom setup.py | Subprocesses, env assumptions, protobuf codegen |
| torch | CMake + custom | Massive, GPU deps, custom build orchestration |

