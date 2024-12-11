<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public repository rule API re-exports

<a id="lock_repo_model_pdm"></a>

## lock_repo_model_pdm

<pre>
load("@rules_pycross//pycross:workspace.bzl", "lock_repo_model_pdm")

lock_repo_model_pdm(<a href="#lock_repo_model_pdm-project_file">project_file</a>, <a href="#lock_repo_model_pdm-lock_file">lock_file</a>, <a href="#lock_repo_model_pdm-default">default</a>, <a href="#lock_repo_model_pdm-optional_groups">optional_groups</a>, <a href="#lock_repo_model_pdm-all_optional_groups">all_optional_groups</a>,
                    <a href="#lock_repo_model_pdm-development_groups">development_groups</a>, <a href="#lock_repo_model_pdm-all_development_groups">all_development_groups</a>, <a href="#lock_repo_model_pdm-require_static_urls">require_static_urls</a>)
</pre>



**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="lock_repo_model_pdm-project_file"></a>project_file |  <p align="center"> - </p>   |  none |
| <a id="lock_repo_model_pdm-lock_file"></a>lock_file |  <p align="center"> - </p>   |  none |
| <a id="lock_repo_model_pdm-default"></a>default |  <p align="center"> - </p>   |  `True` |
| <a id="lock_repo_model_pdm-optional_groups"></a>optional_groups |  <p align="center"> - </p>   |  `[]` |
| <a id="lock_repo_model_pdm-all_optional_groups"></a>all_optional_groups |  <p align="center"> - </p>   |  `False` |
| <a id="lock_repo_model_pdm-development_groups"></a>development_groups |  <p align="center"> - </p>   |  `[]` |
| <a id="lock_repo_model_pdm-all_development_groups"></a>all_development_groups |  <p align="center"> - </p>   |  `False` |
| <a id="lock_repo_model_pdm-require_static_urls"></a>require_static_urls |  <p align="center"> - </p>   |  `True` |


<a id="lock_repo_model_poetry"></a>

## lock_repo_model_poetry

<pre>
load("@rules_pycross//pycross:workspace.bzl", "lock_repo_model_poetry")

lock_repo_model_poetry(<a href="#lock_repo_model_poetry-project_file">project_file</a>, <a href="#lock_repo_model_poetry-lock_file">lock_file</a>, <a href="#lock_repo_model_poetry-default">default</a>, <a href="#lock_repo_model_poetry-optional_groups">optional_groups</a>, <a href="#lock_repo_model_poetry-all_optional_groups">all_optional_groups</a>)
</pre>



**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="lock_repo_model_poetry-project_file"></a>project_file |  <p align="center"> - </p>   |  none |
| <a id="lock_repo_model_poetry-lock_file"></a>lock_file |  <p align="center"> - </p>   |  none |
| <a id="lock_repo_model_poetry-default"></a>default |  <p align="center"> - </p>   |  `True` |
| <a id="lock_repo_model_poetry-optional_groups"></a>optional_groups |  <p align="center"> - </p>   |  `[]` |
| <a id="lock_repo_model_poetry-all_optional_groups"></a>all_optional_groups |  <p align="center"> - </p>   |  `False` |


<a id="lock_repo_model_uv"></a>

## lock_repo_model_uv

<pre>
load("@rules_pycross//pycross:workspace.bzl", "lock_repo_model_uv")

lock_repo_model_uv(<a href="#lock_repo_model_uv-project_file">project_file</a>, <a href="#lock_repo_model_uv-lock_file">lock_file</a>, <a href="#lock_repo_model_uv-default">default</a>, <a href="#lock_repo_model_uv-optional_groups">optional_groups</a>, <a href="#lock_repo_model_uv-all_optional_groups">all_optional_groups</a>,
                   <a href="#lock_repo_model_uv-development_groups">development_groups</a>, <a href="#lock_repo_model_uv-all_development_groups">all_development_groups</a>, <a href="#lock_repo_model_uv-require_static_urls">require_static_urls</a>)
</pre>



