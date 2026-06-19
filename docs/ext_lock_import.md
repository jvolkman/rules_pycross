<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The lock_import extension.

<a id="lock_import"></a>

## lock_import

<pre>
lock_import = use_extension("@rules_pycross//pycross/extensions:lock_import.bzl", "lock_import")
lock_import.import_pdm(<a href="#lock_import.import_pdm-all_development_groups">all_development_groups</a>, <a href="#lock_import.import_pdm-all_optional_groups">all_optional_groups</a>, <a href="#lock_import.import_pdm-build_repo">build_repo</a>,
                       <a href="#lock_import.import_pdm-default_alias_single_version">default_alias_single_version</a>, <a href="#lock_import.import_pdm-default_build_dependencies">default_build_dependencies</a>, <a href="#lock_import.import_pdm-default_group">default_group</a>,
                       <a href="#lock_import.import_pdm-development_groups">development_groups</a>, <a href="#lock_import.import_pdm-disallow_builds">disallow_builds</a>, <a href="#lock_import.import_pdm-local_wheels">local_wheels</a>, <a href="#lock_import.import_pdm-lock_file">lock_file</a>, <a href="#lock_import.import_pdm-optional_groups">optional_groups</a>,
                       <a href="#lock_import.import_pdm-project_file">project_file</a>, <a href="#lock_import.import_pdm-repo">repo</a>, <a href="#lock_import.import_pdm-require_static_urls">require_static_urls</a>, <a href="#lock_import.import_pdm-target_environments">target_environments</a>)
lock_import.import_poetry(<a href="#lock_import.import_poetry-all_optional_groups">all_optional_groups</a>, <a href="#lock_import.import_poetry-build_repo">build_repo</a>, <a href="#lock_import.import_poetry-default_alias_single_version">default_alias_single_version</a>,
                          <a href="#lock_import.import_poetry-default_build_dependencies">default_build_dependencies</a>, <a href="#lock_import.import_poetry-default_group">default_group</a>, <a href="#lock_import.import_poetry-disallow_builds">disallow_builds</a>, <a href="#lock_import.import_poetry-local_wheels">local_wheels</a>,
                          <a href="#lock_import.import_poetry-lock_file">lock_file</a>, <a href="#lock_import.import_poetry-optional_groups">optional_groups</a>, <a href="#lock_import.import_poetry-project_file">project_file</a>, <a href="#lock_import.import_poetry-repo">repo</a>, <a href="#lock_import.import_poetry-target_environments">target_environments</a>)
lock_import.import_uv(<a href="#lock_import.import_uv-all_development_groups">all_development_groups</a>, <a href="#lock_import.import_uv-all_optional_groups">all_optional_groups</a>, <a href="#lock_import.import_uv-build_repo">build_repo</a>,
                      <a href="#lock_import.import_uv-default_alias_single_version">default_alias_single_version</a>, <a href="#lock_import.import_uv-default_build_dependencies">default_build_dependencies</a>, <a href="#lock_import.import_uv-default_group">default_group</a>,
                      <a href="#lock_import.import_uv-development_groups">development_groups</a>, <a href="#lock_import.import_uv-disallow_builds">disallow_builds</a>, <a href="#lock_import.import_uv-local_wheels">local_wheels</a>, <a href="#lock_import.import_uv-lock_file">lock_file</a>, <a href="#lock_import.import_uv-optional_groups">optional_groups</a>,
                      <a href="#lock_import.import_uv-project_file">project_file</a>, <a href="#lock_import.import_uv-repo">repo</a>, <a href="#lock_import.import_uv-require_static_urls">require_static_urls</a>, <a href="#lock_import.import_uv-target_environments">target_environments</a>)
