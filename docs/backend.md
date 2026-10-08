<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API for pycross backend module authors.

This module provides the building blocks needed to implement custom
wheel-building rules and override extensions that integrate with
rules_pycross.

<a id="PycrossExtractedWheelInfo"></a>

## PycrossExtractedWheelInfo

<pre>
load("@rules_pycross//pycross:backend.bzl", "PycrossExtractedWheelInfo")

PycrossExtractedWheelInfo(<a href="#PycrossExtractedWheelInfo-site_packages">site_packages</a>)
</pre>

Information about an extracted (installed) Python wheel.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="PycrossExtractedWheelInfo-site_packages"></a>site_packages |  File (TreeArtifact): The unzipped site-packages directory containing the wheel's installed files.    |


<a id="PycrossPackageInfo"></a>

## PycrossPackageInfo

<pre>
load("@rules_pycross//pycross:backend.bzl", "PycrossPackageInfo")

PycrossPackageInfo(<a href="#PycrossPackageInfo-package_name">package_name</a>, <a href="#PycrossPackageInfo-package_version">package_version</a>, <a href="#PycrossPackageInfo-site_paths">site_paths</a>, <a href="#PycrossPackageInfo-bin_paths">bin_paths</a>, <a href="#PycrossPackageInfo-data_paths">data_paths</a>, <a href="#PycrossPackageInfo-include_paths">include_paths</a>)
</pre>

Information about a Python package (e.g. from a lockfile).

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="PycrossPackageInfo-package_name"></a>package_name |  string: The normalized package name.    |
| <a id="PycrossPackageInfo-package_version"></a>package_version |  string: The package version.    |
| <a id="PycrossPackageInfo-site_paths"></a>site_paths |  list of strings: The site-packages paths provided by this package.    |
| <a id="PycrossPackageInfo-bin_paths"></a>bin_paths |  list of strings: The bin paths provided by this package.    |
| <a id="PycrossPackageInfo-data_paths"></a>data_paths |  list of strings: The data paths provided by this package.    |
| <a id="PycrossPackageInfo-include_paths"></a>include_paths |  list of strings: The include paths provided by this package.    |


<a id="defer_build_error"></a>

## defer_build_error

<pre>
load("@rules_pycross//pycross:backend.bzl", "defer_build_error")

defer_build_error(<a href="#defer_build_error-ctx">ctx</a>, <a href="#defer_build_error-errors">errors</a>)
</pre>

Reports sdist build configuration errors at execution time.

Build rules call this instead of `fail()` when they detect, during analysis,
that a build cannot succeed (e.g. missing build-system packages or tools).
Returning providers backed by a failing action, rather than failing
analysis, keeps analysis-only consumers (aspects, `cquery`) working for
packages that are never actually built, while any real build of the package
still fails with the same message. This mirrors Bazel's validation-action
pattern.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="defer_build_error-ctx"></a>ctx |  The build rule context (must include `COMMON_BUILD_ATTRS`).   |  none |
| <a id="defer_build_error-errors"></a>errors |  list[str], the error messages. Must be non-empty.   |  none |

**RETURNS**

list of providers for the build rule to return.


<a id="encode_build_system_attrs"></a>

## encode_build_system_attrs

<pre>
load("@rules_pycross//pycross:backend.bzl", "encode_build_system_attrs")

encode_build_system_attrs(<a href="#encode_build_system_attrs-tag">tag</a>)
</pre>

Encode BUILD_SYSTEM_ATTRS from a tag into a backend_attrs dict.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="encode_build_system_attrs-tag"></a>tag |  A module tag with optional copts, linkopts, native_deps, config_settings, and tool_deps attributes.   |  none |

**RETURNS**

A dict of JSON-encoded backend attribute values.


<a id="extract_cc_layer"></a>

## extract_cc_layer

<pre>
load("@rules_pycross//pycross:backend.bzl", "extract_cc_layer")

extract_cc_layer(<a href="#extract_cc_layer-ctx">ctx</a>, <a href="#extract_cc_layer-native_deps">native_deps</a>, <a href="#extract_cc_layer-copts">copts</a>, <a href="#extract_cc_layer-linkopts">linkopts</a>, <a href="#extract_cc_layer-meson_properties">meson_properties</a>)
</pre>

Extracts CC toolchain info, headers, and libraries from native deps.

Requires the calling rule to declare:
    - fragments = ["cpp"]
    - toolchains = ["@bazel_tools//tools/cpp:toolchain_type"]
    - _cc_toolchain attr
    - _os_* and _cpu_* constraint attrs


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="extract_cc_layer-ctx"></a>ctx |  The rule context.   |  none |
| <a id="extract_cc_layer-native_deps"></a>native_deps |  list[Target], targets providing CcInfo.   |  none |
| <a id="extract_cc_layer-copts"></a>copts |  list[str], extra compiler flags.   |  none |
| <a id="extract_cc_layer-linkopts"></a>linkopts |  list[str], extra linker flags.   |  none |
| <a id="extract_cc_layer-meson_properties"></a>meson_properties |  dict, meson cross-file properties.   |  `{}` |

