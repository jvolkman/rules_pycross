<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Setuptools overrides extension.

<a id="setuptools"></a>

## setuptools

<pre>
setuptools = use_extension("@rules_pycross//pycross/extensions:setuptools.bzl", "setuptools")
setuptools.override(<a href="#setuptools.override-name">name</a>, <a href="#setuptools.override-config_settings">config_settings</a>, <a href="#setuptools.override-copts">copts</a>, <a href="#setuptools.override-linkopts">linkopts</a>, <a href="#setuptools.override-native_deps">native_deps</a>, <a href="#setuptools.override-repo">repo</a>, <a href="#setuptools.override-tool_deps">tool_deps</a>)
</pre>


**TAG CLASSES**

<a id="setuptools.override"></a>

### override

Specify setuptools-specific package overrides.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="setuptools.override-name"></a>name |  The package key (name or name@version).   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="setuptools.override-config_settings"></a>config_settings |  Setup configuration arguments.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="setuptools.override-copts"></a>copts |  Extra C++ compiler options.   | List of strings | optional |  `[]`  |
| <a id="setuptools.override-linkopts"></a>linkopts |  Extra linker options.   | List of strings | optional |  `[]`  |
| <a id="setuptools.override-native_deps"></a>native_deps |  CC dependencies to link against.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools.override-repo"></a>repo |  The repository name   | String | required |  |
| <a id="setuptools.override-tool_deps"></a>tool_deps |  Overrides for built-in dependencies.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |


