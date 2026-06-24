<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Setuptools Rust overrides extension.

<a id="setuptools_rust"></a>

## setuptools_rust

<pre>
setuptools_rust = use_extension("@rules_pycross_backend_maturin//extensions:setuptools_rust.bzl", "setuptools_rust")
setuptools_rust.override(<a href="#setuptools_rust.override-name">name</a>, <a href="#setuptools_rust.override-data">data</a>, <a href="#setuptools_rust.override-build_env">build_env</a>, <a href="#setuptools_rust.override-cargo_lock">cargo_lock</a>, <a href="#setuptools_rust.override-config_settings">config_settings</a>, <a href="#setuptools_rust.override-copts">copts</a>, <a href="#setuptools_rust.override-linkopts">linkopts</a>,
                         <a href="#setuptools_rust.override-native_deps">native_deps</a>, <a href="#setuptools_rust.override-path_tools">path_tools</a>, <a href="#setuptools_rust.override-post_build_hooks">post_build_hooks</a>, <a href="#setuptools_rust.override-pre_build_hooks">pre_build_hooks</a>, <a href="#setuptools_rust.override-repo">repo</a>, <a href="#setuptools_rust.override-sdist">sdist</a>,
                         <a href="#setuptools_rust.override-tool_deps">tool_deps</a>, <a href="#setuptools_rust.override-workspace">workspace</a>)
</pre>


**TAG CLASSES**

<a id="setuptools_rust.override"></a>

### override

Specify setuptools-rust-specific package overrides.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="setuptools_rust.override-name"></a>name |  The package key (name or name@version).   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="setuptools_rust.override-data"></a>data |  Additional data and dependencies used by the build.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_rust.override-build_env"></a>build_env |  Extra environment variables passed to the sdist build.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="setuptools_rust.override-cargo_lock"></a>cargo_lock |  A Cargo.lock file to use. If not provided, the sdist's own Cargo.lock is used.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="setuptools_rust.override-config_settings"></a>config_settings |  Setup configuration arguments.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="setuptools_rust.override-copts"></a>copts |  Extra C++ compiler options.   | List of strings | optional |  `[]`  |
| <a id="setuptools_rust.override-linkopts"></a>linkopts |  Extra linker options.   | List of strings | optional |  `[]`  |
| <a id="setuptools_rust.override-native_deps"></a>native_deps |  CC dependencies to link against.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_rust.override-path_tools"></a>path_tools |  A list of binary targets placed on PATH during the build.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_rust.override-post_build_hooks"></a>post_build_hooks |  Executables to run after the wheel is built.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_rust.override-pre_build_hooks"></a>pre_build_hooks |  Executables to run before building the wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_rust.override-repo"></a>repo |  The repository name (if applying to a specific lock file).   | String | optional |  `""`  |
| <a id="setuptools_rust.override-sdist"></a>sdist |  Label to the sdist target. Used to resolve repository visibility in the generated _cargo repo.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="setuptools_rust.override-tool_deps"></a>tool_deps |  Overrides for built-in dependencies.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="setuptools_rust.override-workspace"></a>workspace |  The workspace name (if applying to all members of a workspace).   | String | optional |  `""`  |


