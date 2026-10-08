<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Meson build backend for rules_pycross.

<a id="meson_build"></a>

## meson_build

<pre>
load("@rules_pycross//pycross/backends:meson.bzl", "meson_build")

meson_build(<a href="#meson_build-name">name</a>, <a href="#meson_build-deps">deps</a>, <a href="#meson_build-data">data</a>, <a href="#meson_build-allow_native_exec">allow_native_exec</a>, <a href="#meson_build-build_deps">build_deps</a>, <a href="#meson_build-build_env">build_env</a>, <a href="#meson_build-config_settings">config_settings</a>, <a href="#meson_build-copts">copts</a>,
            <a href="#meson_build-linkopts">linkopts</a>, <a href="#meson_build-meson_properties">meson_properties</a>, <a href="#meson_build-native_deps">native_deps</a>, <a href="#meson_build-path_tools">path_tools</a>, <a href="#meson_build-pkg_config_files">pkg_config_files</a>, <a href="#meson_build-post_build_hooks">post_build_hooks</a>,
            <a href="#meson_build-pre_build_hooks">pre_build_hooks</a>, <a href="#meson_build-pre_build_patches">pre_build_patches</a>, <a href="#meson_build-repair_exclude_globs">repair_exclude_globs</a>, <a href="#meson_build-resource_size">resource_size</a>, <a href="#meson_build-sdist">sdist</a>,
            <a href="#meson_build-site_hooks">site_hooks</a>, <a href="#meson_build-source_dir">source_dir</a>, <a href="#meson_build-target_environment">target_environment</a>, <a href="#meson_build-tool_deps">tool_deps</a>, <a href="#meson_build-whldir_name">whldir_name</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="meson_build-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="meson_build-deps"></a>deps |  Runtime dependencies of the package, available on the build's Python path.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-data"></a>data |  Additional data and dependencies used by the build. These files are made available in the sandbox and can be referenced via $(location) in build_env and config_settings values.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-allow_native_exec"></a>allow_native_exec |  Allow Meson to run compiled test binaries on the build host during feature detection. When False (default), Meson always uses compile-only checks, producing reproducible builds regardless of host. Set to True only if you need host-specific optimizations and don't require cross-host reproducibility.   | Boolean | optional |  `False`  |
| <a id="meson_build-build_deps"></a>build_deps |  Build-time Python packages (e.g. `build-system.requires`), available on the build's Python path.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-build_env"></a>build_env |  Environment variables passed to the sdist build. Values are subject to 'Make variable' and $(location) expansion.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="meson_build-config_settings"></a>config_settings |  PEP 517 `config_settings` passed to the build backend. Values are subject to $(location) expansion.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="meson_build-copts"></a>copts |  Extra C/C++ compiler flags, appended after the toolchain flags.   | List of strings | optional |  `[]`  |
| <a id="meson_build-linkopts"></a>linkopts |  Extra linker flags, appended after the toolchain flags.   | List of strings | optional |  `[]`  |
| <a id="meson_build-meson_properties"></a>meson_properties |  Extra entries for the `[properties]` section of the generated Meson cross file.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="meson_build-native_deps"></a>native_deps |  C/C++ libraries whose headers and libraries are made available to the build.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-path_tools"></a>path_tools |  A list of binary targets placed on PATH during the build. Targets can be raw executables or pycross_path_tool targets.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-pkg_config_files"></a>pkg_config_files |  pkg-config `.pc` files made available to the build (e.g. from `pycross_cc_pkg_config`).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-post_build_hooks"></a>post_build_hooks |  Executables to run after the wheel is built. Each hook receives PYCROSS_WHEEL_FILE pointing to the built wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-pre_build_hooks"></a>pre_build_hooks |  Executables to run before building the wheel. Each hook receives PYCROSS_CONFIG_SETTINGS_FILE and PYCROSS_ENV_VARS_FILE environment variables pointing to JSON files it may read and modify.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-pre_build_patches"></a>pre_build_patches |  Patch files to apply to the sdist source tree before building.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-repair_exclude_globs"></a>repair_exclude_globs |  Shared library globs to exclude from wheel repair; assumed provided at runtime.   | List of strings | optional |  `[]`  |
| <a id="meson_build-resource_size"></a>resource_size |  Set the approximate size of this build, which controls two things:<br><br>1. The Bazel scheduler reservation, so large builds don't all run at once. 2. The parallelism passed to the underlying build system via environment    variables (CMAKE_BUILD_PARALLEL_LEVEL, GNUMAKEFLAGS, NINJA_JOBS, etc.).<br><br>Build tool parallelism is set to the scheduler reservation plus a small overcommit (default +2, matching ninja's ncpus+2 convention). This hides I/O latency and lets configure_make targets — whose configure phase is always serial — make better use of their allocation during the parallel make phase. The overcommit can be tuned with @rules_pycross//pycross/settings:parallelism_overcommit.<br><br>Each size maps to a cpu and mem value that can be overridden per-size. See @rules_pycross//pycross/settings:size_{size}_{cpu\|mem}.<br><br>The `serial` size is special: it fixes cpu=1 with no overcommit, for packages that are known-broken under parallel builds.   | String | optional |  `"default"`  |
| <a id="meson_build-sdist"></a>sdist |  The sdist archive to build.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="meson_build-site_hooks"></a>site_hooks |  Python code snippets to execute on interpreter startup during builds.   | List of strings | optional |  `[]`  |
| <a id="meson_build-source_dir"></a>source_dir |  Subdirectory within the sdist source tree to build.   | String | optional |  `""`  |
| <a id="meson_build-target_environment"></a>target_environment |  The target environment mapping JSON (resolved dynamically via alias filegroup).   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@rules_pycross//pycross/private:default_target_platform"`  |
| <a id="meson_build-tool_deps"></a>tool_deps |  Python build tool packages (`meson`, `ninja` and `meson-python`). The generated `@<repo>//_backend` macro fills these in from the lock file.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson_build-whldir_name"></a>whldir_name |  Name for the output .whldir TreeArtifact directory (e.g., 'numpy-1.24.0.whldir'). If empty, defaults to '{name}.whldir'.   | String | optional |  `""`  |


