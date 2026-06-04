<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Meson build backend for rules_pycross.

<a id="meson_build"></a>

## meson_build

<pre>
load("@rules_pycross//pycross/backends:meson.bzl", "meson_build")

meson_build(<a href="#meson_build-name">name</a>, <a href="#meson_build-deps">deps</a>, <a href="#meson_build-build_deps">build_deps</a>, <a href="#meson_build-config_settings">config_settings</a>, <a href="#meson_build-copts">copts</a>, <a href="#meson_build-linkopts">linkopts</a>, <a href="#meson_build-meson_properties">meson_properties</a>, <a href="#meson_build-native_deps">native_deps</a>,
            <a href="#meson_build-path_tools">path_tools</a>, <a href="#meson_build-pkg_config_files">pkg_config_files</a>, <a href="#meson_build-sdist">sdist</a>, <a href="#meson_build-site_hooks">site_hooks</a>, <a href="#meson_build-target_environment">target_environment</a>, <a href="#meson_build-tool_deps">tool_deps</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="meson_build-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="meson_build-deps"></a>deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-build_deps"></a>build_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-config_settings"></a>config_settings |  -   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="meson_build-copts"></a>copts |  -   | List of strings | optional |  `[]`  |
| <a id="meson_build-linkopts"></a>linkopts |  -   | List of strings | optional |  `[]`  |
| <a id="meson_build-meson_properties"></a>meson_properties |  -   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="meson_build-native_deps"></a>native_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-path_tools"></a>path_tools |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-pkg_config_files"></a>pkg_config_files |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-sdist"></a>sdist |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="meson_build-site_hooks"></a>site_hooks |  -   | List of strings | optional |  `[]`  |
| <a id="meson_build-target_environment"></a>target_environment |  The target environment mapping JSON (resolved dynamically via alias filegroup).   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@@rules_pycross++environments+pycross_environments//:current"`  |
| <a id="meson_build-tool_deps"></a>tool_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="meson"></a>

## meson

<pre>
meson = use_extension("@rules_pycross//pycross/backends:meson.bzl", "meson")
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