**RETURNS**

struct(
      config_json = File,      # the serialized CC config
      transitive_files = depset, # all files needed at build time
      make_vars = dict,        # template variables from deps
  )


<a id="get_resource_set"></a>

## get_resource_set

<pre>
load("@rules_pycross//pycross:backend.bzl", "get_resource_set")

get_resource_set(<a href="#get_resource_set-attr">attr</a>)
</pre>

get the resource set as configured by the settings and attrs

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="get_resource_set-attr"></a>attr |  the ctx.attr associated with the target   |  none |

**RETURNS**

A struct with:
      - resource_set: the resource_set callback, or None if bazel default
      - cpu: cpu_cores, or 0 if bazel default
      - mem: mem in MB, or 0 if bazel default
      - allow_cpu_overcommit: True if the build tool may use more
        parallelism than the scheduler reservation (False for sizes
        like "serial" that must enforce an exact -j value)
      - parallelism: The final integer number of parallel jobs to run


<a id="get_unzipped_wheel"></a>

## get_unzipped_wheel

<pre>
load("@rules_pycross//pycross:backend.bzl", "get_unzipped_wheel")

get_unzipped_wheel(<a href="#get_unzipped_wheel-target">target</a>)
</pre>

Extracts the site_packages TreeArtifact from a target.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="get_unzipped_wheel-target"></a>target |  Target, must provide PycrossExtractedWheelInfo.   |  none |

**RETURNS**

File (TreeArtifact): the installed site-packages directory.


<a id="get_wheel"></a>

## get_wheel

<pre>
load("@rules_pycross//pycross:backend.bzl", "get_wheel")

get_wheel(<a href="#get_wheel-target">target</a>)
</pre>

Extracts the wheel output from a target.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="get_wheel-target"></a>target |  Target, a wheel build target.   |  none |

**RETURNS**

File: the wheel file or TreeArtifact directory containing a .whl file.


<a id="group_tool_deps"></a>

## group_tool_deps

<pre>
load("@rules_pycross//pycross:backend.bzl", "group_tool_deps")

group_tool_deps(<a href="#group_tool_deps-tool_deps_list">tool_deps_list</a>)
</pre>

Groups tool_deps by PycrossPackageInfo.package_name.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="group_tool_deps-tool_deps_list"></a>tool_deps_list |  list[Target], targets that may carry PycrossPackageInfo.   |  none |

**RETURNS**

dict[str, list[Target]]: targets keyed by normalized package name.


<a id="make_override_extension"></a>

## make_override_extension

<pre>
load("@rules_pycross//pycross:backend.bzl", "make_override_extension")

make_override_extension(<a href="#make_override_extension-backend_name">backend_name</a>, <a href="#make_override_extension-build_backend">build_backend</a>, <a href="#make_override_extension-override_attrs">override_attrs</a>)
</pre>

Create a module extension for a build-system backend.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="make_override_extension-backend_name"></a>backend_name |  Short name (e.g. "setuptools"). Used to name the generated overrides repo as `<backend_name>_overrides`.   |  none |
| <a id="make_override_extension-build_backend"></a>build_backend |  The build backend identifier string stored in the override JSON (e.g. "setuptools_build").   |  none |
| <a id="make_override_extension-override_attrs"></a>override_attrs |  The tag attribute dict for the `override` tag class.   |  none |

**RETURNS**

A `module_extension` value.


<a id="register_bin_extract_action"></a>

## register_bin_extract_action

<pre>
load("@rules_pycross//pycross:backend.bzl", "register_bin_extract_action")

register_bin_extract_action(<a href="#register_bin_extract_action-ctx">ctx</a>, <a href="#register_bin_extract_action-wheel_dir">wheel_dir</a>, <a href="#register_bin_extract_action-binary_name">binary_name</a>)
</pre>

Extracts a native binary from a wheel's bin/ directory.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="register_bin_extract_action-ctx"></a>ctx |  The rule context.   |  none |
| <a id="register_bin_extract_action-wheel_dir"></a>wheel_dir |  File, the tree artifact of the unzipped wheel.   |  none |
| <a id="register_bin_extract_action-binary_name"></a>binary_name |  str, name of the binary.   |  none |

**RETURNS**

struct(
      name = str,
      file = File,
  )


<a id="register_pep517_action"></a>

## register_pep517_action

<pre>
load("@rules_pycross//pycross:backend.bzl", "register_pep517_action")

register_pep517_action(<a href="#register_pep517_action-ctx">ctx</a>, <a href="#register_pep517_action-builder">builder</a>, <a href="#register_pep517_action-additional_build_deps">additional_build_deps</a>, <a href="#register_pep517_action-layers">layers</a>, <a href="#register_pep517_action-tool_executables">tool_executables</a>, <a href="#register_pep517_action-extra_files">extra_files</a>,
                       <a href="#register_pep517_action-extra_inputs">extra_inputs</a>, <a href="#register_pep517_action-env">env</a>, <a href="#register_pep517_action-resource_set">resource_set</a>)