<a id="meson"></a>

## meson

<pre>
meson = use_extension("@rules_pycross//pycross/backends:meson.bzl", "meson")
meson.override(<a href="#meson.override-name">name</a>, <a href="#meson.override-data">data</a>, <a href="#meson.override-build_env">build_env</a>, <a href="#meson.override-config_settings">config_settings</a>, <a href="#meson.override-copts">copts</a>, <a href="#meson.override-linkopts">linkopts</a>, <a href="#meson.override-native_deps">native_deps</a>, <a href="#meson.override-path_tools">path_tools</a>,
               <a href="#meson.override-post_build_hooks">post_build_hooks</a>, <a href="#meson.override-pre_build_hooks">pre_build_hooks</a>, <a href="#meson.override-repair_exclude_globs">repair_exclude_globs</a>, <a href="#meson.override-tool_deps">tool_deps</a>, <a href="#meson.override-workspace">workspace</a>)
</pre>


**TAG CLASSES**

<a id="meson.override"></a>

### override

Specify meson-specific package overrides.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="meson.override-name"></a>name |  The package name, `name@version`, or '*' to apply to all packages built with this backend. For a package `name@version`, matching entries are layered from least to most specific (`*`, then `name`, then `name@version`); each field set by a more specific entry replaces the less specific value. The version must match a locked version exactly.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="meson.override-data"></a>data |  Additional data and dependencies used by the build.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-build_env"></a>build_env |  Extra environment variables passed to the sdist build.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="meson.override-config_settings"></a>config_settings |  Setup configuration arguments.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="meson.override-copts"></a>copts |  Extra C++ compiler options.   | List of strings | optional |  `[]`  |
| <a id="meson.override-linkopts"></a>linkopts |  Extra linker options.   | List of strings | optional |  `[]`  |
| <a id="meson.override-native_deps"></a>native_deps |  CC dependencies to link against.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-path_tools"></a>path_tools |  A list of binary targets placed on PATH during the build, under their basename. Wrap a target in `pycross_path_tool` to give it a different name on PATH.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-post_build_hooks"></a>post_build_hooks |  Executables to run after the wheel is built.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-pre_build_hooks"></a>pre_build_hooks |  Executables to run before building the wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="meson.override-repair_exclude_globs"></a>repair_exclude_globs |  Shared library globs to exclude from wheel repair; assumed provided at runtime.   | List of strings | optional |  `[]`  |
| <a id="meson.override-tool_deps"></a>tool_deps |  Overrides for the backend's tool packages, keyed by tool package name (e.g. `{"cmake": "@other//cmake:pkg"}`). Each entry replaces the auto-detected default for that tool, or adds it if the tool is not in the lock. Keys must be one of the backend's tool packages (or `repairwheel`), and each value must be a pycross package target for that package.   | Dictionary: String -> Label | optional |  `{}`  |
| <a id="meson.override-workspace"></a>workspace |  The workspace whose packages this override applies to.   | String | required |  |


