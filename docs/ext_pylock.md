<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The pylock extension.

<a id="pylock"></a>

## pylock

<pre>
pylock = use_extension("@rules_pycross//pycross/extensions:pylock.bzl", "pylock")
pylock.repo(<a href="#pylock.repo-name">name</a>, <a href="#pylock.repo-constraint_values">constraint_values</a>, <a href="#pylock.repo-dependency_groups">dependency_groups</a>, <a href="#pylock.repo-flags">flags</a>, <a href="#pylock.repo-platform">platform</a>, <a href="#pylock.repo-projects">projects</a>, <a href="#pylock.repo-settings">settings</a>,
            <a href="#pylock.repo-workspace">workspace</a>)
pylock.package(<a href="#pylock.package-name">name</a>, <a href="#pylock.package-bin_paths">bin_paths</a>, <a href="#pylock.package-build_backend">build_backend</a>, <a href="#pylock.package-build_mode">build_mode</a>, <a href="#pylock.package-build_target">build_target</a>, <a href="#pylock.package-build_tools_repo">build_tools_repo</a>,
               <a href="#pylock.package-data_paths">data_paths</a>, <a href="#pylock.package-extra_build_tools">extra_build_tools</a>, <a href="#pylock.package-extra_dependencies">extra_dependencies</a>, <a href="#pylock.package-ignore_dependencies">ignore_dependencies</a>, <a href="#pylock.package-include_paths">include_paths</a>,
               <a href="#pylock.package-install_exclude_globs">install_exclude_globs</a>, <a href="#pylock.package-post_install_patches">post_install_patches</a>, <a href="#pylock.package-pre_build_patches">pre_build_patches</a>, <a href="#pylock.package-site_hooks">site_hooks</a>, <a href="#pylock.package-site_paths">site_paths</a>,
               <a href="#pylock.package-wheel_library_tags">wheel_library_tags</a>, <a href="#pylock.package-workspace">workspace</a>)
pylock.workspace(<a href="#pylock.workspace-name">name</a>, <a href="#pylock.workspace-extra_project_files">extra_project_files</a>, <a href="#pylock.workspace-local_wheels">local_wheels</a>, <a href="#pylock.workspace-lock_file">lock_file</a>, <a href="#pylock.workspace-pypi_indexes">pypi_indexes</a>)
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
| <a id="pylock.repo-dependency_groups"></a>dependency_groups |  A list of target groups to include. E.g. ['default', 'group:foo', '*']. Use 'transitive' to generate aliases for transitively-reachable packages. Defaults to ['default'].   | List of strings | optional |  `["default"]`  |
| <a id="pylock.repo-flags"></a>flags |  Flags applied to this repo's targets via a transition, written like the command line: `--<flag>[=<value>]` (a missing value means `True`), e.g. `--@repo//_variants:extra_x=True` or `--compilation_mode=opt`. Repeat an entry to pass multiple values to a list setting; each entry is one element (no comma splitting). `@repo` labels must be visible to rules_pycross (e.g. repos from this extension); use `settings` for other build settings.   | List of strings | optional |  `[]`  |
| <a id="pylock.repo-platform"></a>platform |  An existing platform target to use directly.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="pylock.repo-projects"></a>projects |  A list of project names to include. Use ['*'] to include all discovered projects.   | List of strings | optional |  `[]`  |
| <a id="pylock.repo-settings"></a>settings |  Build settings applied to this repo's targets via a transition, as `{label: value}`. Labels resolve relative to the declaring module. List settings split the value on commas. Use `flags` for built-in options.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: Label -> String</a> | optional |  `{}`  |
| <a id="pylock.repo-workspace"></a>workspace |  Name of the workspace this member belongs to.   | String | required |  |

<a id="pylock.package"></a>

### package

Specify package-specific settings.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pylock.package-name"></a>name |  The package key (name or name@version). Can be '*' to apply to all packages in the workspace.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pylock.package-bin_paths"></a>bin_paths |  Override the auto-detected bin paths.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-build_backend"></a>build_backend |  An explicit pycross build rule name to use for this package (e.g. 'maturin_build'), overriding the rule auto-selected from pyproject.toml's build-backend. The sdist's declared PEP 517 backend is still invoked, and its build-system.requires are still added as build dependencies.   | String | optional |  `""`  |
| <a id="pylock.package-build_mode"></a>build_mode |  How to choose between pre-built wheels and building from source. `auto` (the default): use a matching wheel if there is one, otherwise build the sdist. `always`: always build from source. `never`: never build the sdist; fail if no wheel matches (a `build_target` is still used). Unset (`""`) inherits from the `*` entry.   | String | optional |  `""`  |
| <a id="pylock.package-build_target"></a>build_target |  An optional override build target to use when building from source.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="pylock.package-build_tools_repo"></a>build_tools_repo |  Optional repo to use for resolving sdist build dependencies for this package.   | String | optional |  `""`  |
| <a id="pylock.package-data_paths"></a>data_paths |  Override the auto-detected data paths.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-extra_build_tools"></a>extra_build_tools |  A list of additional package keys to use when building this package from source.   | List of strings | optional |  `[]`  |
| <a id="pylock.package-extra_dependencies"></a>extra_dependencies |  A list of package keys to add to this package's runtime dependencies.   | List of strings | optional |  `[]`  |
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
| <a id="pylock.workspace-extra_project_files"></a>extra_project_files |  Optional list of extra pyproject.toml files to consider.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pylock.workspace-local_wheels"></a>local_wheels |  A list of local .whl files to consider when processing lock files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="pylock.workspace-lock_file"></a>lock_file |  The shared lock file for the workspace.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pylock.workspace-pypi_indexes"></a>pypi_indexes |  Simple Repository API (PEP 503/691) index URLs, e.g. `https://pypi.org/simple`. Lock entries without a download URL or per-package index are looked up in each index in order. Defaults to PyPI.   | List of strings | optional |  `[]`  |