lock_import.import_pylock(<a href="#lock_import.import_pylock-all_development_groups">all_development_groups</a>, <a href="#lock_import.import_pylock-all_optional_groups">all_optional_groups</a>, <a href="#lock_import.import_pylock-build_repo">build_repo</a>,
                          <a href="#lock_import.import_pylock-default_alias_single_version">default_alias_single_version</a>, <a href="#lock_import.import_pylock-default_build_dependencies">default_build_dependencies</a>, <a href="#lock_import.import_pylock-default_group">default_group</a>,
                          <a href="#lock_import.import_pylock-development_groups">development_groups</a>, <a href="#lock_import.import_pylock-disallow_builds">disallow_builds</a>, <a href="#lock_import.import_pylock-local_wheels">local_wheels</a>, <a href="#lock_import.import_pylock-lock_file">lock_file</a>,
                          <a href="#lock_import.import_pylock-optional_groups">optional_groups</a>, <a href="#lock_import.import_pylock-project_file">project_file</a>, <a href="#lock_import.import_pylock-repo">repo</a>, <a href="#lock_import.import_pylock-target_environments">target_environments</a>)
lock_import.import_pdm_workspace(<a href="#lock_import.import_pdm_workspace-name">name</a>, <a href="#lock_import.import_pdm_workspace-build_repo">build_repo</a>, <a href="#lock_import.import_pdm_workspace-default_alias_single_version">default_alias_single_version</a>,
                                 <a href="#lock_import.import_pdm_workspace-default_build_dependencies">default_build_dependencies</a>, <a href="#lock_import.import_pdm_workspace-disallow_builds">disallow_builds</a>, <a href="#lock_import.import_pdm_workspace-local_wheels">local_wheels</a>, <a href="#lock_import.import_pdm_workspace-lock_file">lock_file</a>,
                                 <a href="#lock_import.import_pdm_workspace-target_environments">target_environments</a>)
lock_import.pdm_all_members(<a href="#lock_import.pdm_all_members-all_development_groups">all_development_groups</a>, <a href="#lock_import.pdm_all_members-all_optional_groups">all_optional_groups</a>, <a href="#lock_import.pdm_all_members-development_groups">development_groups</a>,
                            <a href="#lock_import.pdm_all_members-excluded_projects">excluded_projects</a>, <a href="#lock_import.pdm_all_members-optional_groups">optional_groups</a>, <a href="#lock_import.pdm_all_members-repo_pattern">repo_pattern</a>, <a href="#lock_import.pdm_all_members-workspace">workspace</a>)
lock_import.pdm_member(<a href="#lock_import.pdm_member-default_group">default_group</a>, <a href="#lock_import.pdm_member-development_groups">development_groups</a>, <a href="#lock_import.pdm_member-optional_groups">optional_groups</a>, <a href="#lock_import.pdm_member-project">project</a>, <a href="#lock_import.pdm_member-project_file">project_file</a>,
                       <a href="#lock_import.pdm_member-repo">repo</a>, <a href="#lock_import.pdm_member-workspace">workspace</a>)
lock_import.import_uv_workspace(<a href="#lock_import.import_uv_workspace-name">name</a>, <a href="#lock_import.import_uv_workspace-build_repo">build_repo</a>, <a href="#lock_import.import_uv_workspace-default_alias_single_version">default_alias_single_version</a>,
                                <a href="#lock_import.import_uv_workspace-default_build_dependencies">default_build_dependencies</a>, <a href="#lock_import.import_uv_workspace-disallow_builds">disallow_builds</a>, <a href="#lock_import.import_uv_workspace-local_wheels">local_wheels</a>, <a href="#lock_import.import_uv_workspace-lock_file">lock_file</a>,
                                <a href="#lock_import.import_uv_workspace-require_static_urls">require_static_urls</a>, <a href="#lock_import.import_uv_workspace-target_environments">target_environments</a>)
lock_import.uv_all_members(<a href="#lock_import.uv_all_members-all_development_groups">all_development_groups</a>, <a href="#lock_import.uv_all_members-all_optional_groups">all_optional_groups</a>, <a href="#lock_import.uv_all_members-development_groups">development_groups</a>,
                           <a href="#lock_import.uv_all_members-excluded_projects">excluded_projects</a>, <a href="#lock_import.uv_all_members-optional_groups">optional_groups</a>, <a href="#lock_import.uv_all_members-repo_pattern">repo_pattern</a>, <a href="#lock_import.uv_all_members-workspace">workspace</a>)
