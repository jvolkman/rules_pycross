<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API re-exports

<a id="#pycross_lock_file"></a>

## pycross_lock_file

<pre>
pycross_lock_file(<a href="#pycross_lock_file-name">name</a>, <a href="#pycross_lock_file-always_build_packages">always_build_packages</a>, <a href="#pycross_lock_file-build_prefix">build_prefix</a>, <a href="#pycross_lock_file-build_target_overrides">build_target_overrides</a>,
                  <a href="#pycross_lock_file-default_alias_single_version">default_alias_single_version</a>, <a href="#pycross_lock_file-environment_prefix">environment_prefix</a>, <a href="#pycross_lock_file-local_wheels">local_wheels</a>, <a href="#pycross_lock_file-lock_model_file">lock_model_file</a>,
                  <a href="#pycross_lock_file-out">out</a>, <a href="#pycross_lock_file-package_build_dependencies">package_build_dependencies</a>, <a href="#pycross_lock_file-package_prefix">package_prefix</a>, <a href="#pycross_lock_file-pypi_index">pypi_index</a>, <a href="#pycross_lock_file-remote_wheels">remote_wheels</a>,
                  <a href="#pycross_lock_file-repo_prefix">repo_prefix</a>, <a href="#pycross_lock_file-target_environments">target_environments</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_lock_file-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="pycross_lock_file-always_build_packages"></a>always_build_packages |  A list of package keys (name or name@version) to always build from source.   | List of strings | optional | [] |
| <a id="pycross_lock_file-build_prefix"></a>build_prefix |  An optional prefix to apply to package build targets. Defaults to _build   | String | optional | "_build" |
| <a id="pycross_lock_file-build_target_overrides"></a>build_target_overrides |  A mapping of package keys (name or name@version) to existing pycross_wheel_build build targets.   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | optional | {} |
| <a id="pycross_lock_file-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional | False |
| <a id="pycross_lock_file-environment_prefix"></a>environment_prefix |  An optional prefix to apply to environment targets. Defaults to _env   | String | optional | "_env" |
| <a id="pycross_lock_file-local_wheels"></a>local_wheels |  A list of wheel files.   | <a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a> | optional | [] |
| <a id="pycross_lock_file-lock_model_file"></a>lock_model_file |  The lock model JSON file.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| <a id="pycross_lock_file-out"></a>out |  The output file.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| <a id="pycross_lock_file-package_build_dependencies"></a>package_build_dependencies |  A dict of package keys (name or name@version) to a list of that packages build dependency keys.   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> List of strings</a> | optional | {} |
| <a id="pycross_lock_file-package_prefix"></a>package_prefix |  An optional prefix to apply to package targets.   | String | optional | "" |
| <a id="pycross_lock_file-pypi_index"></a>pypi_index |  The PyPI-compatible index to use (must support the JSON API).   | String | optional | "" |
| <a id="pycross_lock_file-remote_wheels"></a>remote_wheels |  A mapping of remote wheels to their sha256 hashes.   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | optional | {} |
| <a id="pycross_lock_file-repo_prefix"></a>repo_prefix |  The prefix to apply to repository targets. Defaults to the lock file target name.   | String | optional | "" |
| <a id="pycross_lock_file-target_environments"></a>target_environments |  A list of pycross_target_environment labels.   | <a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a> | optional | [] |


<a id="#pycross_lock_repo"></a>

## pycross_lock_repo

<pre>
pycross_lock_repo(<a href="#pycross_lock_repo-name">name</a>, <a href="#pycross_lock_repo-lock_file">lock_file</a>, <a href="#pycross_lock_repo-repo_mapping">repo_mapping</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_lock_repo-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="pycross_lock_repo-lock_file"></a>lock_file |  The generated bzl lock file.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| <a id="pycross_lock_repo-repo_mapping"></a>repo_mapping |  A dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.&lt;p&gt;For example, an entry <code>"@foo": "@bar"</code> declares that, for any time this repository depends on <code>@foo</code> (such as a dependency on <code>@foo//some:target</code>, it should actually resolve that dependency within globally-declared <code>@bar</code> (<code>@bar//some:target</code>).   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | required |  |


<a id="#pycross_poetry_lock_model"></a>

## pycross_poetry_lock_model

<pre>
pycross_poetry_lock_model(<a href="#pycross_poetry_lock_model-name">name</a>, <a href="#pycross_poetry_lock_model-poetry_lock_file">poetry_lock_file</a>, <a href="#pycross_poetry_lock_model-poetry_project_file">poetry_project_file</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_poetry_lock_model-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="pycross_poetry_lock_model-poetry_lock_file"></a>poetry_lock_file |  The poetry.lock file.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| <a id="pycross_poetry_lock_model-poetry_project_file"></a>poetry_project_file |  The pyproject.toml file with Poetry dependencies.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |


<a id="#pycross_target_environment"></a>

## pycross_target_environment

<pre>
pycross_target_environment(<a href="#pycross_target_environment-name">name</a>, <a href="#pycross_target_environment-abis">abis</a>, <a href="#pycross_target_environment-envornment_markers">envornment_markers</a>, <a href="#pycross_target_environment-implementation">implementation</a>, <a href="#pycross_target_environment-platforms">platforms</a>,
                           <a href="#pycross_target_environment-python_compatible_with">python_compatible_with</a>, <a href="#pycross_target_environment-version">version</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_target_environment-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="pycross_target_environment-abis"></a>abis |  A list of PEP 425 abi tags.   | List of strings | optional | [] |
| <a id="pycross_target_environment-envornment_markers"></a>envornment_markers |  Environment marker overrides.   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | optional | {} |
| <a id="pycross_target_environment-implementation"></a>implementation |  The PEP 425 implementation abbreviation (defaults to 'cp' for CPython).   | String | optional | "cp" |
| <a id="pycross_target_environment-platforms"></a>platforms |  A list of PEP 425 platform tags.   | List of strings | optional | [] |
| <a id="pycross_target_environment-python_compatible_with"></a>python_compatible_with |  A list of constraints that, when satisfied, indicates this target_platform should be selected.   | <a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a> | required |  |
| <a id="pycross_target_environment-version"></a>version |  The python version.   | String | required |  |


<a id="#pycross_wheel_build"></a>

## pycross_wheel_build

<pre>
pycross_wheel_build(<a href="#pycross_wheel_build-name">name</a>, <a href="#pycross_wheel_build-copts">copts</a>, <a href="#pycross_wheel_build-deps">deps</a>, <a href="#pycross_wheel_build-linkopts">linkopts</a>, <a href="#pycross_wheel_build-sdist">sdist</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_wheel_build-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="pycross_wheel_build-copts"></a>copts |  Additional C compiler options.   | List of strings | optional | [] |
| <a id="pycross_wheel_build-deps"></a>deps |  A list of build dependencies for the wheel.   | <a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a> | optional | [] |
| <a id="pycross_wheel_build-linkopts"></a>linkopts |  Additional C linker options.   | List of strings | optional | [] |
| <a id="pycross_wheel_build-sdist"></a>sdist |  The sdist file.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |


<a id="#pycross_wheel_library"></a>

## pycross_wheel_library

<pre>
pycross_wheel_library(<a href="#pycross_wheel_library-name">name</a>, <a href="#pycross_wheel_library-deps">deps</a>, <a href="#pycross_wheel_library-enable_implicit_namespace_pkgs">enable_implicit_namespace_pkgs</a>, <a href="#pycross_wheel_library-python_version">python_version</a>, <a href="#pycross_wheel_library-wheel">wheel</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_wheel_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="pycross_wheel_library-deps"></a>deps |  A list of this wheel's Python library dependencies.   | <a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a> | optional | [] |
| <a id="pycross_wheel_library-enable_implicit_namespace_pkgs"></a>enable_implicit_namespace_pkgs |  If true, disables conversion of native namespace packages into pkg-util style namespace packages. When set all py_binary and py_test targets must specify either <code>legacy_create_init=False</code> or the global Bazel option <code>--incompatible_default_to_explicit_init_py</code> to prevent <code>__init__.py</code> being automatically generated in every directory. This option is required to support some packages which cannot handle the conversion to pkg-util style.   | Boolean | optional | True |
| <a id="pycross_wheel_library-python_version"></a>python_version |  The python version required for this wheel ('PY2' or 'PY3')   | String | optional | "" |
| <a id="pycross_wheel_library-wheel"></a>wheel |  The wheel file.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |


<a id="#pypi_file"></a>

## pypi_file

<pre>
pypi_file(<a href="#pypi_file-name">name</a>, <a href="#pypi_file-filename">filename</a>, <a href="#pypi_file-index">index</a>, <a href="#pypi_file-keep_metadata">keep_metadata</a>, <a href="#pypi_file-package_name">package_name</a>, <a href="#pypi_file-package_version">package_version</a>, <a href="#pypi_file-repo_mapping">repo_mapping</a>, <a href="#pypi_file-sha256">sha256</a>)
</pre>

Downloads a file from a PyPI-compatible package index.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pypi_file-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="pypi_file-filename"></a>filename |  The name of the file to download.   | String | required |  |
| <a id="pypi_file-index"></a>index |  The base URL of the PyPI-compatible package index to use. Defaults to pypi.org.   | String | optional | "https://pypi.org" |
| <a id="pypi_file-keep_metadata"></a>keep_metadata |  Whether to store the pypi_metadata.json file for debugging.   | Boolean | optional | False |
| <a id="pypi_file-package_name"></a>package_name |  The package name.   | String | required |  |
| <a id="pypi_file-package_version"></a>package_version |  The package version.   | String | required |  |
| <a id="pypi_file-repo_mapping"></a>repo_mapping |  A dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.&lt;p&gt;For example, an entry <code>"@foo": "@bar"</code> declares that, for any time this repository depends on <code>@foo</code> (such as a dependency on <code>@foo//some:target</code>, it should actually resolve that dependency within globally-declared <code>@bar</code> (<code>@bar//some:target</code>).   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | required |  |
| <a id="pypi_file-sha256"></a>sha256 |  The expected SHA-256 of the file downloaded.   | String | required |  |


