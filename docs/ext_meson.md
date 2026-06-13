<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Meson build backend for rules_pycross.

<a id="meson_build"></a>

## meson_build

<pre>
load("@rules_pycross//pycross/backends:meson.bzl", "meson_build")

meson_build(<a href="#meson_build-name">name</a>, <a href="#meson_build-deps">deps</a>, <a href="#meson_build-data">data</a>, <a href="#meson_build-build_deps">build_deps</a>, <a href="#meson_build-build_env">build_env</a>, <a href="#meson_build-config_settings">config_settings</a>, <a href="#meson_build-copts">copts</a>, <a href="#meson_build-linkopts">linkopts</a>,
            <a href="#meson_build-meson_properties">meson_properties</a>, <a href="#meson_build-native_deps">native_deps</a>, <a href="#meson_build-path_tools">path_tools</a>, <a href="#meson_build-pkg_config_files">pkg_config_files</a>, <a href="#meson_build-post_build_hooks">post_build_hooks</a>,
            <a href="#meson_build-pre_build_hooks">pre_build_hooks</a>, <a href="#meson_build-pre_build_patches">pre_build_patches</a>, <a href="#meson_build-sdist">sdist</a>, <a href="#meson_build-site_hooks">site_hooks</a>, <a href="#meson_build-source_dir">source_dir</a>, <a href="#meson_build-target_environment">target_environment</a>,
            <a href="#meson_build-tool_deps">tool_deps</a>, <a href="#meson_build-whldir_name">whldir_name</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="meson_build-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="meson_build-deps"></a>deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-data"></a>data |  Additional data and dependencies used by the build. These files are made available in the sandbox and can be referenced via $(location) in build_env and config_settings values.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-build_deps"></a>build_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-build_env"></a>build_env |  Environment variables passed to the sdist build. Values are subject to 'Make variable' and $(location) expansion.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="meson_build-config_settings"></a>config_settings |  -   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="meson_build-copts"></a>copts |  -   | List of strings | optional |  `[]`  |
| <a id="meson_build-linkopts"></a>linkopts |  -   | List of strings | optional |  `[]`  |
| <a id="meson_build-meson_properties"></a>meson_properties |  -   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="meson_build-native_deps"></a>native_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-path_tools"></a>path_tools |  A list of binary targets placed on PATH during the build. Targets can be raw executables or pycross_path_tool targets.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-pkg_config_files"></a>pkg_config_files |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-post_build_hooks"></a>post_build_hooks |  Executables to run after the wheel is built. Each hook receives PYCROSS_WHEEL_FILE pointing to the built wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-pre_build_hooks"></a>pre_build_hooks |  Executables to run before building the wheel. Each hook receives PYCROSS_CONFIG_SETTINGS_FILE and PYCROSS_ENV_VARS_FILE environment variables pointing to JSON files it may read and modify.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-pre_build_patches"></a>pre_build_patches |  Patch files to apply to the sdist source tree before building.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-sdist"></a>sdist |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="meson_build-site_hooks"></a>site_hooks |  Python code snippets to execute on interpreter startup during builds.   | List of strings | optional |  `[]`  |
| <a id="meson_build-source_dir"></a>source_dir |  Subdirectory within the sdist source tree to build.   | String | optional |  `""`  |
| <a id="meson_build-target_environment"></a>target_environment |  The target environment mapping JSON (resolved dynamically via alias filegroup).   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@@rules_pycross++environments+pycross_environments//:current"`  |
| <a id="meson_build-tool_deps"></a>tool_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-whldir_name"></a>whldir_name |  Name for the output .whldir TreeArtifact directory (e.g., 'numpy-1.24.0.whldir'). If empty, defaults to '{name}.whldir'.   | String | optional |  `""`  |


<a id="meson"></a>

## meson

<pre>
meson = use_extension("@rules_pycross//pycross/backends:meson.bzl", "meson")
meson.override(<a href="#meson.override-name">name</a>, <a href="#meson.override-data">data</a>, <a href="#meson.override-build_env">build_env</a>, <a href="#meson.override-config_settings">config_settings</a>, <a href="#meson.override-copts">copts</a>, <a href="#meson.override-linkopts">linkopts</a>, <a href="#meson.override-native_deps">native_deps</a>, <a href="#meson.override-path_tools">path_tools</a>,
               <a href="#meson.override-post_build_hooks">post_build_hooks</a>, <a href="#meson.override-pre_build_hooks">pre_build_hooks</a>, <a href="#meson.override-repo">repo</a>, <a href="#meson.override-tool_deps">tool_deps</a>)
</pre>


**TAG CLASSES**

<a id="meson.override"></a>

### override

Specify meson-specific package overrides.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="meson.override-name"></a>name |  The package key (name or name@version).   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="meson.override-data"></a>data |  Additional data and dependencies used by the build.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-build_env"></a>build_env |  Extra environment variables passed to the sdist build.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="meson.override-config_settings"></a>config_settings |  Setup configuration arguments.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="meson.override-copts"></a>copts |  Extra C++ compiler options.   | List of strings | optional |  `[]`  |
| <a id="meson.override-linkopts"></a>linkopts |  Extra linker options.   | List of strings | optional |  `[]`  |
| <a id="meson.override-native_deps"></a>native_deps |  CC dependencies to link against.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-path_tools"></a>path_tools |  A list of binary targets placed on PATH during the build.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-post_build_hooks"></a>post_build_hooks |  Executables to run after the wheel is built.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-pre_build_hooks"></a>pre_build_hooks |  Executables to run before building the wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-repo"></a>repo |  The repository name   | String | required |  |
| <a id="meson.override-tool_deps"></a>tool_deps |  Overrides for built-in dependencies.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |


