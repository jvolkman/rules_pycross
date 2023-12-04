<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API re-exports

<a id="pycross_lock_file"></a>

## pycross_lock_file

<pre>
pycross_lock_file(<a href="#pycross_lock_file-name">name</a>, <a href="#pycross_lock_file-always_build_packages">always_build_packages</a>, <a href="#pycross_lock_file-build_prefix">build_prefix</a>, <a href="#pycross_lock_file-build_target_overrides">build_target_overrides</a>,
                  <a href="#pycross_lock_file-default_alias_single_version">default_alias_single_version</a>, <a href="#pycross_lock_file-disallow_builds">disallow_builds</a>, <a href="#pycross_lock_file-environment_prefix">environment_prefix</a>,
                  <a href="#pycross_lock_file-generate_file_map">generate_file_map</a>, <a href="#pycross_lock_file-local_wheels">local_wheels</a>, <a href="#pycross_lock_file-lock_model_file">lock_model_file</a>, <a href="#pycross_lock_file-out">out</a>, <a href="#pycross_lock_file-package_build_dependencies">package_build_dependencies</a>,
                  <a href="#pycross_lock_file-package_ignore_dependencies">package_ignore_dependencies</a>, <a href="#pycross_lock_file-package_prefix">package_prefix</a>, <a href="#pycross_lock_file-pypi_index">pypi_index</a>, <a href="#pycross_lock_file-remote_wheels">remote_wheels</a>, <a href="#pycross_lock_file-repo_prefix">repo_prefix</a>,
                  <a href="#pycross_lock_file-target_environments">target_environments</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_lock_file-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_lock_file-always_build_packages"></a>always_build_packages |  A list of package keys (name or name@version) to always build from source.   | List of strings | optional | <code>[]</code> |
| <a id="pycross_lock_file-build_prefix"></a>build_prefix |  An optional prefix to apply to package build targets. Defaults to _build   | String | optional | <code>"_build"</code> |
| <a id="pycross_lock_file-build_target_overrides"></a>build_target_overrides |  A mapping of package keys (name or name@version) to existing pycross_wheel_build build targets.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional | <code>{}</code> |
| <a id="pycross_lock_file-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional | <code>False</code> |
| <a id="pycross_lock_file-disallow_builds"></a>disallow_builds |  Do not allow pycross_wheel_build targets in the final lock file (i.e., require wheels).   | Boolean | optional | <code>False</code> |
| <a id="pycross_lock_file-environment_prefix"></a>environment_prefix |  An optional prefix to apply to environment targets. Defaults to _env   | String | optional | <code>"_env"</code> |
| <a id="pycross_lock_file-generate_file_map"></a>generate_file_map |  Generate a FILES dict containing a mapping of filenames to repo labels.   | Boolean | optional | <code>False</code> |
| <a id="pycross_lock_file-local_wheels"></a>local_wheels |  A list of wheel files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |
| <a id="pycross_lock_file-lock_model_file"></a>lock_model_file |  The lock model JSON file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_lock_file-out"></a>out |  The output file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_lock_file-package_build_dependencies"></a>package_build_dependencies |  A dict of package keys (name or name@version) to a list of that packages build dependency keys.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional | <code>{}</code> |
| <a id="pycross_lock_file-package_ignore_dependencies"></a>package_ignore_dependencies |  A dict of package keys (name or name@version) to a list of that packages dependency keys to ignore.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional | <code>{}</code> |
| <a id="pycross_lock_file-package_prefix"></a>package_prefix |  An optional prefix to apply to package targets.   | String | optional | <code>""</code> |
| <a id="pycross_lock_file-pypi_index"></a>pypi_index |  The PyPI-compatible index to use (must support the JSON API).   | String | optional | <code>""</code> |
| <a id="pycross_lock_file-remote_wheels"></a>remote_wheels |  A mapping of remote wheels to their sha256 hashes.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional | <code>{}</code> |
| <a id="pycross_lock_file-repo_prefix"></a>repo_prefix |  The prefix to apply to repository targets. Defaults to the lock file target name.   | String | optional | <code>""</code> |
| <a id="pycross_lock_file-target_environments"></a>target_environments |  A list of pycross_target_environment labels.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |


<a id="pycross_lock_repo"></a>

## pycross_lock_repo

<pre>
pycross_lock_repo(<a href="#pycross_lock_repo-name">name</a>, <a href="#pycross_lock_repo-lock_file">lock_file</a>, <a href="#pycross_lock_repo-repo_mapping">repo_mapping</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_lock_repo-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_lock_repo-lock_file"></a>lock_file |  The generated bzl lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_lock_repo-repo_mapping"></a>repo_mapping |  A dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.&lt;p&gt;For example, an entry <code>"@foo": "@bar"</code> declares that, for any time this repository depends on <code>@foo</code> (such as a dependency on <code>@foo//some:target</code>, it should actually resolve that dependency within globally-declared <code>@bar</code> (<code>@bar//some:target</code>).   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | required |  |


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
| <a id="pycross_pdm_lock_model-all_development_groups"></a>all_development_groups |  Install all dev dependencies.   | Boolean | optional | <code>False</code> |
| <a id="pycross_pdm_lock_model-all_optional_groups"></a>all_optional_groups |  Install all optional dependencies.   | Boolean | optional | <code>False</code> |
| <a id="pycross_pdm_lock_model-default"></a>default |  Whether to install dependencies from the default group.   | Boolean | optional | <code>True</code> |
| <a id="pycross_pdm_lock_model-development_groups"></a>development_groups |  List of development dependency groups to install.   | List of strings | optional | <code>[]</code> |
| <a id="pycross_pdm_lock_model-lock_file"></a>lock_file |  The pdm.lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_pdm_lock_model-optional_groups"></a>optional_groups |  List of optional dependency groups to install.   | List of strings | optional | <code>[]</code> |
| <a id="pycross_pdm_lock_model-project_file"></a>project_file |  The pyproject.toml file with pdm dependencies.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_pdm_lock_model-require_static_urls"></a>require_static_urls |  Require that the lock file is created with --static-urls.   | Boolean | optional | <code>True</code> |


<a id="pycross_pkg_repo"></a>

## pycross_pkg_repo

<pre>
pycross_pkg_repo(<a href="#pycross_pkg_repo-name">name</a>, <a href="#pycross_pkg_repo-always_build_packages">always_build_packages</a>, <a href="#pycross_pkg_repo-build_prefix">build_prefix</a>, <a href="#pycross_pkg_repo-build_target_overrides">build_target_overrides</a>,
                 <a href="#pycross_pkg_repo-default_alias_single_version">default_alias_single_version</a>, <a href="#pycross_pkg_repo-disallow_builds">disallow_builds</a>, <a href="#pycross_pkg_repo-environment_prefix">environment_prefix</a>, <a href="#pycross_pkg_repo-generate_file_map">generate_file_map</a>,
                 <a href="#pycross_pkg_repo-local_wheels">local_wheels</a>, <a href="#pycross_pkg_repo-lock_model">lock_model</a>, <a href="#pycross_pkg_repo-package_build_dependencies">package_build_dependencies</a>, <a href="#pycross_pkg_repo-package_ignore_dependencies">package_ignore_dependencies</a>,
                 <a href="#pycross_pkg_repo-package_prefix">package_prefix</a>, <a href="#pycross_pkg_repo-pypi_index">pypi_index</a>, <a href="#pycross_pkg_repo-remote_wheels">remote_wheels</a>, <a href="#pycross_pkg_repo-repo_mapping">repo_mapping</a>, <a href="#pycross_pkg_repo-repo_prefix">repo_prefix</a>,
                 <a href="#pycross_pkg_repo-target_environments">target_environments</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_pkg_repo-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_pkg_repo-always_build_packages"></a>always_build_packages |  A list of package keys (name or name@version) to always build from source.   | List of strings | optional | <code>[]</code> |
| <a id="pycross_pkg_repo-build_prefix"></a>build_prefix |  An optional prefix to apply to package build targets. Defaults to _build   | String | optional | <code>"_build"</code> |
| <a id="pycross_pkg_repo-build_target_overrides"></a>build_target_overrides |  A mapping of package keys (name or name@version) to existing pycross_wheel_build build targets.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional | <code>{}</code> |
| <a id="pycross_pkg_repo-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional | <code>False</code> |
| <a id="pycross_pkg_repo-disallow_builds"></a>disallow_builds |  Do not allow pycross_wheel_build targets in the final lock file (i.e., require wheels).   | Boolean | optional | <code>False</code> |
| <a id="pycross_pkg_repo-environment_prefix"></a>environment_prefix |  An optional prefix to apply to environment targets. Defaults to _env   | String | optional | <code>"_env"</code> |
| <a id="pycross_pkg_repo-generate_file_map"></a>generate_file_map |  Generate a FILES dict containing a mapping of filenames to repo labels.   | Boolean | optional | <code>False</code> |
| <a id="pycross_pkg_repo-local_wheels"></a>local_wheels |  A list of wheel files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |
| <a id="pycross_pkg_repo-lock_model"></a>lock_model |  Lock model params. The returned value of pkg_repo_model_pdm or pkg_repo_model_poetry.   | String | required |  |
| <a id="pycross_pkg_repo-package_build_dependencies"></a>package_build_dependencies |  A dict of package keys (name or name@version) to a list of that packages build dependency keys.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional | <code>{}</code> |
| <a id="pycross_pkg_repo-package_ignore_dependencies"></a>package_ignore_dependencies |  A dict of package keys (name or name@version) to a list of that packages dependency keys to ignore.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional | <code>{}</code> |
| <a id="pycross_pkg_repo-package_prefix"></a>package_prefix |  An optional prefix to apply to package targets.   | String | optional | <code>""</code> |
| <a id="pycross_pkg_repo-pypi_index"></a>pypi_index |  The PyPI-compatible index to use (must support the JSON API).   | String | optional | <code>""</code> |
| <a id="pycross_pkg_repo-remote_wheels"></a>remote_wheels |  A mapping of remote wheels to their sha256 hashes.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional | <code>{}</code> |
| <a id="pycross_pkg_repo-repo_mapping"></a>repo_mapping |  A dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.&lt;p&gt;For example, an entry <code>"@foo": "@bar"</code> declares that, for any time this repository depends on <code>@foo</code> (such as a dependency on <code>@foo//some:target</code>, it should actually resolve that dependency within globally-declared <code>@bar</code> (<code>@bar//some:target</code>).   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | required |  |
| <a id="pycross_pkg_repo-repo_prefix"></a>repo_prefix |  The prefix to apply to repository targets. Defaults to the lock file target name.   | String | optional | <code>""</code> |
| <a id="pycross_pkg_repo-target_environments"></a>target_environments |  A list of pycross_target_environment labels.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |


<a id="pycross_poetry_lock_model"></a>

## pycross_poetry_lock_model

<pre>
pycross_poetry_lock_model(<a href="#pycross_poetry_lock_model-name">name</a>, <a href="#pycross_poetry_lock_model-poetry_lock_file">poetry_lock_file</a>, <a href="#pycross_poetry_lock_model-poetry_project_file">poetry_project_file</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_poetry_lock_model-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_poetry_lock_model-poetry_lock_file"></a>poetry_lock_file |  The poetry.lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_poetry_lock_model-poetry_project_file"></a>poetry_project_file |  The pyproject.toml file with Poetry dependencies.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


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
| <a id="pycross_target_environment-abis"></a>abis |  A list of PEP 425 abi tags. Defaults to ['none'].   | List of strings | optional | <code>["none"]</code> |
| <a id="pycross_target_environment-config_setting"></a>config_setting |  Optional config_setting target to select this environment.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional | <code>None</code> |
| <a id="pycross_target_environment-envornment_markers"></a>envornment_markers |  Environment marker overrides.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional | <code>{}</code> |
| <a id="pycross_target_environment-flag_values"></a>flag_values |  A list of flag values that, when satisfied, indicates this target_platform should be selected (together with python_compatible_with).   | <a href="https://bazel.build/rules/lib/dict">Dictionary: Label -> String</a> | optional | <code>{}</code> |
| <a id="pycross_target_environment-implementation"></a>implementation |  The PEP 425 implementation abbreviation. Defaults to 'cp' for CPython.   | String | optional | <code>"cp"</code> |
| <a id="pycross_target_environment-platforms"></a>platforms |  A list of PEP 425 platform tags. Defaults to ['any'].   | List of strings | optional | <code>["any"]</code> |
| <a id="pycross_target_environment-python_compatible_with"></a>python_compatible_with |  A list of constraints that, when satisfied, indicates this target_platform should be selected (together with flag_values).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |
| <a id="pycross_target_environment-version"></a>version |  The python version.   | String | required |  |


<a id="pycross_wheel_build"></a>

## pycross_wheel_build

<pre>
pycross_wheel_build(<a href="#pycross_wheel_build-name">name</a>, <a href="#pycross_wheel_build-build_env">build_env</a>, <a href="#pycross_wheel_build-config_settings">config_settings</a>, <a href="#pycross_wheel_build-copts">copts</a>, <a href="#pycross_wheel_build-data">data</a>, <a href="#pycross_wheel_build-deps">deps</a>, <a href="#pycross_wheel_build-linkopts">linkopts</a>, <a href="#pycross_wheel_build-native_deps">native_deps</a>,
                    <a href="#pycross_wheel_build-path_tools">path_tools</a>, <a href="#pycross_wheel_build-post_build_hooks">post_build_hooks</a>, <a href="#pycross_wheel_build-pre_build_hooks">pre_build_hooks</a>, <a href="#pycross_wheel_build-sdist">sdist</a>, <a href="#pycross_wheel_build-target_environment">target_environment</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_wheel_build-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_wheel_build-build_env"></a>build_env |  Environment variables passed to the sdist build. Values are subject to 'Make variable', location, and build_cwd_token expansion.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional | <code>{}</code> |
| <a id="pycross_wheel_build-config_settings"></a>config_settings |  PEP 517 config settings passed to the sdist build. Values are subject to 'Make variable', location, and build_cwd_token expansion.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> List of strings</a> | optional | <code>{}</code> |
| <a id="pycross_wheel_build-copts"></a>copts |  Additional C compiler options.   | List of strings | optional | <code>[]</code> |
| <a id="pycross_wheel_build-data"></a>data |  Additional data and dependencies used by the build.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |
| <a id="pycross_wheel_build-deps"></a>deps |  A list of Python build dependencies for the wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |
| <a id="pycross_wheel_build-linkopts"></a>linkopts |  Additional C linker options.   | List of strings | optional | <code>[]</code> |
| <a id="pycross_wheel_build-native_deps"></a>native_deps |  A list of native build dependencies (CcInfo) for the wheel.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |
| <a id="pycross_wheel_build-path_tools"></a>path_tools |  A mapping of binaries to names that are placed in PATH when building the sdist.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: Label -> String</a> | optional | <code>{}</code> |
| <a id="pycross_wheel_build-post_build_hooks"></a>post_build_hooks |  A list of binaries that are executed after the wheel is built.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |
| <a id="pycross_wheel_build-pre_build_hooks"></a>pre_build_hooks |  A list of binaries that are executed prior to building the sdist.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |
| <a id="pycross_wheel_build-sdist"></a>sdist |  The sdist file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_wheel_build-target_environment"></a>target_environment |  The target environment to build for.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional | <code>None</code> |


<a id="pycross_wheel_library"></a>

## pycross_wheel_library

<pre>
pycross_wheel_library(<a href="#pycross_wheel_library-name">name</a>, <a href="#pycross_wheel_library-deps">deps</a>, <a href="#pycross_wheel_library-enable_implicit_namespace_pkgs">enable_implicit_namespace_pkgs</a>, <a href="#pycross_wheel_library-python_version">python_version</a>, <a href="#pycross_wheel_library-wheel">wheel</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_wheel_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_wheel_library-deps"></a>deps |  A list of this wheel's Python library dependencies.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |
| <a id="pycross_wheel_library-enable_implicit_namespace_pkgs"></a>enable_implicit_namespace_pkgs |  If true, disables conversion of native namespace packages into pkg-util style namespace packages. When set all py_binary and py_test targets must specify either <code>legacy_create_init=False</code> or the global Bazel option <code>--incompatible_default_to_explicit_init_py</code> to prevent <code>__init__.py</code> being automatically generated in every directory. This option is required to support some packages which cannot handle the conversion to pkg-util style.   | Boolean | optional | <code>True</code> |
| <a id="pycross_wheel_library-python_version"></a>python_version |  The python version required for this wheel ('PY2' or 'PY3')   | String | optional | <code>""</code> |
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
| <a id="pycross_wheel_zipimport_library-deps"></a>deps |  A list of this wheel's Python library dependencies.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |
| <a id="pycross_wheel_zipimport_library-wheel"></a>wheel |  The wheel file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


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
| <a id="pypi_file-index"></a>index |  The base URL of the PyPI-compatible package index to use. Defaults to pypi.org.   | String | optional | <code>"https://pypi.org"</code> |
| <a id="pypi_file-keep_metadata"></a>keep_metadata |  Whether to store the pypi_metadata.json file for debugging.   | Boolean | optional | <code>False</code> |
| <a id="pypi_file-package_name"></a>package_name |  The package name.   | String | required |  |
| <a id="pypi_file-package_version"></a>package_version |  The package version.   | String | required |  |
| <a id="pypi_file-repo_mapping"></a>repo_mapping |  A dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.&lt;p&gt;For example, an entry <code>"@foo": "@bar"</code> declares that, for any time this repository depends on <code>@foo</code> (such as a dependency on <code>@foo//some:target</code>, it should actually resolve that dependency within globally-declared <code>@bar</code> (<code>@bar//some:target</code>).   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | required |  |
| <a id="pypi_file-sha256"></a>sha256 |  The expected SHA-256 of the file downloaded.   | String | required |  |


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


<a id="pkg_repo_model_pdm"></a>

## pkg_repo_model_pdm

<pre>
pkg_repo_model_pdm(<a href="#pkg_repo_model_pdm-project_file">project_file</a>, <a href="#pkg_repo_model_pdm-lock_file">lock_file</a>, <a href="#pkg_repo_model_pdm-default">default</a>, <a href="#pkg_repo_model_pdm-optional_groups">optional_groups</a>, <a href="#pkg_repo_model_pdm-all_optional_groups">all_optional_groups</a>,
                   <a href="#pkg_repo_model_pdm-development_groups">development_groups</a>, <a href="#pkg_repo_model_pdm-all_development_groups">all_development_groups</a>, <a href="#pkg_repo_model_pdm-require_static_urls">require_static_urls</a>)
</pre>



**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pkg_repo_model_pdm-project_file"></a>project_file |  <p align="center"> - </p>   |  none |
| <a id="pkg_repo_model_pdm-lock_file"></a>lock_file |  <p align="center"> - </p>   |  none |
| <a id="pkg_repo_model_pdm-default"></a>default |  <p align="center"> - </p>   |  <code>True</code> |
| <a id="pkg_repo_model_pdm-optional_groups"></a>optional_groups |  <p align="center"> - </p>   |  <code>[]</code> |
| <a id="pkg_repo_model_pdm-all_optional_groups"></a>all_optional_groups |  <p align="center"> - </p>   |  <code>False</code> |
| <a id="pkg_repo_model_pdm-development_groups"></a>development_groups |  <p align="center"> - </p>   |  <code>[]</code> |
| <a id="pkg_repo_model_pdm-all_development_groups"></a>all_development_groups |  <p align="center"> - </p>   |  <code>False</code> |
| <a id="pkg_repo_model_pdm-require_static_urls"></a>require_static_urls |  <p align="center"> - </p>   |  <code>True</code> |


<a id="pkg_repo_model_poetry"></a>

## pkg_repo_model_poetry

<pre>
pkg_repo_model_poetry(<a href="#pkg_repo_model_poetry-project_file">project_file</a>, <a href="#pkg_repo_model_poetry-lock_file">lock_file</a>)
</pre>



**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pkg_repo_model_poetry-project_file"></a>project_file |  <p align="center"> - </p>   |  none |
| <a id="pkg_repo_model_poetry-lock_file"></a>lock_file |  <p align="center"> - </p>   |  none |


<a id="pycross_register_for_python_toolchains"></a>

## pycross_register_for_python_toolchains

<pre>
pycross_register_for_python_toolchains(<a href="#pycross_register_for_python_toolchains-name">name</a>, <a href="#pycross_register_for_python_toolchains-python_toolchains_repo_name">python_toolchains_repo_name</a>, <a href="#pycross_register_for_python_toolchains-platforms">platforms</a>, <a href="#pycross_register_for_python_toolchains-glibc_version">glibc_version</a>,
                                       <a href="#pycross_register_for_python_toolchains-macos_version">macos_version</a>)
</pre>

    Register target environments and toolchains for a given list of Python versions.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pycross_register_for_python_toolchains-name"></a>name |  the toolchain repo name.   |  none |
| <a id="pycross_register_for_python_toolchains-python_toolchains_repo_name"></a>python_toolchains_repo_name |  the repo name of the registered rules_python tolchain repo.   |  none |
| <a id="pycross_register_for_python_toolchains-platforms"></a>platforms |  an optional list of platforms to support (e.g., "x86_64-unknown-linux-gnu"). By default, all platforms supported by rules_python are registered.   |  <code>None</code> |
| <a id="pycross_register_for_python_toolchains-glibc_version"></a>glibc_version |  the maximum supported GLIBC version.   |  <code>"2.25"</code> |
| <a id="pycross_register_for_python_toolchains-macos_version"></a>macos_version |  the maximum supported macOS version.   |  <code>"12.0"</code> |


