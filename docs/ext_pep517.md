<!-- Generated with Stardoc: http://skydoc.bazel.build -->

PEP 517 build backend for rules_pycross.

<a id="pep517_build"></a>

## pep517_build

<pre>
load("@rules_pycross//pycross/backends:pep517.bzl", "pep517_build")

pep517_build(<a href="#pep517_build-name">name</a>, <a href="#pep517_build-deps">deps</a>, <a href="#pep517_build-data">data</a>, <a href="#pep517_build-build_deps">build_deps</a>, <a href="#pep517_build-build_env">build_env</a>, <a href="#pep517_build-post_build_hooks">post_build_hooks</a>, <a href="#pep517_build-pre_build_hooks">pre_build_hooks</a>,
             <a href="#pep517_build-pre_build_patches">pre_build_patches</a>, <a href="#pep517_build-required_build_packages">required_build_packages</a>, <a href="#pep517_build-resource_size">resource_size</a>, <a href="#pep517_build-sdist">sdist</a>, <a href="#pep517_build-site_hooks">site_hooks</a>, <a href="#pep517_build-source_dir">source_dir</a>,
             <a href="#pep517_build-target_environment">target_environment</a>, <a href="#pep517_build-whldir_name">whldir_name</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pep517_build-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pep517_build-deps"></a>deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pep517_build-data"></a>data |  Additional data and dependencies used by the build. These files are made available in the sandbox and can be referenced via $(location) in build_env and config_settings values.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pep517_build-build_deps"></a>build_deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pep517_build-build_env"></a>build_env |  Environment variables passed to the sdist build. Values are subject to 'Make variable' and $(location) expansion.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="pep517_build-post_build_hooks"></a>post_build_hooks |  Executables to run after the wheel is built. Each hook receives PYCROSS_WHEEL_FILE pointing to the built wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pep517_build-pre_build_hooks"></a>pre_build_hooks |  Executables to run before building the wheel. Each hook receives PYCROSS_CONFIG_SETTINGS_FILE and PYCROSS_ENV_VARS_FILE environment variables pointing to JSON files it may read and modify.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pep517_build-pre_build_patches"></a>pre_build_patches |  Patch files to apply to the sdist source tree before building.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pep517_build-required_build_packages"></a>required_build_packages |  PEP 503 normalized names of packages required by build-system.requires. Used to validate that all needed build tools are present in build_deps.   | List of strings | optional |  `[]`  |
| <a id="pep517_build-resource_size"></a>resource_size |  Set the approximate size of this build, which controls two things:<br><br>1. The Bazel scheduler reservation, so large builds don't all run at once. 2. The parallelism passed to the underlying build system via environment    variables (CMAKE_BUILD_PARALLEL_LEVEL, GNUMAKEFLAGS, NINJA_JOBS, etc.).<br><br>Build tool parallelism is set to the scheduler reservation plus a small overcommit (default +2, matching ninja's ncpus+2 convention). This hides I/O latency and lets configure_make targets — whose configure phase is always serial — make better use of their allocation during the parallel make phase. The overcommit can be tuned with @rules_pycross//pycross/settings:parallelism_overcommit.<br><br>Each size maps to a cpu and mem value that can be overridden per-size. See @rules_pycross//pycross/settings:size_{size}_{cpu\|mem}.<br><br>The `serial` size is special: it fixes cpu=1 with no overcommit, for packages that are known-broken under parallel builds.   | String | optional |  `"default"`  |
| <a id="pep517_build-sdist"></a>sdist |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pep517_build-site_hooks"></a>site_hooks |  Python code snippets to execute on interpreter startup during builds.   | List of strings | optional |  `[]`  |
| <a id="pep517_build-source_dir"></a>source_dir |  Subdirectory within the sdist source tree to build.   | String | optional |  `""`  |
| <a id="pep517_build-target_environment"></a>target_environment |  The target environment mapping JSON (resolved dynamically via alias filegroup).   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@rules_pycross//pycross/private:default_target_platform"`  |
| <a id="pep517_build-whldir_name"></a>whldir_name |  Name for the output .whldir TreeArtifact directory (e.g., 'numpy-1.24.0.whldir'). If empty, defaults to '{name}.whldir'.   | String | optional |  `""`  |