lock_import.uv_member(<a href="#lock_import.uv_member-default_group">default_group</a>, <a href="#lock_import.uv_member-development_groups">development_groups</a>, <a href="#lock_import.uv_member-optional_groups">optional_groups</a>, <a href="#lock_import.uv_member-project">project</a>, <a href="#lock_import.uv_member-project_file">project_file</a>,
                      <a href="#lock_import.uv_member-repo">repo</a>, <a href="#lock_import.uv_member-workspace">workspace</a>)
lock_import.package(<a href="#lock_import.package-name">name</a>, <a href="#lock_import.package-always_build">always_build</a>, <a href="#lock_import.package-bin_paths">bin_paths</a>, <a href="#lock_import.package-build_backend">build_backend</a>, <a href="#lock_import.package-build_dependencies">build_dependencies</a>, <a href="#lock_import.package-build_repo">build_repo</a>,
                    <a href="#lock_import.package-build_target">build_target</a>, <a href="#lock_import.package-data_paths">data_paths</a>, <a href="#lock_import.package-ignore_dependencies">ignore_dependencies</a>, <a href="#lock_import.package-include_paths">include_paths</a>,
                    <a href="#lock_import.package-install_exclude_globs">install_exclude_globs</a>, <a href="#lock_import.package-post_install_patches">post_install_patches</a>, <a href="#lock_import.package-pre_build_patches">pre_build_patches</a>, <a href="#lock_import.package-repo">repo</a>, <a href="#lock_import.package-site_hooks">site_hooks</a>,
                    <a href="#lock_import.package-site_paths">site_paths</a>, <a href="#lock_import.package-workspace">workspace</a>)
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
| <a id="lock_import.import_pdm-build_repo"></a>build_repo |  Optional default repo to use for resolving sdist build dependencies.   | String | optional |  `""`  |
| <a id="lock_import.import_pdm-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pdm-default_build_dependencies"></a>default_build_dependencies |  A list of package keys (name or name@version) that will be used as default build dependencies.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_pdm-default_group"></a>default_group |  Whether to install dependencies from the default group.   | Boolean | optional |  `True`  |
| <a id="lock_import.import_pdm-development_groups"></a>development_groups |  List of development dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_pdm-disallow_builds"></a>disallow_builds |  If True, only pre-built wheels are allowed.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pdm-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lock_import.import_pdm-lock_file"></a>lock_file |  The lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lock_import.import_pdm-optional_groups"></a>optional_groups |  List of optional dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_pdm-project_file"></a>project_file |  The pyproject.toml file. If not specified, defaults to pyproject.toml next to the lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="lock_import.import_pdm-repo"></a>repo |  The repository name   | String | required |  |
| <a id="lock_import.import_pdm-require_static_urls"></a>require_static_urls |  Require that the lock file is created with --static-urls.   | Boolean | optional |  `True`  |
| <a id="lock_import.import_pdm-target_environments"></a>target_environments |  A list of target environment descriptors.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `["@@rules_pycross++environments+pycross_environments//:environments"]`  |

<a id="lock_import.import_poetry"></a>

### import_poetry

Import a Poetry lock file.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.import_poetry-all_optional_groups"></a>all_optional_groups |  Install all optional dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_poetry-build_repo"></a>build_repo |  Optional default repo to use for resolving sdist build dependencies.   | String | optional |  `""`  |
| <a id="lock_import.import_poetry-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_poetry-default_build_dependencies"></a>default_build_dependencies |  A list of package keys (name or name@version) that will be used as default build dependencies.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_poetry-default_group"></a>default_group |  Whether to install dependencies from the default group.   | Boolean | optional |  `True`  |
| <a id="lock_import.import_poetry-disallow_builds"></a>disallow_builds |  If True, only pre-built wheels are allowed.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_poetry-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lock_import.import_poetry-lock_file"></a>lock_file |  The poetry.lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lock_import.import_poetry-optional_groups"></a>optional_groups |  List of optional dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_poetry-project_file"></a>project_file |  The pyproject.toml file. If not specified, defaults to pyproject.toml next to the lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="lock_import.import_poetry-repo"></a>repo |  The repository name   | String | required |  |
| <a id="lock_import.import_poetry-target_environments"></a>target_environments |  A list of target environment descriptors.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `["@@rules_pycross++environments+pycross_environments//:environments"]`  |