**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="lock_repo_model_uv-project_file"></a>project_file |  <p align="center"> - </p>   |  none |
| <a id="lock_repo_model_uv-lock_file"></a>lock_file |  <p align="center"> - </p>   |  none |
| <a id="lock_repo_model_uv-default"></a>default |  <p align="center"> - </p>   |  `True` |
| <a id="lock_repo_model_uv-optional_groups"></a>optional_groups |  <p align="center"> - </p>   |  `[]` |
| <a id="lock_repo_model_uv-all_optional_groups"></a>all_optional_groups |  <p align="center"> - </p>   |  `False` |
| <a id="lock_repo_model_uv-development_groups"></a>development_groups |  <p align="center"> - </p>   |  `[]` |
| <a id="lock_repo_model_uv-all_development_groups"></a>all_development_groups |  <p align="center"> - </p>   |  `False` |
| <a id="lock_repo_model_uv-require_static_urls"></a>require_static_urls |  <p align="center"> - </p>   |  `True` |


<a id="pycross_lock_repo"></a>

## pycross_lock_repo

<pre>
load("@rules_pycross//pycross:workspace.bzl", "pycross_lock_repo")

pycross_lock_repo(<a href="#pycross_lock_repo-name">name</a>, <a href="#pycross_lock_repo-lock_model">lock_model</a>, <a href="#pycross_lock_repo-kwargs">kwargs</a>)
</pre>

Create a repo containing packages described by an imported lock.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pycross_lock_repo-name"></a>name |  the repo name.   |  none |
| <a id="pycross_lock_repo-lock_model"></a>lock_model |  the serialized lock model struct. Use `lock_repo_model_pdm` or `lock_repo_model_poetry`.   |  none |
| <a id="pycross_lock_repo-kwargs"></a>kwargs |  additional args to pass to `resolved_lock_repo` and `package_repo`.   |  none |


<a id="pycross_register_for_python_toolchains"></a>

## pycross_register_for_python_toolchains

<pre>
load("@rules_pycross//pycross:workspace.bzl", "pycross_register_for_python_toolchains")

pycross_register_for_python_toolchains(<a href="#pycross_register_for_python_toolchains-name">name</a>, <a href="#pycross_register_for_python_toolchains-python_toolchains_repo">python_toolchains_repo</a>, <a href="#pycross_register_for_python_toolchains-platforms">platforms</a>, <a href="#pycross_register_for_python_toolchains-glibc_version">glibc_version</a>,
                                       <a href="#pycross_register_for_python_toolchains-macos_version">macos_version</a>)
</pre>

Register target environments and toolchains for a given list of Python versions.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="pycross_register_for_python_toolchains-name"></a>name |  the toolchain repo name.   |  none |
| <a id="pycross_register_for_python_toolchains-python_toolchains_repo"></a>python_toolchains_repo |  a label to the registered rules_python tolchain repo.   |  none |
| <a id="pycross_register_for_python_toolchains-platforms"></a>platforms |  an optional list of platforms to support (e.g., "x86_64-unknown-linux-gnu"). By default, all platforms supported by rules_python are registered.   |  `None` |
| <a id="pycross_register_for_python_toolchains-glibc_version"></a>glibc_version |  the maximum supported GLIBC version.   |  `None` |
| <a id="pycross_register_for_python_toolchains-macos_version"></a>macos_version |  the maximum supported macOS version.   |  `None` |


<a id="pycross_lock_file_repo"></a>

## pycross_lock_file_repo

<pre>
load("@rules_pycross//pycross:workspace.bzl", "pycross_lock_file_repo")

pycross_lock_file_repo(<a href="#pycross_lock_file_repo-name">name</a>, <a href="#pycross_lock_file_repo-lock_file">lock_file</a>, <a href="#pycross_lock_file_repo-repo_mapping">repo_mapping</a>)
</pre>

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_lock_file_repo-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_lock_file_repo-lock_file"></a>lock_file |  The generated bzl lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_lock_file_repo-repo_mapping"></a>repo_mapping |  In `WORKSPACE` context only: a dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.<br><br>For example, an entry `"@foo": "@bar"` declares that, for any time this repository depends on `@foo` (such as a dependency on `@foo//some:target`, it should actually resolve that dependency within globally-declared `@bar` (`@bar//some:target`).<br><br>This attribute is _not_ supported in `MODULE.bazel` context (when invoking a repository rule inside a module extension's implementation function).   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  |


