<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The pylock extension.

<a id="pylock"></a>

## pylock

<pre>
pylock = use_extension("@rules_pycross//pycross/extensions:pylock.bzl", "pylock")
pylock.repo(<a href="#pylock.repo-name">name</a>, <a href="#pylock.repo-constraint_values">constraint_values</a>, <a href="#pylock.repo-create_transitive_aliases">create_transitive_aliases</a>, <a href="#pylock.repo-dependency_groups">dependency_groups</a>, <a href="#pylock.repo-flags">flags</a>,
            <a href="#pylock.repo-legacy_create_root_aliases">legacy_create_root_aliases</a>, <a href="#pylock.repo-platform">platform</a>, <a href="#pylock.repo-projects">projects</a>, <a href="#pylock.repo-workspace">workspace</a>)
pylock.package(<a href="#pylock.package-name">name</a>, <a href="#pylock.package-always_build">always_build</a>, <a href="#pylock.package-bin_paths">bin_paths</a>, <a href="#pylock.package-build_backend">build_backend</a>, <a href="#pylock.package-build_target">build_target</a>, <a href="#pylock.package-build_tools_repo">build_tools_repo</a>,
               <a href="#pylock.package-data_paths">data_paths</a>, <a href="#pylock.package-extra_build_tools">extra_build_tools</a>, <a href="#pylock.package-ignore_dependencies">ignore_dependencies</a>, <a href="#pylock.package-include_paths">include_paths</a>,
               <a href="#pylock.package-install_exclude_globs">install_exclude_globs</a>, <a href="#pylock.package-post_install_patches">post_install_patches</a>, <a href="#pylock.package-pre_build_patches">pre_build_patches</a>, <a href="#pylock.package-site_hooks">site_hooks</a>, <a href="#pylock.package-site_paths">site_paths</a>,
               <a href="#pylock.package-wheel_library_tags">wheel_library_tags</a>, <a href="#pylock.package-workspace">workspace</a>)
pylock.workspace(<a href="#pylock.workspace-name">name</a>, <a href="#pylock.workspace-disallow_builds">disallow_builds</a>, <a href="#pylock.workspace-extra_project_files">extra_project_files</a>, <a href="#pylock.workspace-local_wheels">local_wheels</a>, <a href="#pylock.workspace-lock_file">lock_file</a>, <a href="#pylock.workspace-pypi_indexes">pypi_indexes</a>)
</pre>


**TAG CLASSES**

<a id="pylock.repo"></a>

### repo

Override a pylock workspace member's settings.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pylock.repo-name"></a>name |  Override the repo name.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | optional |  `""`  |
| <a id="pylock.repo-constraint_values"></a>constraint_values |  A list of constraint values to apply to the generated platform.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pylock.repo-create_transitive_aliases"></a>create_transitive_aliases |  Generate aliases for transitive single-version packages in this repo.   | Boolean | optional |  `False`  |
| <a id="pylock.repo-dependency_groups"></a>dependency_groups |  A list of dependency groups to include. E.g. ['default', 'group:foo', '*']. Defaults to ['default'].   | List of strings | optional |  `["default"]`  |
| <a id="pylock.repo-flags"></a>flags |  A list of flags to apply to the generated platform (e.g., '--@flag=value').   | List of strings | optional |  `[]`  |
| <a id="pylock.repo-legacy_create_root_aliases"></a>legacy_create_root_aliases |  Create //:pkg aliases for bare packages in the generated repo. Useful for migrating from 1.x.   | Boolean | optional |  `False`  |
| <a id="pylock.repo-platform"></a>platform |  An existing platform target to use directly.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="pylock.repo-projects"></a>projects |  A list of project names to include. Use ['*'] to include all discovered projects.   | List of strings | optional |  `[]`  |
| <a id="pylock.repo-workspace"></a>workspace |  Name of the workspace this member belongs to.   | String | required |  |

<a id="pylock.package"></a>

### package

Specify package-specific settings.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pylock.package-name"></a>name |  The package key (name or name@version). Can be '*' to apply to all packages in the workspace.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pylock.package-always_build"></a>always_build |  If True, don't use pre-built wheels for this package.   | Boolean | optional |  `False`  |
| <a id="pylock.package-bin_paths"></a>bin_paths |  Override the auto-detected bin paths.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-build_backend"></a>build_backend |  An explicit build backend rule name to use for this package.   | String | optional |  `""`  |
| <a id="pylock.package-build_target"></a>build_target |  An optional override build target to use when building from source.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="pylock.package-build_tools_repo"></a>build_tools_repo |  Optional repo to use for resolving sdist build dependencies for this package.   | String | optional |  `""`  |
| <a id="pylock.package-data_paths"></a>data_paths |  Override the auto-detected data paths.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-extra_build_tools"></a>extra_build_tools |  A list of additional package keys to use when building this package from source.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-ignore_dependencies"></a>ignore_dependencies |  A list of package keys to drop from this package's declared dependencies.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-include_paths"></a>include_paths |  Override the auto-detected include paths.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-install_exclude_globs"></a>install_exclude_globs |  A list of globs for files to exclude during installation.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-post_install_patches"></a>post_install_patches |  A list of patches to apply after wheel installation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pylock.package-pre_build_patches"></a>pre_build_patches |  A list of patches to apply to the sdist source tree before building.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pylock.package-site_hooks"></a>site_hooks |  A list of Python code snippets to execute on interpreter startup during builds.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-site_paths"></a>site_paths |  Override the auto-detected top-level importable paths.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-wheel_library_tags"></a>wheel_library_tags |  Optional tags to apply to the generated pycross_wheel_library target.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-workspace"></a>workspace |  The workspace name (optional if inferable).   | String | optional |  `""`  |

<a id="pylock.workspace"></a>

### workspace

Declare a pylock workspace from a shared lock file.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pylock.workspace-name"></a>name |  Workspace name. Used to link members to this workspace.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pylock.workspace-disallow_builds"></a>disallow_builds |  If True, only pre-built wheels are allowed.   | Boolean | optional |  `False`  |
| <a id="pylock.workspace-extra_project_files"></a>extra_project_files |  Optional list of extra pyproject.toml files to consider.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pylock.workspace-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pylock.workspace-lock_file"></a>lock_file |  The shared lock file for the workspace.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pylock.workspace-pypi_indexes"></a>pypi_indexes |  List of PyPI-compatible indexes to use for downloading packages.   | List of strings | optional |  `[]`  |