<a id="lock_import.import_uv"></a>

### import_uv

Import a uv lock file.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.import_uv-all_development_groups"></a>all_development_groups |  Install all dev dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_uv-all_optional_groups"></a>all_optional_groups |  Install all optional dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_uv-build_repo"></a>build_repo |  Optional default repo to use for resolving sdist build dependencies.   | String | optional |  `""`  |
| <a id="lock_import.import_uv-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_uv-default_build_dependencies"></a>default_build_dependencies |  A list of package keys (name or name@version) that will be used as default build dependencies.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_uv-default_group"></a>default_group |  Whether to install dependencies from the default group.   | Boolean | optional |  `True`  |
| <a id="lock_import.import_uv-development_groups"></a>development_groups |  List of development dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_uv-disallow_builds"></a>disallow_builds |  If True, only pre-built wheels are allowed.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_uv-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lock_import.import_uv-lock_file"></a>lock_file |  The lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lock_import.import_uv-optional_groups"></a>optional_groups |  List of optional dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_uv-project_file"></a>project_file |  The pyproject.toml file. If not specified, defaults to pyproject.toml next to the lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="lock_import.import_uv-repo"></a>repo |  The repository name   | String | required |  |
| <a id="lock_import.import_uv-require_static_urls"></a>require_static_urls |  Require that the lock file is created with --static-urls.   | Boolean | optional |  `True`  |
| <a id="lock_import.import_uv-target_environments"></a>target_environments |  A list of target environment descriptors.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `["@@rules_pycross++environments+pycross_environments//:environments"]`  |

<a id="lock_import.import_pylock"></a>

### import_pylock

Import a pylock.toml lock file.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.import_pylock-all_development_groups"></a>all_development_groups |  Install all dev dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pylock-all_optional_groups"></a>all_optional_groups |  Install all optional dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pylock-build_repo"></a>build_repo |  Optional default repo to use for resolving sdist build dependencies.   | String | optional |  `""`  |
| <a id="lock_import.import_pylock-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pylock-default_build_dependencies"></a>default_build_dependencies |  A list of package keys (name or name@version) that will be used as default build dependencies.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_pylock-default_group"></a>default_group |  Whether to install dependencies from the default group.   | Boolean | optional |  `True`  |
| <a id="lock_import.import_pylock-development_groups"></a>development_groups |  List of development dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_pylock-disallow_builds"></a>disallow_builds |  If True, only pre-built wheels are allowed.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pylock-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lock_import.import_pylock-lock_file"></a>lock_file |  The pylock.toml file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lock_import.import_pylock-optional_groups"></a>optional_groups |  List of optional dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_pylock-project_file"></a>project_file |  Optional pyproject.toml file.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="lock_import.import_pylock-repo"></a>repo |  The repository name   | String | required |  |
| <a id="lock_import.import_pylock-target_environments"></a>target_environments |  A list of target environment descriptors.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `["@@rules_pycross++environments+pycross_environments//:environments"]`  |

<a id="lock_import.import_pdm_workspace"></a>

### import_pdm_workspace

Import a PDM workspace.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.import_pdm_workspace-name"></a>name |  Workspace name. Used to link members to this workspace.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lock_import.import_pdm_workspace-build_repo"></a>build_repo |  Optional default repo to use for resolving sdist build dependencies.   | String | optional |  `""`  |
| <a id="lock_import.import_pdm_workspace-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pdm_workspace-default_build_dependencies"></a>default_build_dependencies |  A list of package keys (name or name@version) that will be used as default build dependencies.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_pdm_workspace-disallow_builds"></a>disallow_builds |  If True, only pre-built wheels are allowed.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_pdm_workspace-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lock_import.import_pdm_workspace-lock_file"></a>lock_file |  The shared pdm.lock file for the workspace.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lock_import.import_pdm_workspace-target_environments"></a>target_environments |  A list of target environment descriptors.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `["@@rules_pycross++environments+pycross_environments//:environments"]`  |

