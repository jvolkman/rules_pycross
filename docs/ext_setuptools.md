<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Setuptools build backend for rules_pycross.

<a id="setuptools_build"></a>

## setuptools_build

<pre>
load("@rules_pycross//pycross/backends:setuptools.bzl", "setuptools_build")

setuptools_build(<a href="#setuptools_build-name">name</a>, <a href="#setuptools_build-deps">deps</a>, <a href="#setuptools_build-build_deps">build_deps</a>, <a href="#setuptools_build-config_settings">config_settings</a>, <a href="#setuptools_build-copts">copts</a>, <a href="#setuptools_build-linkopts">linkopts</a>, <a href="#setuptools_build-native_deps">native_deps</a>, <a href="#setuptools_build-path_tools">path_tools</a>,
                 <a href="#setuptools_build-pkg_config_files">pkg_config_files</a>, <a href="#setuptools_build-pre_build_patches">pre_build_patches</a>, <a href="#setuptools_build-sdist">sdist</a>, <a href="#setuptools_build-site_hooks">site_hooks</a>, <a href="#setuptools_build-target_environment">target_environment</a>,
                 <a href="#setuptools_build-tool_deps">tool_deps</a>, <a href="#setuptools_build-whldir_name">whldir_name</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="setuptools_build-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="setuptools_build-deps"></a>deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_build-build_deps"></a>build_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_build-config_settings"></a>config_settings |  -   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="setuptools_build-copts"></a>copts |  -   | List of strings | optional |  `[]`  |
| <a id="setuptools_build-linkopts"></a>linkopts |  -   | List of strings | optional |  `[]`  |
| <a id="setuptools_build-native_deps"></a>native_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_build-path_tools"></a>path_tools |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_build-pkg_config_files"></a>pkg_config_files |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_build-pre_build_patches"></a>pre_build_patches |  Patch files to apply to the sdist source tree before building.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_build-sdist"></a>sdist |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="setuptools_build-site_hooks"></a>site_hooks |  Python code snippets to execute on interpreter startup during builds.   | List of strings | optional |  `[]`  |
| <a id="setuptools_build-target_environment"></a>target_environment |  The target environment mapping JSON (resolved dynamically via alias filegroup).   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@@rules_pycross++environments+pycross_environments//:current"`  |
| <a id="setuptools_build-tool_deps"></a>tool_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="setuptools_build-whldir_name"></a>whldir_name |  Name for the output .whldir TreeArtifact directory (e.g., 'numpy-1.24.0.whldir'). If empty, defaults to '{name}.whldir'.   | String | optional |  `""`  |


<a id="setuptools"></a>

## setuptools

<pre>
setuptools = use_extension("@rules_pycross//pycross/backends:setuptools.bzl", "setuptools")
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


