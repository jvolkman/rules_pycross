<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The lock_import extension.

<a id="pycross"></a>

## pycross

<pre>
pycross = use_extension("@rules_pycross//pycross/extensions:pycross.bzl", "pycross")
pycross.configure_environments(<a href="#pycross.configure_environments-glibc_version">glibc_version</a>, <a href="#pycross.configure_environments-macos_version">macos_version</a>, <a href="#pycross.configure_environments-musl_version">musl_version</a>, <a href="#pycross.configure_environments-platforms">platforms</a>,
                               <a href="#pycross.configure_environments-python_versions">python_versions</a>)
pycross.configure_interpreter(<a href="#pycross.configure_interpreter-python_defs_file">python_defs_file</a>, <a href="#pycross.configure_interpreter-python_interpreter_target">python_interpreter_target</a>)
pycross.configure_toolchains(<a href="#pycross.configure_toolchains-register_toolchains">register_toolchains</a>)
pycross.register_backend(<a href="#pycross.register_backend-name">name</a>, <a href="#pycross.register_backend-default">default</a>, <a href="#pycross.register_backend-pyproject_backends">pyproject_backends</a>, <a href="#pycross.register_backend-rule_bzl">rule_bzl</a>, <a href="#pycross.register_backend-sdist_repo_bzl">sdist_repo_bzl</a>, <a href="#pycross.register_backend-sdist_repo_fn">sdist_repo_fn</a>,
                         <a href="#pycross.register_backend-tool_packages">tool_packages</a>)
</pre>

Configure rules_pycross.


**TAG CLASSES**

<a id="pycross.configure_environments"></a>

### configure_environments

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross.configure_environments-glibc_version"></a>glibc_version |  The maximum glibc version to accept for Bazel platforms that match the @platforms//os:linux constraint. Must be in the format '2.X', and greater than 2.5. All versions from 2.5 through this version will be supported. For example, if this value is set to 2.15, wheels tagged manylinux_2_5, manylinux_2_6, ..., manylinux_2_15 will be accepted. Defaults to '2.28' if unspecified.   | String | optional |  `""`  |
| <a id="pycross.configure_environments-macos_version"></a>macos_version |  The maximum macOS version to accept for Bazel platforms that match the @platforms//os:osx constraint. Must be in the format 'X.Y' with X >= 10. All versions from 10.4 through this version will be supported. For example, if this value is set to 12.0, wheels tagged macosx_10_4, macosx_10_5, ..., macosx_11_0, macosx_12_0 will be accepted. Defaults to '15.0' if unspecified.   | String | optional |  `""`  |
| <a id="pycross.configure_environments-musl_version"></a>musl_version |  The musl version to accept for Bazel platforms that match the @platforms//os:linux constraint when @rules_python//python/config_settings:py_linux_libc is set to 'musl'. Defaults to '1.2' if unspecified.   | String | optional |  `""`  |
| <a id="pycross.configure_environments-platforms"></a>platforms |  The list of Python platforms to support in by default in Pycross builds. See https://github.com/bazelbuild/rules_python/blob/main/python/versions.bzl for the list of supported platforms per Python version. By default all supported platforms for each registered version are supported.   | List of strings | optional |  `[]`  |
| <a id="pycross.configure_environments-python_versions"></a>python_versions |  The list of Python versions to support in by default in Pycross builds. These strings will be X.Y or X.Y.Z depending on how versions were registered with rules_python. By default all registered versions are supported.   | List of strings | optional |  `[]`  |

<a id="pycross.configure_interpreter"></a>

### configure_interpreter

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross.configure_interpreter-python_defs_file"></a>python_defs_file |  A label to a .bzl file that provides py_binary and py_test.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="pycross.configure_interpreter-python_interpreter_target"></a>python_interpreter_target |  The label to a python executable to use for invoking internal tools.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |

<a id="pycross.configure_toolchains"></a>

### configure_toolchains

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross.configure_toolchains-register_toolchains"></a>register_toolchains |  Register toolchains for all rules_python-registered interpreters.   | Boolean | optional |  `True`  |

<a id="pycross.register_backend"></a>

### register_backend

Register a build backend for pycross sdist builds.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross.register_backend-name"></a>name |  Pycross rule name (e.g. 'meson_build').   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross.register_backend-default"></a>default |  If True, this backend is used when no pyproject_backends entry matches. Only one backend may be the default. Root module wins if multiple are set.   | Boolean | optional |  `False`  |
| <a id="pycross.register_backend-pyproject_backends"></a>pyproject_backends |  pyproject.toml build-system.build-backend values that map to this backend (e.g. ['mesonpy', 'mesonbuild']).   | List of strings | optional |  `[]`  |
| <a id="pycross.register_backend-rule_bzl"></a>rule_bzl |  Label of the .bzl file containing the rule, e.g. '@rules_pycross//pycross/private/build/rules:meson_build.bzl'.   | String | required |  |
| <a id="pycross.register_backend-sdist_repo_bzl"></a>sdist_repo_bzl |  Optional label of a .bzl file providing a custom sdist repository_rule for this backend.   | String | optional |  `""`  |
| <a id="pycross.register_backend-sdist_repo_fn"></a>sdist_repo_fn |  Optional function name in sdist_repo_bzl. Defaults to '<name>_sdist_repo' (replacing '_build' suffix).   | String | optional |  `""`  |
| <a id="pycross.register_backend-tool_packages"></a>tool_packages |  PEP 503 normalized PyPI package names of tools this backend needs at build time (e.g. ['meson', 'ninja', 'meson-python']).   | List of strings | optional |  `[]`  |