<a id="lock_import.pdm_all_members"></a>

### pdm_all_members

Auto-discover and import all members from a pdm.lock file.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.pdm_all_members-all_development_groups"></a>all_development_groups |  Install all dev dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.pdm_all_members-all_optional_groups"></a>all_optional_groups |  Install all optional dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.pdm_all_members-development_groups"></a>development_groups |  List of development dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.pdm_all_members-excluded_projects"></a>excluded_projects |  Project names to skip during auto-discovery.   | List of strings | optional |  `[]`  |
| <a id="lock_import.pdm_all_members-optional_groups"></a>optional_groups |  List of optional dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.pdm_all_members-repo_pattern"></a>repo_pattern |  Pattern for auto-generated repo names. Use '{member}' as a placeholder for the normalized project name. For example, 'ws_{member}' produces 'ws_lib_a' for a project named 'lib-a'. Default is '{member}'.   | String | optional |  `"{member}"`  |
| <a id="lock_import.pdm_all_members-workspace"></a>workspace |  Name of the workspace this member belongs to.   | String | required |  |

<a id="lock_import.pdm_member"></a>

### pdm_member

Override settings for a specific PDM member.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.pdm_member-default_group"></a>default_group |  Whether to install dependencies from the default group.   | Boolean | optional |  `True`  |
| <a id="lock_import.pdm_member-development_groups"></a>development_groups |  List of development dependency groups to install (overrides all_members setting).   | List of strings | optional |  `[]`  |
| <a id="lock_import.pdm_member-optional_groups"></a>optional_groups |  List of optional dependency groups to install (overrides all_members setting).   | List of strings | optional |  `[]`  |
| <a id="lock_import.pdm_member-project"></a>project |  The project name as it appears in pdm.lock. Optional if the workspace has only one member.   | String | optional |  `""`  |
| <a id="lock_import.pdm_member-project_file"></a>project_file |  Override auto-discovered pyproject.toml path.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="lock_import.pdm_member-repo"></a>repo |  Override the repo name (default: {prefix}{normalized_project_name}).   | String | optional |  `""`  |
| <a id="lock_import.pdm_member-workspace"></a>workspace |  Name of the workspace this member belongs to.   | String | required |  |

<a id="lock_import.import_uv_workspace"></a>

### import_uv_workspace

Import a uv workspace. Define members with uv_all_members and uv_member tags.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.import_uv_workspace-name"></a>name |  Workspace name. Used to link members to this workspace.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lock_import.import_uv_workspace-build_repo"></a>build_repo |  Optional default repo to use for resolving sdist build dependencies.   | String | optional |  `""`  |
| <a id="lock_import.import_uv_workspace-default_alias_single_version"></a>default_alias_single_version |  Generate aliases for all packages that have a single version in the lock file.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_uv_workspace-default_build_dependencies"></a>default_build_dependencies |  A list of package keys (name or name@version) that will be used as default build dependencies.   | List of strings | optional |  `[]`  |
| <a id="lock_import.import_uv_workspace-disallow_builds"></a>disallow_builds |  If True, only pre-built wheels are allowed.   | Boolean | optional |  `False`  |
| <a id="lock_import.import_uv_workspace-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lock_import.import_uv_workspace-lock_file"></a>lock_file |  The shared uv.lock file for the workspace.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lock_import.import_uv_workspace-require_static_urls"></a>require_static_urls |  Require that the lock file is created with --static-urls.   | Boolean | optional |  `True`  |
| <a id="lock_import.import_uv_workspace-target_environments"></a>target_environments |  A list of target environment descriptors.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `["@@rules_pycross++environments+pycross_environments//:environments"]`  |

<a id="lock_import.uv_all_members"></a>

### uv_all_members

