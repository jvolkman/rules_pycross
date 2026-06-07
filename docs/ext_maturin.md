<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Maturin overrides extension.

Provides the `maturin_overrides` module extension with an `override` tag class
for declaring maturin-specific package overrides. Generates:

  1. `@maturin_overrides//:overrides.json` — consumed by lock_import via
     `lock_import.override_source(file = ...)`.

  2. `@<repo>_cargo//` repos — containing `pycross_generate_cargo_lock` targets
     for each maturin-overridden package.

<a id="maturin"></a>

## maturin

<pre>
maturin = use_extension("@rules_pycross_backend_maturin//extensions:maturin.bzl", "maturin")
maturin.override(<a href="#maturin.override-name">name</a>, <a href="#maturin.override-cargo_lock">cargo_lock</a>, <a href="#maturin.override-config_settings">config_settings</a>, <a href="#maturin.override-copts">copts</a>, <a href="#maturin.override-linkopts">linkopts</a>, <a href="#maturin.override-native_deps">native_deps</a>, <a href="#maturin.override-repo">repo</a>, <a href="#maturin.override-sdist">sdist</a>,
                 <a href="#maturin.override-tool_deps">tool_deps</a>)
</pre>


**TAG CLASSES**

<a id="maturin.override"></a>

### override

Specify maturin-specific package overrides.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="maturin.override-name"></a>name |  The package name.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="maturin.override-cargo_lock"></a>cargo_lock |  A Cargo.lock file to use. If not provided, the sdist's own Cargo.lock is used.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="maturin.override-config_settings"></a>config_settings |  Setup configuration arguments.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="maturin.override-copts"></a>copts |  Extra C++ compiler options.   | List of strings | optional |  `[]`  |
| <a id="maturin.override-linkopts"></a>linkopts |  Extra linker options.   | List of strings | optional |  `[]`  |
| <a id="maturin.override-native_deps"></a>native_deps |  CC dependencies to link against.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="maturin.override-repo"></a>repo |  The lock repo this override applies to.   | String | required |  |
| <a id="maturin.override-sdist"></a>sdist |  Label to the sdist target (e.g. @uv//pkg:sdist). Used to resolve repository visibility in the generated _cargo repo.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="maturin.override-tool_deps"></a>tool_deps |  Overrides for built-in dependencies.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |


