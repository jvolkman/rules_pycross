<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The environments extension.

<a id="environments"></a>

## environments

<pre>
environments = use_extension("@rules_pycross//pycross/extensions:environments.bzl", "environments")
environments.create_for_python_toolchains(<a href="#environments.create_for_python_toolchains-name">name</a>, <a href="#environments.create_for_python_toolchains-glibc_version">glibc_version</a>, <a href="#environments.create_for_python_toolchains-macos_version">macos_version</a>, <a href="#environments.create_for_python_toolchains-platforms">platforms</a>,
                                          <a href="#environments.create_for_python_toolchains-python_versions">python_versions</a>)
</pre>

Create target environments.


**TAG CLASSES**

<a id="environments.create_for_python_toolchains"></a>

### create_for_python_toolchains

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="environments.create_for_python_toolchains-name"></a>name |  -   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="environments.create_for_python_toolchains-glibc_version"></a>glibc_version |  The maximum glibc version to accept for Bazel platforms that match the @platforms//os:linux constraint. Must be in the format '2.X', and greater than 2.5. All versions from 2.5 through this version will be supported. For example, if this value is set to 2.15, wheels tagged manylinux_2_5, manylinux_2_6, ..., manylinux_2_15 will be accepted. Defaults to '2.28' if unspecified.   | String | optional |  `""`  |
| <a id="environments.create_for_python_toolchains-macos_version"></a>macos_version |  The maximum macOS version to accept for Bazel platforms that match the @platforms//os:osx constraint. Must be in the format 'X.Y' with X >= 10. All versions from 10.4 through this version will be supported. For example, if this value is set to 12.0, wheels tagged macosx_10_4, macosx_10_5, ..., macosx_11_0, macosx_12_0 will be accepted. Defaults to '12.0' if unspecified.   | String | optional |  `""`  |
| <a id="environments.create_for_python_toolchains-platforms"></a>platforms |  The list of Python platforms to support in by default in Pycross builds. See https://github.com/bazelbuild/rules_python/blob/main/python/versions.bzl for the list of supported platforms per Python version. By default all supported platforms for each registered version are supported.   | List of strings | optional |  `[]`  |
| <a id="environments.create_for_python_toolchains-python_versions"></a>python_versions |  The list of Python versions to support in by default in Pycross builds. These strings will be X.Y or X.Y.Z depending on how versions were registered with rules_python. By default all registered versions are supported.   | List of strings | optional |  `[]`  |


