<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The lock_import extension.

<a id="lock_import"></a>

## lock_import

<pre>
lock_import = use_extension("@rules_pycross//pycross/extensions:lock_import.bzl", "lock_import")
lock_import.import_pdm(<a href="#lock_import.import_pdm-all_development_groups">all_development_groups</a>, <a href="#lock_import.import_pdm-all_optional_groups">all_optional_groups</a>, <a href="#lock_import.import_pdm-default">default</a>,
                       <a href="#lock_import.import_pdm-default_alias_single_version">default_alias_single_version</a>, <a href="#lock_import.import_pdm-development_groups">development_groups</a>, <a href="#lock_import.import_pdm-disallow_builds">disallow_builds</a>,
                       <a href="#lock_import.import_pdm-local_wheels">local_wheels</a>, <a href="#lock_import.import_pdm-lock_file">lock_file</a>, <a href="#lock_import.import_pdm-optional_groups">optional_groups</a>, <a href="#lock_import.import_pdm-project_file">project_file</a>, <a href="#lock_import.import_pdm-repo">repo</a>,
                       <a href="#lock_import.import_pdm-require_static_urls">require_static_urls</a>, <a href="#lock_import.import_pdm-target_environments">target_environments</a>)
lock_import.import_poetry(<a href="#lock_import.import_poetry-default_alias_single_version">default_alias_single_version</a>, <a href="#lock_import.import_poetry-disallow_builds">disallow_builds</a>, <a href="#lock_import.import_poetry-local_wheels">local_wheels</a>, <a href="#lock_import.import_poetry-lock_file">lock_file</a>,
                          <a href="#lock_import.import_poetry-project_file">project_file</a>, <a href="#lock_import.import_poetry-repo">repo</a>, <a href="#lock_import.import_poetry-target_environments">target_environments</a>)
lock_import.package(<a href="#lock_import.package-name">name</a>, <a href="#lock_import.package-always_build">always_build</a>, <a href="#lock_import.package-build_dependencies">build_dependencies</a>, <a href="#lock_import.package-build_target">build_target</a>, <a href="#lock_import.package-ignore_dependencies">ignore_dependencies</a>,
                    <a href="#lock_import.package-install_exclude_globs">install_exclude_globs</a>, <a href="#lock_import.package-repo">repo</a>)
</pre>


**TAG CLASSES**

<a id="lock_import.import_pdm"></a>

### import_pdm

Import a PDM lock file.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.import_pdm-all_development_groups"></a>all_development_groups |  Install all dev dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pdm-all_optional_groups"></a>all_optional_groups |  Install all optional dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pdm-default"></a>default |  Whether to install dependencies from the default group.   | Boolean | optional |  `True`  |
| <a id="lock_import.import_pdm-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pdm-development_groups"></a>development_groups |  List of development dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_pdm-disallow_builds"></a>disallow_builds |  If True, only pre-built wheels are allowed.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pdm-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lock_import.import_pdm-lock_file"></a>lock_file |  The pdm.lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lock_import.import_pdm-optional_groups"></a>optional_groups |  List of optional dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_pdm-project_file"></a>project_file |  The pyproject.toml file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lock_import.import_pdm-repo"></a>repo |  The repository name   | String | required |  |
| <a id="lock_import.import_pdm-require_static_urls"></a>require_static_urls |  Require that the lock file is created with --static-urls.   | Boolean | optional |  `True`  |
| <a id="lock_import.import_pdm-target_environments"></a>target_environments |  A list of target environment descriptors.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `["@pycross_environments//:environments"]`  |

<a id="lock_import.import_poetry"></a>

### import_poetry

Import a Poetry lock file.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.import_poetry-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_poetry-disallow_builds"></a>disallow_builds |  If True, only pre-built wheels are allowed.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_poetry-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lock_import.import_poetry-lock_file"></a>lock_file |  The poetry.lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lock_import.import_poetry-project_file"></a>project_file |  The pyproject.toml file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lock_import.import_poetry-repo"></a>repo |  The repository name   | String | required |  |
| <a id="lock_import.import_poetry-target_environments"></a>target_environments |  A list of target environment descriptors.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `["@pycross_environments//:environments"]`  |

<a id="lock_import.package"></a>

### package

Specify package-specific settings.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.package-name"></a>name |  The package key (name or name@version).   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lock_import.package-always_build"></a>always_build |  If True, don't use pre-built wheels for this package.   | Boolean | optional |  `False`  |
| <a id="lock_import.package-build_dependencies"></a>build_dependencies |  A list of additional package keys (name or name@version) to use when building this package from source.   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-build_target"></a>build_target |  An optional override build target to use when and if this package needs to be built from source.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="lock_import.package-ignore_dependencies"></a>ignore_dependencies |  A list of package keys (name or name@version) to drop from this package's set of declared dependencies.   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-install_exclude_globs"></a>install_exclude_globs |  A list of globs for files to exclude during installation.   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-repo"></a>repo |  The repository name   | String | required |  |


