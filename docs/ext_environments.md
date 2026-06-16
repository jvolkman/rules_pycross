<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The environments extension.

<a id="environments"></a>

## environments

<pre>
environments = use_extension("@rules_pycross//pycross/extensions:environments.bzl", "environments")
environments.create_for_python_toolchains(<a href="#environments.create_for_python_toolchains-name">name</a>, <a href="#environments.create_for_python_toolchains-glibc_version">glibc_version</a>, <a href="#environments.create_for_python_toolchains-macos_version">macos_version</a>, <a href="#environments.create_for_python_toolchains-musl_version">musl_version</a>,
                                          <a href="#environments.create_for_python_toolchains-platforms">platforms</a>, <a href="#environments.create_for_python_toolchains-python_versions">python_versions</a>)
environments.create(<a href="#environments.create-name">name</a>, <a href="#environments.create-glibc_version">glibc_version</a>, <a href="#environments.create-macos_version">macos_version</a>, <a href="#environments.create-musl_version">musl_version</a>)
environments.python(<a href="#environments.python-envs">envs</a>, <a href="#environments.python-version">version</a>)
environments.platform(<a href="#environments.platform-envs">envs</a>, <a href="#environments.platform-glibc_version">glibc_version</a>, <a href="#environments.platform-macos_version">macos_version</a>, <a href="#environments.platform-musl_version">musl_version</a>, <a href="#environments.platform-target">target</a>)
</pre>

Create target environments.


**TAG CLASSES**

<a id="environments.create_for_python_toolchains"></a>

### create_for_python_toolchains

Create an environments repo using Python versions discovered from rules_python.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="environments.create_for_python_toolchains-name"></a>name |  The environments repo name.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | optional |  `"pycross_environments"`  |
| <a id="environments.create_for_python_toolchains-glibc_version"></a>glibc_version |  Default glibc version for Linux platforms.   | String | optional |  `""`  |
| <a id="environments.create_for_python_toolchains-macos_version"></a>macos_version |  Default macOS version for Darwin platforms.   | String | optional |  `""`  |
| <a id="environments.create_for_python_toolchains-musl_version"></a>musl_version |  Default musl version for Linux musl platforms.   | String | optional |  `""`  |
| <a id="environments.create_for_python_toolchains-platforms"></a>platforms |  The list of Python platforms to support. Mutually exclusive with platform() tags for this environments repo. By default all supported platforms are included.   | List of strings | optional |  `[]`  |
| <a id="environments.create_for_python_toolchains-python_versions"></a>python_versions |  The list of Python versions to support. By default all registered versions are supported.   | List of strings | optional |  `[]`  |

<a id="environments.create"></a>

### create

Create an environments repo with explicit Python versions (BYOT).

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="environments.create-name"></a>name |  The environments repo name.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="environments.create-glibc_version"></a>glibc_version |  Default glibc version for Linux platforms.   | String | optional |  `""`  |
| <a id="environments.create-macos_version"></a>macos_version |  Default macOS version for Darwin platforms.   | String | optional |  `""`  |
| <a id="environments.create-musl_version"></a>musl_version |  Default musl version for Linux musl platforms.   | String | optional |  `""`  |

<a id="environments.python"></a>

### python

Declare a Python version for a create() environments repo.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="environments.python-envs"></a>envs |  Name of the environments repo. Defaults to 'pycross_environments'.   | String | optional |  `"pycross_environments"`  |
| <a id="environments.python-version"></a>version |  Python version (e.g. '3.11.6' or '3.12').   | String | required |  |

<a id="environments.platform"></a>

### platform

Declare a target platform with optional per-platform version overrides.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="environments.platform-envs"></a>envs |  Name of the environments repo. Defaults to 'pycross_environments'.   | String | optional |  `"pycross_environments"`  |
| <a id="environments.platform-glibc_version"></a>glibc_version |  Override glibc version for this platform.   | String | optional |  `""`  |
| <a id="environments.platform-macos_version"></a>macos_version |  Override macOS version for this platform.   | String | optional |  `""`  |
| <a id="environments.platform-musl_version"></a>musl_version |  Override musl version for this platform.   | String | optional |  `""`  |
| <a id="environments.platform-target"></a>target |  Platform triple (e.g. 'x86_64-unknown-linux-gnu').   | String | required |  |


