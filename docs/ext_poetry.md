<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The poetry extension.

<a id="poetry"></a>

## poetry

<pre>
poetry = use_extension("@rules_pycross//pycross/extensions:poetry.bzl", "poetry")
poetry.repo(<a href="#poetry.repo-name">name</a>, <a href="#poetry.repo-constraint_values">constraint_values</a>, <a href="#poetry.repo-create_transitive_aliases">create_transitive_aliases</a>, <a href="#poetry.repo-dependency_groups">dependency_groups</a>, <a href="#poetry.repo-flags">flags</a>,
            <a href="#poetry.repo-legacy_create_root_aliases">legacy_create_root_aliases</a>, <a href="#poetry.repo-platform">platform</a>, <a href="#poetry.repo-projects">projects</a>, <a href="#poetry.repo-workspace">workspace</a>)
poetry.package(<a href="#poetry.package-name">name</a>, <a href="#poetry.package-always_build">always_build</a>, <a href="#poetry.package-bin_paths">bin_paths</a>, <a href="#poetry.package-build_backend">build_backend</a>, <a href="#poetry.package-build_target">build_target</a>, <a href="#poetry.package-build_tools_repo">build_tools_repo</a>,
               <a href="#poetry.package-data_paths">data_paths</a>, <a href="#poetry.package-extra_build_tools">extra_build_tools</a>, <a href="#poetry.package-ignore_dependencies">ignore_dependencies</a>, <a href="#poetry.package-include_paths">include_paths</a>,
               <a href="#poetry.package-install_exclude_globs">install_exclude_globs</a>, <a href="#poetry.package-post_install_patches">post_install_patches</a>, <a href="#poetry.package-pre_build_patches">pre_build_patches</a>, <a href="#poetry.package-site_hooks">site_hooks</a>, <a href="#poetry.package-site_paths">site_paths</a>,
               <a href="#poetry.package-wheel_library_tags">wheel_library_tags</a>, <a href="#poetry.package-workspace">workspace</a>)
poetry.workspace(<a href="#poetry.workspace-name">name</a>, <a href="#poetry.workspace-disallow_builds">disallow_builds</a>, <a href="#poetry.workspace-extra_project_files">extra_project_files</a>, <a href="#poetry.workspace-local_wheels">local_wheels</a>, <a href="#poetry.workspace-lock_file">lock_file</a>, <a href="#poetry.workspace-pypi_indexes">pypi_indexes</a>)
</pre>


**TAG CLASSES**

<a id="poetry.repo"></a>

### repo

Override a poetry workspace member's settings.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="poetry.repo-name"></a>name |  Override the repo name.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | optional |  `""`  |
| <a id="poetry.repo-constraint_values"></a>constraint_values |  A list of constraint values to apply to the generated platform.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="poetry.repo-create_transitive_aliases"></a>create_transitive_aliases |  Generate aliases for transitive single-version packages in this repo.   | Boolean | optional |  `False`  |
| <a id="poetry.repo-dependency_groups"></a>dependency_groups |  A list of dependency groups to include. E.g. ['default', 'group:foo', '*']. Defaults to ['default'].   | List of strings | optional |  `["default"]`  |
| <a id="poetry.repo-flags"></a>flags |  A list of flags to apply to the generated platform (e.g., '--@flag=value').   | List of strings | optional |  `[]`  |
| <a id="poetry.repo-legacy_create_root_aliases"></a>legacy_create_root_aliases |  Create //:pkg aliases for bare packages in the generated repo. Useful for migrating from 1.x.   | Boolean | optional |  `False`  |
| <a id="poetry.repo-platform"></a>platform |  An existing platform target to use directly.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="poetry.repo-projects"></a>projects |  A list of project names to include. Use ['*'] to include all discovered projects.   | List of strings | optional |  `[]`  |
| <a id="poetry.repo-workspace"></a>workspace |  Name of the workspace this member belongs to.   | String | required |  |

<a id="poetry.package"></a>

### package

Specify package-specific settings.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="poetry.package-name"></a>name |  The package key (name or name@version). Can be '*' to apply to all packages in the workspace.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="poetry.package-always_build"></a>always_build |  If True, don't use pre-built wheels for this package.   | Boolean | optional |  `False`  |
| <a id="poetry.package-bin_paths"></a>bin_paths |  Override the auto-detected bin paths.   | List of strings | optional |  `[]`  |
| <a id="poetry.package-build_backend"></a>build_backend |  An explicit build backend rule name to use for this package.   | String | optional |  `""`  |
| <a id="poetry.package-build_target"></a>build_target |  An optional override build target to use when building from source.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="poetry.package-build_tools_repo"></a>build_tools_repo |  Optional repo to use for resolving sdist build dependencies for this package.   | String | optional |  `""`  |
| <a id="poetry.package-data_paths"></a>data_paths |  Override the auto-detected data paths.   | List of strings | optional |  `[]`  |
| <a id="poetry.package-extra_build_tools"></a>extra_build_tools |  A list of additional package keys to use when building this package from source.   | List of strings | optional |  `[]`  |
| <a id="poetry.package-ignore_dependencies"></a>ignore_dependencies |  A list of package keys to drop from this package's declared dependencies.   | List of strings | optional |  `[]`  |
| <a id="poetry.package-include_paths"></a>include_paths |  Override the auto-detected include paths.   | List of strings | optional |  `[]`  |
| <a id="poetry.package-install_exclude_globs"></a>install_exclude_globs |  A list of globs for files to exclude during installation.   | List of strings | optional |  `[]`  |
| <a id="poetry.package-post_install_patches"></a>post_install_patches |  A list of patches to apply after wheel installation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="poetry.package-pre_build_patches"></a>pre_build_patches |  A list of patches to apply to the sdist source tree before building.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="poetry.package-site_hooks"></a>site_hooks |  A list of Python code snippets to execute on interpreter startup during builds.   | List of strings | optional |  `[]`  |
| <a id="poetry.package-site_paths"></a>site_paths |  Override the auto-detected top-level importable paths.   | List of strings | optional |  `[]`  |
| <a id="poetry.package-wheel_library_tags"></a>wheel_library_tags |  Optional tags to apply to the generated pycross_wheel_library target.   | List of strings | optional |  `[]`  |
| <a id="poetry.package-workspace"></a>workspace |  The workspace name (optional if inferable).   | String | optional |  `""`  |

<a id="poetry.workspace"></a>

### workspace

Declare a poetry workspace from a shared lock file.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="poetry.workspace-name"></a>name |  Workspace name. Used to link members to this workspace.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="poetry.workspace-disallow_builds"></a>disallow_builds |  If True, only pre-built wheels are allowed.   | Boolean | optional |  `False`  |
| <a id="poetry.workspace-extra_project_files"></a>extra_project_files |  Optional list of extra pyproject.toml files to consider.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="poetry.workspace-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="poetry.workspace-lock_file"></a>lock_file |  The shared lock file for the workspace.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="poetry.workspace-pypi_indexes"></a>pypi_indexes |  List of PyPI-compatible indexes to use for downloading packages.   | List of strings | optional |  `[]`  |


