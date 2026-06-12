<!-- Generated with Stardoc: http://skydoc.bazel.build -->

CMake build backend for rules_pycross.

<a id="cmake_build"></a>

## cmake_build

<pre>
load("@rules_pycross//pycross/backends:cmake.bzl", "cmake_build")

cmake_build(<a href="#cmake_build-name">name</a>, <a href="#cmake_build-deps">deps</a>, <a href="#cmake_build-data">data</a>, <a href="#cmake_build-build_deps">build_deps</a>, <a href="#cmake_build-build_env">build_env</a>, <a href="#cmake_build-config_settings">config_settings</a>, <a href="#cmake_build-copts">copts</a>, <a href="#cmake_build-linkopts">linkopts</a>, <a href="#cmake_build-native_deps">native_deps</a>,
            <a href="#cmake_build-path_tools">path_tools</a>, <a href="#cmake_build-pkg_config_files">pkg_config_files</a>, <a href="#cmake_build-post_build_hooks">post_build_hooks</a>, <a href="#cmake_build-pre_build_hooks">pre_build_hooks</a>, <a href="#cmake_build-pre_build_patches">pre_build_patches</a>, <a href="#cmake_build-sdist">sdist</a>,
            <a href="#cmake_build-site_hooks">site_hooks</a>, <a href="#cmake_build-target_environment">target_environment</a>, <a href="#cmake_build-tool_deps">tool_deps</a>, <a href="#cmake_build-whldir_name">whldir_name</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="cmake_build-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="cmake_build-deps"></a>deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="cmake_build-data"></a>data |  Additional data and dependencies used by the build. These files are made available in the sandbox and can be referenced via $(location) in build_env and config_settings values.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="cmake_build-build_deps"></a>build_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="cmake_build-build_env"></a>build_env |  Environment variables passed to the sdist build. Values are subject to 'Make variable' and $(location) expansion.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="cmake_build-config_settings"></a>config_settings |  -   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="cmake_build-copts"></a>copts |  -   | List of strings | optional |  `[]`  |
| <a id="cmake_build-linkopts"></a>linkopts |  -   | List of strings | optional |  `[]`  |
| <a id="cmake_build-native_deps"></a>native_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="cmake_build-path_tools"></a>path_tools |  A mapping of binary targets to names placed on PATH during the build. If the name (value) is empty, the executable's basename is used.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: Label -> String</a> | optional |  `{}`  |
| <a id="cmake_build-pkg_config_files"></a>pkg_config_files |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="cmake_build-post_build_hooks"></a>post_build_hooks |  Executables to run after the wheel is built. Each hook receives PYCROSS_WHEEL_FILE pointing to the built wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="cmake_build-pre_build_hooks"></a>pre_build_hooks |  Executables to run before building the wheel. Each hook receives PYCROSS_CONFIG_SETTINGS_FILE and PYCROSS_ENV_VARS_FILE environment variables pointing to JSON files it may read and modify.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="cmake_build-pre_build_patches"></a>pre_build_patches |  Patch files to apply to the sdist source tree before building.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="cmake_build-sdist"></a>sdist |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="cmake_build-site_hooks"></a>site_hooks |  Python code snippets to execute on interpreter startup during builds.   | List of strings | optional |  `[]`  |
| <a id="cmake_build-target_environment"></a>target_environment |  The target environment mapping JSON (resolved dynamically via alias filegroup).   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@@rules_pycross++environments+pycross_environments//:current"`  |
| <a id="cmake_build-tool_deps"></a>tool_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="cmake_build-whldir_name"></a>whldir_name |  Name for the output .whldir TreeArtifact directory (e.g., 'numpy-1.24.0.whldir'). If empty, defaults to '{name}.whldir'.   | String | optional |  `""`  |


<a id="cmake"></a>

## cmake

<pre>
cmake = use_extension("@rules_pycross//pycross/backends:cmake.bzl", "cmake")
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