Auto-discover and import all members from a uv.lock file.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.uv_all_members-all_development_groups"></a>all_development_groups |  Install all dev dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.uv_all_members-all_optional_groups"></a>all_optional_groups |  Install all optional dependencies.   | Boolean | optional |  `False`  |
| <a id="lock_import.uv_all_members-development_groups"></a>development_groups |  List of development dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.uv_all_members-excluded_projects"></a>excluded_projects |  Project names to skip during auto-discovery.   | List of strings | optional |  `[]`  |
| <a id="lock_import.uv_all_members-optional_groups"></a>optional_groups |  List of optional dependency groups to install.   | List of strings | optional |  `[]`  |
| <a id="lock_import.uv_all_members-repo_pattern"></a>repo_pattern |  Pattern for auto-generated repo names. Use '{member}' as a placeholder for the normalized project name. For example, 'ws_{member}' produces 'ws_lib_a' for a project named 'lib-a'. Default is '{member}'.   | String | optional |  `"{member}"`  |
| <a id="lock_import.uv_all_members-workspace"></a>workspace |  Name of the workspace this member belongs to.   | String | required |  |

<a id="lock_import.uv_member"></a>

### uv_member

Override settings for a specific member.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.uv_member-default_group"></a>default_group |  Whether to install dependencies from the default group.   | Boolean | optional |  `True`  |
| <a id="lock_import.uv_member-development_groups"></a>development_groups |  List of development dependency groups to install (overrides all_members setting).   | List of strings | optional |  `[]`  |
| <a id="lock_import.uv_member-optional_groups"></a>optional_groups |  List of optional dependency groups to install (overrides all_members setting).   | List of strings | optional |  `[]`  |
| <a id="lock_import.uv_member-project"></a>project |  The project name as it appears in uv.lock. Optional if the workspace has only one member.   | String | optional |  `""`  |
| <a id="lock_import.uv_member-project_file"></a>project_file |  Override auto-discovered pyproject.toml path.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="lock_import.uv_member-repo"></a>repo |  Override the repo name (default: {prefix}{normalized_project_name}).   | String | optional |  `""`  |
| <a id="lock_import.uv_member-workspace"></a>workspace |  Name of the workspace this member belongs to.   | String | required |  |

<a id="lock_import.package"></a>

### package

Specify package-specific settings.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_import.package-name"></a>name |  The package key (name or name@version).   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lock_import.package-always_build"></a>always_build |  If True, don't use pre-built wheels for this package.   | Boolean | optional |  `False`  |
| <a id="lock_import.package-bin_paths"></a>bin_paths |  Override the auto-detected bin paths.   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-build_backend"></a>build_backend |  An explicit build backend rule name to use for this package (e.g. 'maturin_build'). Overrides pyproject.toml detection.   | String | optional |  `""`  |
| <a id="lock_import.package-build_dependencies"></a>build_dependencies |  A list of additional package keys (name or name@version) to use when building this package from source.   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-build_repo"></a>build_repo |  Optional repo to use for resolving sdist build dependencies for this package.   | String | optional |  `""`  |
| <a id="lock_import.package-build_target"></a>build_target |  An optional override build target to use when and if this package needs to be built from source.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="lock_import.package-data_paths"></a>data_paths |  Override the auto-detected data paths.   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-ignore_dependencies"></a>ignore_dependencies |  A list of package keys (name or name@version) to drop from this package's set of declared dependencies.   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-include_paths"></a>include_paths |  Override the auto-detected include paths.   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-install_exclude_globs"></a>install_exclude_globs |  A list of globs for files to exclude during installation.   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-post_install_patches"></a>post_install_patches |  A list of patches to apply after wheel installation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lock_import.package-pre_build_patches"></a>pre_build_patches |  A list of patches to apply to the sdist source tree before building.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lock_import.package-repo"></a>repo |  The repository name (if applying to a specific lock file).   | String | optional |  `""`  |
| <a id="lock_import.package-site_hooks"></a>site_hooks |  A list of Python code snippets to execute on interpreter startup during builds.   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-site_paths"></a>site_paths |  Override the auto-detected top-level importable paths (packages, .pth files, standalone modules). Use forward slashes for nested namespaces (e.g. 'google/cloud/storage').   | List of strings | optional |  `[]`  |
| <a id="lock_import.package-workspace"></a>workspace |  The workspace name (if applying to all members of a workspace).   | String | optional |  `""`  |


