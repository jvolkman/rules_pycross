<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The pycross extension.

<a id="pycross"></a>

## pycross

<pre>
pycross = use_extension("@rules_pycross//pycross/extensions:pycross.bzl", "pycross")
pycross.configure_interpreter(<a href="#pycross.configure_interpreter-python_defs_file">python_defs_file</a>, <a href="#pycross.configure_interpreter-python_interpreter_target">python_interpreter_target</a>)
pycross.configure_toolchains(<a href="#pycross.configure_toolchains-platforms">platforms</a>, <a href="#pycross.configure_toolchains-python_versions">python_versions</a>, <a href="#pycross.configure_toolchains-register_toolchains">register_toolchains</a>)
</pre>

Configure rules_pycross.


**TAG CLASSES**

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
| <a id="pycross.configure_toolchains-platforms"></a>platforms |  The list of Python platforms to support in by default in Pycross builds. See https://github.com/bazelbuild/rules_python/blob/main/python/versions.bzl for the list of supported platforms per Python version. By default all supported platforms for each registered version are supported.   | List of strings | optional |  `[]`  |
| <a id="pycross.configure_toolchains-python_versions"></a>python_versions |  The list of Python versions to support in by default in Pycross builds. These strings will be X.Y or X.Y.Z depending on how versions were registered with rules_python. By default all registered versions are supported.   | List of strings | optional |  `[]`  |
| <a id="pycross.configure_toolchains-register_toolchains"></a>register_toolchains |  Register toolchains for all rules_python-registered interpreters.   | Boolean | optional |  `True`  |


