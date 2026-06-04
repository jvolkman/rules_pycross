<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Meson overrides extension.

<a id="meson"></a>

## meson

<pre>
meson = use_extension("@rules_pycross//pycross/extensions:meson.bzl", "meson")
meson.override(<a href="#meson.override-name">name</a>, <a href="#meson.override-config_settings">config_settings</a>, <a href="#meson.override-copts">copts</a>, <a href="#meson.override-linkopts">linkopts</a>, <a href="#meson.override-native_deps">native_deps</a>, <a href="#meson.override-repo">repo</a>, <a href="#meson.override-tool_deps">tool_deps</a>)
</pre>


**TAG CLASSES**

<a id="meson.override"></a>

### override

Specify meson-specific package overrides.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="meson.override-name"></a>name |  The package key (name or name@version).   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="meson.override-config_settings"></a>config_settings |  Setup configuration arguments.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="meson.override-copts"></a>copts |  Extra C++ compiler options.   | List of strings | optional |  `[]`  |
| <a id="meson.override-linkopts"></a>linkopts |  Extra linker options.   | List of strings | optional |  `[]`  |
| <a id="meson.override-native_deps"></a>native_deps |  CC dependencies to link against.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-repo"></a>repo |  The repository name   | String | required |  |
| <a id="meson.override-tool_deps"></a>tool_deps |  Overrides for built-in dependencies.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |


