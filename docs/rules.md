<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API re-exports

<a id="#pycross_lock_file"></a>

## pycross_lock_file

<pre>
pycross_lock_file(<a href="#pycross_lock_file-name">name</a>, <a href="#pycross_lock_file-file_url_overrides">file_url_overrides</a>, <a href="#pycross_lock_file-out">out</a>, <a href="#pycross_lock_file-poetry_lock_file">poetry_lock_file</a>, <a href="#pycross_lock_file-poetry_project_file">poetry_project_file</a>,
                  <a href="#pycross_lock_file-target_environments">target_environments</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_lock_file-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="pycross_lock_file-file_url_overrides"></a>file_url_overrides |  An optional mapping of wheel or sdist filenames to their URLs.   | <a href="https://bazel.build/docs/skylark/lib/dict.html">Dictionary: String -> String</a> | optional | {} |
| <a id="pycross_lock_file-out"></a>out |  The output file.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| <a id="pycross_lock_file-poetry_lock_file"></a>poetry_lock_file |  The poetry.lock file.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| <a id="pycross_lock_file-poetry_project_file"></a>poetry_project_file |  The pyproject.toml file with Poetry dependencies.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |
| <a id="pycross_lock_file-target_environments"></a>target_environments |  A list of pycross_target_environment labels.   | <a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a> | optional | [] |


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
pycross_wheel_build(<a href="#pycross_wheel_build-name">name</a>, <a href="#pycross_wheel_build-deps">deps</a>, <a href="#pycross_wheel_build-sdist">sdist</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_wheel_build-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/docs/build-ref.html#name">Name</a> | required |  |
| <a id="pycross_wheel_build-deps"></a>deps |  A list of build dependencies for the wheel.   | <a href="https://bazel.build/docs/build-ref.html#labels">List of labels</a> | optional | [] |
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
| <a id="pycross_wheel_library-python_version"></a>python_version |  The python version required for this wheel.   | String | optional | "" |
| <a id="pycross_wheel_library-wheel"></a>wheel |  The wheel file.   | <a href="https://bazel.build/docs/build-ref.html#labels">Label</a> | required |  |


