<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Setuptools Rust overrides extension.

<a id="setuptools_rust"></a>

## setuptools_rust

<pre>
setuptools_rust = use_extension("@rules_pycross_backend_maturin//extensions:setuptools_rust.bzl", "setuptools_rust")
setuptools_rust.override(<a href="#setuptools_rust.override-name">name</a>, <a href="#setuptools_rust.override-data">data</a>, <a href="#setuptools_rust.override-build_env">build_env</a>, <a href="#setuptools_rust.override-cargo_lock">cargo_lock</a>, <a href="#setuptools_rust.override-config_settings">config_settings</a>, <a href="#setuptools_rust.override-copts">copts</a>, <a href="#setuptools_rust.override-linkopts">linkopts</a>,
                         <a href="#setuptools_rust.override-native_deps">native_deps</a>, <a href="#setuptools_rust.override-path_tools">path_tools</a>, <a href="#setuptools_rust.override-post_build_hooks">post_build_hooks</a>, <a href="#setuptools_rust.override-pre_build_hooks">pre_build_hooks</a>,
                         <a href="#setuptools_rust.override-repair_exclude_globs">repair_exclude_globs</a>, <a href="#setuptools_rust.override-tool_deps">tool_deps</a>, <a href="#setuptools_rust.override-workspace">workspace</a>)
</pre>


**TAG CLASSES**

<a id="setuptools_rust.override"></a>

### override

Specify setuptools-rust-specific package overrides.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="setuptools_rust.override-name"></a>name |  The package name, `name@version`, or '*' to apply to all packages built with this backend. For a package `name@version`, matching entries are layered from least to most specific (`*`, then `name`, then `name@version`); each field set by a more specific entry replaces the less specific value. The version must match a locked version exactly.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="setuptools_rust.override-data"></a>data |  Additional data and dependencies used by the build.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_rust.override-build_env"></a>build_env |  Extra environment variables passed to the sdist build.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="setuptools_rust.override-cargo_lock"></a>cargo_lock |  A Cargo.lock file to use. If not provided, the sdist's own Cargo.lock is used.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="setuptools_rust.override-config_settings"></a>config_settings |  Setup configuration arguments.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="setuptools_rust.override-copts"></a>copts |  Extra C++ compiler options.   | List of strings | optional |  `[]`  |
| <a id="setuptools_rust.override-linkopts"></a>linkopts |  Extra linker options.   | List of strings | optional |  `[]`  |
| <a id="setuptools_rust.override-native_deps"></a>native_deps |  CC dependencies to link against.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_rust.override-path_tools"></a>path_tools |  A list of binary targets placed on PATH during the build, under their basename. Wrap a target in `pycross_path_tool` to give it a different name on PATH.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_rust.override-post_build_hooks"></a>post_build_hooks |  Executables to run after the wheel is built.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_rust.override-pre_build_hooks"></a>pre_build_hooks |  Executables to run before building the wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_rust.override-repair_exclude_globs"></a>repair_exclude_globs |  Shared library globs to exclude from wheel repair; assumed provided at runtime.   | List of strings | optional |  `[]`  |
| <a id="setuptools_rust.override-tool_deps"></a>tool_deps |  Overrides for the backend's tool packages, keyed by tool package name (e.g. `{"cmake": "@other//cmake:pkg"}`). Each entry replaces the auto-detected default for that tool, or adds it if the tool is not in the lock. Keys must be one of the backend's tool packages (or `repairwheel`), and each value must be a pycross package target for that package.   | Dictionary: String -> Label | optional |  `{}`  |
| <a id="setuptools_rust.override-workspace"></a>workspace |  The workspace whose packages this override applies to.   | String | required |  |


