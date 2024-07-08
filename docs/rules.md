<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public build rule API re-exports

<a id="pycross_lock_file"></a>

## pycross_lock_file

<pre>
pycross_lock_file(<a href="#pycross_lock_file-name">name</a>, <a href="#pycross_lock_file-out">out</a>, <a href="#pycross_lock_file-always_include_sdist">always_include_sdist</a>, <a href="#pycross_lock_file-annotations">annotations</a>, <a href="#pycross_lock_file-default_alias_single_version">default_alias_single_version</a>,
                  <a href="#pycross_lock_file-disallow_builds">disallow_builds</a>, <a href="#pycross_lock_file-fully_qualified_environment_labels">fully_qualified_environment_labels</a>, <a href="#pycross_lock_file-generate_file_map">generate_file_map</a>,
                  <a href="#pycross_lock_file-local_wheels">local_wheels</a>, <a href="#pycross_lock_file-lock_model_file">lock_model_file</a>, <a href="#pycross_lock_file-pypi_index">pypi_index</a>, <a href="#pycross_lock_file-remote_wheels">remote_wheels</a>, <a href="#pycross_lock_file-repo_prefix">repo_prefix</a>,
                  <a href="#pycross_lock_file-target_environments">target_environments</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_lock_file-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_lock_file-out"></a>out |  The output file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_lock_file-always_include_sdist"></a>always_include_sdist |  Always include an entry for a package's sdist if one exists.   | Boolean | optional |  `False`  |
| <a id="pycross_lock_file-annotations"></a>annotations |  Optional annotations to apply to packages.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="pycross_lock_file-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional |  `False`  |
| <a id="pycross_lock_file-disallow_builds"></a>disallow_builds |  Do not allow pycross_wheel_build targets in the final lock file (i.e., require wheels).   | Boolean | optional |  `False`  |
| <a id="pycross_lock_file-fully_qualified_environment_labels"></a>fully_qualified_environment_labels |  Generate fully-qualified environment labels.   | Boolean | optional |  `True`  |
| <a id="pycross_lock_file-generate_file_map"></a>generate_file_map |  Generate a FILES dict containing a mapping of filenames to repo labels.   | Boolean | optional |  `False`  |
| <a id="pycross_lock_file-local_wheels"></a>local_wheels |  A list of wheel files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pycross_lock_file-lock_model_file"></a>lock_model_file |  The lock model JSON file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_lock_file-pypi_index"></a>pypi_index |  The PyPI-compatible index to use (must support the JSON API).   | String | optional |  `""`  |
| <a id="pycross_lock_file-remote_wheels"></a>remote_wheels |  A mapping of remote wheels to their sha256 hashes.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="pycross_lock_file-repo_prefix"></a>repo_prefix |  The prefix to apply to repository targets. Defaults to the lock file target name.   | String | optional |  `""`  |
| <a id="pycross_lock_file-target_environments"></a>target_environments |  A list of pycross_target_environment labels.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="pycross_pdm_lock_model"></a>

## pycross_pdm_lock_model

<pre>
pycross_pdm_lock_model(<a href="#pycross_pdm_lock_model-name">name</a>, <a href="#pycross_pdm_lock_model-all_development_groups">all_development_groups</a>, <a href="#pycross_pdm_lock_model-all_optional_groups">all_optional_groups</a>, <a href="#pycross_pdm_lock_model-default">default</a>,
                       <a href="#pycross_pdm_lock_model-development_groups">development_groups</a>, <a href="#pycross_pdm_lock_model-lock_file">lock_file</a>, <a href="#pycross_pdm_lock_model-optional_groups">optional_groups</a>, <a href="#pycross_pdm_lock_model-project_file">project_file</a>,
                       <a href="#pycross_pdm_lock_model-require_static_urls">require_static_urls</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_pdm_lock_model-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_pdm_lock_model-all_development_groups"></a>all_development_groups |  Install all dev dependencies.   | Boolean | optional |  `False`  |
| <a id="pycross_pdm_lock_model-all_optional_groups"></a>all_optional_groups |  Install all optional dependencies.   | Boolean | optional |  `False`  |
| <a id="pycross_pdm_lock_model-default"></a>default |  Whether to install dependencies from the default group.   | Boolean | optional |  `True`  |
| <a id="pycross_pdm_lock_model-development_groups"></a>development_groups |  List of development dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="pycross_pdm_lock_model-lock_file"></a>lock_file |  The lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_pdm_lock_model-optional_groups"></a>optional_groups |  List of optional dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="pycross_pdm_lock_model-project_file"></a>project_file |  The pyproject.toml file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_pdm_lock_model-require_static_urls"></a>require_static_urls |  Require that the lock file is created with --static-urls.   | Boolean | optional |  `True`  |


<a id="pycross_poetry_lock_model"></a>

## pycross_poetry_lock_model

<pre>
pycross_poetry_lock_model(<a href="#pycross_poetry_lock_model-name">name</a>, <a href="#pycross_poetry_lock_model-lock_file">lock_file</a>, <a href="#pycross_poetry_lock_model-project_file">project_file</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_poetry_lock_model-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_poetry_lock_model-lock_file"></a>lock_file |  The poetry.lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_poetry_lock_model-project_file"></a>project_file |  The pyproject.toml file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="pycross_target_environment"></a>

## pycross_target_environment

<pre>
pycross_target_environment(<a href="#pycross_target_environment-name">name</a>, <a href="#pycross_target_environment-abis">abis</a>, <a href="#pycross_target_environment-config_setting">config_setting</a>, <a href="#pycross_target_environment-envornment_markers">envornment_markers</a>, <a href="#pycross_target_environment-flag_values">flag_values</a>,
                           <a href="#pycross_target_environment-implementation">implementation</a>, <a href="#pycross_target_environment-platforms">platforms</a>, <a href="#pycross_target_environment-python_compatible_with">python_compatible_with</a>, <a href="#pycross_target_environment-version">version</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_target_environment-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_target_environment-abis"></a>abis |  A list of PEP 425 abi tags. Defaults to ['none'].   | List of strings | optional |  `["none"]`  |
| <a id="pycross_target_environment-config_setting"></a>config_setting |  Optional config_setting target to select this environment.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="pycross_target_environment-envornment_markers"></a>envornment_markers |  Environment marker overrides.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="pycross_target_environment-flag_values"></a>flag_values |  A list of flag values that, when satisfied, indicates this target_platform should be selected (together with python_compatible_with).   | <a href="https://bazel.build/rules/lib/dict">Dictionary: Label -> String</a> | optional |  `{}`  |
| <a id="pycross_target_environment-implementation"></a>implementation |  The PEP 425 implementation abbreviation. Defaults to 'cp' for CPython.   | String | optional |  `"cp"`  |
| <a id="pycross_target_environment-platforms"></a>platforms |  A list of PEP 425 platform tags. Defaults to ['any'].   | List of strings | optional |  `["any"]`  |
| <a id="pycross_target_environment-python_compatible_with"></a>python_compatible_with |  A list of constraints that, when satisfied, indicates this target_platform should be selected (together with flag_values).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pycross_target_environment-version"></a>version |  The python version.   | String | required |  |


<a id="pycross_wheel_build"></a>

## pycross_wheel_build

<pre>
pycross_wheel_build(<a href="#pycross_wheel_build-name">name</a>, <a href="#pycross_wheel_build-deps">deps</a>, <a href="#pycross_wheel_build-data">data</a>, <a href="#pycross_wheel_build-build_env">build_env</a>, <a href="#pycross_wheel_build-config_settings">config_settings</a>, <a href="#pycross_wheel_build-copts">copts</a>, <a href="#pycross_wheel_build-linkopts">linkopts</a>, <a href="#pycross_wheel_build-native_deps">native_deps</a>,
                    <a href="#pycross_wheel_build-path_tools">path_tools</a>, <a href="#pycross_wheel_build-post_build_hooks">post_build_hooks</a>, <a href="#pycross_wheel_build-pre_build_hooks">pre_build_hooks</a>, <a href="#pycross_wheel_build-sdist">sdist</a>, <a href="#pycross_wheel_build-target_environment">target_environment</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_wheel_build-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_wheel_build-deps"></a>deps |  A list of Python build dependencies for the wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pycross_wheel_build-data"></a>data |  Additional data and dependencies used by the build.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pycross_wheel_build-build_env"></a>build_env |  Environment variables passed to the sdist build. Values are subject to 'Make variable', location, and build_cwd_token expansion.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="pycross_wheel_build-config_settings"></a>config_settings |  PEP 517 config settings passed to the sdist build. Values are subject to 'Make variable', location, and build_cwd_token expansion.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="pycross_wheel_build-copts"></a>copts |  Additional C compiler options.   | List of strings | optional |  `[]`  |
| <a id="pycross_wheel_build-linkopts"></a>linkopts |  Additional C linker options.   | List of strings | optional |  `[]`  |
| <a id="pycross_wheel_build-native_deps"></a>native_deps |  A list of native build dependencies (CcInfo) for the wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pycross_wheel_build-path_tools"></a>path_tools |  A mapping of binaries to names that are placed in PATH when building the sdist.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: Label -> String</a> | optional |  `{}`  |
| <a id="pycross_wheel_build-post_build_hooks"></a>post_build_hooks |  A list of binaries that are executed after the wheel is built.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pycross_wheel_build-pre_build_hooks"></a>pre_build_hooks |  A list of binaries that are executed prior to building the sdist.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pycross_wheel_build-sdist"></a>sdist |  The sdist file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_wheel_build-target_environment"></a>target_environment |  The target environment to build for.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |


<a id="pycross_wheel_library"></a>

## pycross_wheel_library

<pre>
pycross_wheel_library(<a href="#pycross_wheel_library-name">name</a>, <a href="#pycross_wheel_library-deps">deps</a>, <a href="#pycross_wheel_library-enable_implicit_namespace_pkgs">enable_implicit_namespace_pkgs</a>, <a href="#pycross_wheel_library-install_exclude_globs">install_exclude_globs</a>,
                      <a href="#pycross_wheel_library-python_version">python_version</a>, <a href="#pycross_wheel_library-wheel">wheel</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_wheel_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_wheel_library-deps"></a>deps |  A list of this wheel's Python library dependencies.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pycross_wheel_library-enable_implicit_namespace_pkgs"></a>enable_implicit_namespace_pkgs |  If true, disables conversion of native namespace packages into pkg-util style namespace packages. When set all py_binary and py_test targets must specify either `legacy_create_init=False` or the global Bazel option `--incompatible_default_to_explicit_init_py` to prevent `__init__.py` being automatically generated in every directory. This option is required to support some packages which cannot handle the conversion to pkg-util style.   | Boolean | optional |  `True`  |
| <a id="pycross_wheel_library-install_exclude_globs"></a>install_exclude_globs |  A list of globs for files to exclude during installation.   | List of strings | optional |  `[]`  |
| <a id="pycross_wheel_library-python_version"></a>python_version |  The python version required for this wheel ('PY2' or 'PY3')   | String | optional |  `""`  |
| <a id="pycross_wheel_library-wheel"></a>wheel |  The wheel file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="pycross_wheel_zipimport_library"></a>

## pycross_wheel_zipimport_library

<pre>
pycross_wheel_zipimport_library(<a href="#pycross_wheel_zipimport_library-name">name</a>, <a href="#pycross_wheel_zipimport_library-deps">deps</a>, <a href="#pycross_wheel_zipimport_library-wheel">wheel</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_wheel_zipimport_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_wheel_zipimport_library-deps"></a>deps |  A list of this wheel's Python library dependencies.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pycross_wheel_zipimport_library-wheel"></a>wheel |  The wheel file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="PycrossWheelInfo"></a>

## PycrossWheelInfo

<pre>
PycrossWheelInfo(<a href="#PycrossWheelInfo-name_file">name_file</a>, <a href="#PycrossWheelInfo-wheel_file">wheel_file</a>)
</pre>

Information about a Python wheel.

**FIELDS**


| Name  | Description |
| :------------- | :------------- |
| <a id="PycrossWheelInfo-name_file"></a>name_file |  File: A file containing the canonical name of the wheel.    |
| <a id="PycrossWheelInfo-wheel_file"></a>wheel_file |  File: The wheel file itself.    |


<a id="package_annotation"></a>

## package_annotation

<pre>
package_annotation(<a href="#package_annotation-always_build">always_build</a>, <a href="#package_annotation-build_dependencies">build_dependencies</a>, <a href="#package_annotation-build_target">build_target</a>, <a href="#package_annotation-ignore_dependencies">ignore_dependencies</a>,
                   <a href="#package_annotation-install_exclude_globs">install_exclude_globs</a>)
</pre>

Annotations to apply to individual packages.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="package_annotation-always_build"></a>always_build |  If True, don't use pre-build wheels for this package.   |  `False` |
| <a id="package_annotation-build_dependencies"></a>build_dependencies |  A list of additional package keys (name or name@version) to use when building this package from source.   |  `[]` |
| <a id="package_annotation-build_target"></a>build_target |  An optional override build target to use when and if this package needs to be built from source.   |  `None` |
| <a id="package_annotation-ignore_dependencies"></a>ignore_dependencies |  A list of package keys (name or name@version) to drop from this package's set of declared dependencies.   |  `[]` |
| <a id="package_annotation-install_exclude_globs"></a>install_exclude_globs |  A list of globs for files to exclude during installation.   |  `[]` |

**RETURNS**

str: A json encoded string of the provided content.


<a id="pypi_file"></a>

## pypi_file

<pre>
pypi_file(<a href="#pypi_file-name">name</a>, <a href="#pypi_file-filename">filename</a>, <a href="#pypi_file-index">index</a>, <a href="#pypi_file-keep_metadata">keep_metadata</a>, <a href="#pypi_file-package_name">package_name</a>, <a href="#pypi_file-package_version">package_version</a>, <a href="#pypi_file-repo_mapping">repo_mapping</a>, <a href="#pypi_file-sha256">sha256</a>)
</pre>

Downloads a file from a PyPI-compatible package index.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pypi_file-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pypi_file-filename"></a>filename |  The name of the file to download.   | String | required |  |
| <a id="pypi_file-index"></a>index |  The base URL of the PyPI-compatible package index to use. Defaults to pypi.org.   | String | optional |  `"https://pypi.org"`  |
| <a id="pypi_file-keep_metadata"></a>keep_metadata |  Whether to store the pypi_metadata.json file for debugging.   | Boolean | optional |  `False`  |
| <a id="pypi_file-package_name"></a>package_name |  The package name.   | String | required |  |
| <a id="pypi_file-package_version"></a>package_version |  The package version.   | String | required |  |
| <a id="pypi_file-repo_mapping"></a>repo_mapping |  In `WORKSPACE` context only: a dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.<br><br>For example, an entry `"@foo": "@bar"` declares that, for any time this repository depends on `@foo` (such as a dependency on `@foo//some:target`, it should actually resolve that dependency within globally-declared `@bar` (`@bar//some:target`).<br><br>This attribute is _not_ supported in `MODULE.bazel` context (when invoking a repository rule inside a module extension's implementation function).   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  |
| <a id="pypi_file-sha256"></a>sha256 |  The expected SHA-256 of the file downloaded.   | String | required |  |