</pre>

Registers the PEP 517 wheel build action.

Common attributes (sdist, deps, build_deps, site_hooks, pre_build_patches,
config_settings, pkg_config_files) are extracted directly from ctx.attr/ctx.file/ctx.files.
This avoids repetitive plumbing in each build rule implementation.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="register_pep517_action-ctx"></a>ctx |  The rule context.   |  none |
| <a id="register_pep517_action-builder"></a>builder |  Target, the builder executable.   |  none |
| <a id="register_pep517_action-additional_build_deps"></a>additional_build_deps |  list[Target], extra build-time deps to merge with ctx.attr.build_deps.   |  `[]` |
| <a id="register_pep517_action-layers"></a>layers |  list[struct], CC/Rust environment from extract_*_layer().   |  `[]` |
| <a id="register_pep517_action-tool_executables"></a>tool_executables |  list[struct(name, file)], executables to place on PATH.   |  `[]` |
| <a id="register_pep517_action-extra_files"></a>extra_files |  dict[str, File], files to inject into the sdist directory before building, keyed by their target filename (e.g. "package.json").   |  `{}` |
| <a id="register_pep517_action-extra_inputs"></a>extra_inputs |  list[File], extra inputs to the action.   |  `[]` |
| <a id="register_pep517_action-env"></a>env |  dict[str, str], extra environment variables to pass to the action.   |  `{}` |
| <a id="register_pep517_action-resource_set"></a>resource_set |  function or dict, resource requirements for the action.   |  `None` |

**RETURNS**

struct(
      wheel_dir = File,  # TreeArtifact containing one .whl file
  )


<a id="register_repair_action"></a>

## register_repair_action

<pre>
load("@rules_pycross//pycross:backend.bzl", "register_repair_action")

register_repair_action(<a href="#register_repair_action-ctx">ctx</a>, <a href="#register_repair_action-input_wheel_dir">input_wheel_dir</a>, <a href="#register_repair_action-repair_tool">repair_tool</a>, <a href="#register_repair_action-native_deps">native_deps</a>, <a href="#register_repair_action-target_environment">target_environment</a>,
                       <a href="#register_repair_action-repair_exclude_globs">repair_exclude_globs</a>, <a href="#register_repair_action-repair_deps">repair_deps</a>, <a href="#register_repair_action-resource_set">resource_set</a>)
</pre>

Registers the repairwheel action to bundle native shared libs.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="register_repair_action-ctx"></a>ctx |  The rule context.   |  none |
| <a id="register_repair_action-input_wheel_dir"></a>input_wheel_dir |  File, the input wheel directory TreeArtifact.   |  none |
| <a id="register_repair_action-repair_tool"></a>repair_tool |  Target, the repair_wheel executable.   |  none |
| <a id="register_repair_action-native_deps"></a>native_deps |  list[Target], CcInfo deps whose shared libs to bundle.   |  `[]` |
| <a id="register_repair_action-target_environment"></a>target_environment |  File (optional), the target environment JSON.   |  `None` |
| <a id="register_repair_action-repair_exclude_globs"></a>repair_exclude_globs |  list[str], shared library globs to leave unbundled.   |  `[]` |
| <a id="register_repair_action-repair_deps"></a>repair_deps |  list[Target], optional PyInfo targets (e.g. user-provided repairwheel) whose site-packages are prepended to PYTHONPATH, shadowing the bundled version.   |  `[]` |
| <a id="register_repair_action-resource_set"></a>resource_set |  function or dict, resource requirements for the action.   |  `None` |

**RETURNS**

struct(
      wheel_dir = File,      # tree artifact of repaired wheel contents
  )


<a id="resolve_path_tools"></a>

## resolve_path_tools

<pre>
load("@rules_pycross//pycross:backend.bzl", "resolve_path_tools")

resolve_path_tools(<a href="#resolve_path_tools-ctx">ctx</a>)
</pre>

Resolve path_tools attr into a list of tool executable structs.

Each entry in ``ctx.attr.path_tools`` is either:
- A ``pycross_path_tool`` target (carries ``PycrossPathToolInfo``) — uses
  the custom name from the provider.
- A plain executable target — uses the executable's basename.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="resolve_path_tools-ctx"></a>ctx |  Rule context with a ``path_tools`` label_list attr.   |  none |

**RETURNS**

list[struct]: Each struct has ``name``, ``file``, and ``files_to_run``.


<a id="create_overrides_repo"></a>

## create_overrides_repo

<pre>
load("@rules_pycross//pycross:backend.bzl", "create_overrides_repo")

create_overrides_repo(<a href="#create_overrides_repo-name">name</a>, <a href="#create_overrides_repo-content">content</a>)
</pre>

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="create_overrides_repo-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="create_overrides_repo-content"></a>content |  -   | String | optional |  `""`  |


