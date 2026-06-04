<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Maturin overrides extension.

Provides the `maturin_overrides` module extension with an `override` tag class
for declaring maturin-specific package overrides. Generates:

  1. `@maturin_overrides//:overrides.json` — consumed by lock_import via
     `lock_import.override_source(file = ...)`.

  2. `@<repo>_cargo//` repos — containing `pycross_generate_cargo_lock` targets
     for each maturin-overridden package.

<a id="maturin_overrides"></a>

## maturin_overrides

<pre>
maturin_overrides = use_extension("@rules_pycross_backend_maturin//extensions:overrides.bzl", "maturin_overrides")
maturin_overrides.override(<a href="#maturin_overrides.override-name">name</a>, <a href="#maturin_overrides.override-always_build">always_build</a>, <a href="#maturin_overrides.override-build_dependencies">build_dependencies</a>, <a href="#maturin_overrides.override-cargo_lock">cargo_lock</a>, <a href="#maturin_overrides.override-config_settings">config_settings</a>,
                           <a href="#maturin_overrides.override-copts">copts</a>, <a href="#maturin_overrides.override-ignore_dependencies">ignore_dependencies</a>, <a href="#maturin_overrides.override-install_exclude_globs">install_exclude_globs</a>, <a href="#maturin_overrides.override-linkopts">linkopts</a>, <a href="#maturin_overrides.override-native_deps">native_deps</a>,
                           <a href="#maturin_overrides.override-post_install_patches">post_install_patches</a>, <a href="#maturin_overrides.override-repo">repo</a>, <a href="#maturin_overrides.override-tool_deps">tool_deps</a>)
</pre>


**TAG CLASSES**

<a id="maturin_overrides.override"></a>

### override

Specify maturin-specific package overrides.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="maturin_overrides.override-name"></a>name |  The package name.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="maturin_overrides.override-always_build"></a>always_build |  If True, don't use pre-built wheels for this package.   | Boolean | optional |  `True`  |
| <a id="maturin_overrides.override-build_dependencies"></a>build_dependencies |  Additional build-time dependencies.   | List of strings | optional |  `[]`  |
| <a id="maturin_overrides.override-cargo_lock"></a>cargo_lock |  A Cargo.lock file to use. If not provided, the sdist's own Cargo.lock is used.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="maturin_overrides.override-config_settings"></a>config_settings |  Setup configuration arguments.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="maturin_overrides.override-copts"></a>copts |  Extra C++ compiler options.   | List of strings | optional |  `[]`  |
| <a id="maturin_overrides.override-ignore_dependencies"></a>ignore_dependencies |  Dependencies to drop from this package.   | List of strings | optional |  `[]`  |
| <a id="maturin_overrides.override-install_exclude_globs"></a>install_exclude_globs |  Globs for files to exclude during installation.   | List of strings | optional |  `[]`  |
| <a id="maturin_overrides.override-linkopts"></a>linkopts |  Extra linker options.   | List of strings | optional |  `[]`  |
| <a id="maturin_overrides.override-native_deps"></a>native_deps |  CC dependencies to link against.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="maturin_overrides.override-post_install_patches"></a>post_install_patches |  Patches to apply after wheel installation.   | List of strings | optional |  `[]`  |
| <a id="maturin_overrides.override-repo"></a>repo |  The lock repo this override applies to.   | String | required |  |
| <a id="maturin_overrides.override-tool_deps"></a>tool_deps |  Overrides for built-in dependencies.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |


