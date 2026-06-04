<!-- Generated with Stardoc: http://skydoc.bazel.build -->

CMake overrides extension.

<a id="cmake"></a>

## cmake

<pre>
cmake = use_extension("@rules_pycross//pycross/extensions:cmake.bzl", "cmake")
cmake.override(<a href="#cmake.override-name">name</a>, <a href="#cmake.override-config_settings">config_settings</a>, <a href="#cmake.override-copts">copts</a>, <a href="#cmake.override-linkopts">linkopts</a>, <a href="#cmake.override-native_deps">native_deps</a>, <a href="#cmake.override-repo">repo</a>, <a href="#cmake.override-tool_deps">tool_deps</a>)
</pre>


**TAG CLASSES**

<a id="cmake.override"></a>

### override

Specify cmake-specific package overrides.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="cmake.override-name"></a>name |  The package key (name or name@version).   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="cmake.override-config_settings"></a>config_settings |  Setup configuration arguments.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="cmake.override-copts"></a>copts |  Extra C++ compiler options.   | List of strings | optional |  `[]`  |
| <a id="cmake.override-linkopts"></a>linkopts |  Extra linker options.   | List of strings | optional |  `[]`  |
| <a id="cmake.override-native_deps"></a>native_deps |  CC dependencies to link against.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="cmake.override-repo"></a>repo |  The repository name   | String | required |  |
| <a id="cmake.override-tool_deps"></a>tool_deps |  Overrides for built-in dependencies.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |


