<!-- Generated with Stardoc: http://skydoc.bazel.build -->

This module implements the language-specific toolchain rule.

<a id="pycross_hermetic_toolchain"></a>

## pycross_hermetic_toolchain

<pre>
load("@rules_pycross//pycross:toolchain.bzl", "pycross_hermetic_toolchain")

pycross_hermetic_toolchain(<a href="#pycross_hermetic_toolchain-name">name</a>, <a href="#pycross_hermetic_toolchain-exec_interpreter">exec_interpreter</a>, <a href="#pycross_hermetic_toolchain-target_interpreter">target_interpreter</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_hermetic_toolchain-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_hermetic_toolchain-exec_interpreter"></a>exec_interpreter |  The execution Python interpreter (can be PyRuntimeInfo or a toolchain alias).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pycross_hermetic_toolchain-target_interpreter"></a>target_interpreter |  The target Python interpreter (PyRuntimeInfo).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="PycrossBuildExecRuntimeInfo"></a>

## PycrossBuildExecRuntimeInfo

<pre>
load("@rules_pycross//pycross:toolchain.bzl", "PycrossBuildExecRuntimeInfo")

PycrossBuildExecRuntimeInfo(<a href="#PycrossBuildExecRuntimeInfo-exec_python_files">exec_python_files</a>, <a href="#PycrossBuildExecRuntimeInfo-exec_python_files_to_run">exec_python_files_to_run</a>, <a href="#PycrossBuildExecRuntimeInfo-exec_python_executable">exec_python_executable</a>,
                            <a href="#PycrossBuildExecRuntimeInfo-target_python_files">target_python_files</a>, <a href="#PycrossBuildExecRuntimeInfo-target_python_files_to_run">target_python_files_to_run</a>, <a href="#PycrossBuildExecRuntimeInfo-target_python_executable">target_python_executable</a>)
</pre>

Extended information about a (exec, target) Python interpreter pair.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="PycrossBuildExecRuntimeInfo-exec_python_files"></a>exec_python_files |  A depset containing all files for the exec interpreter.    |
| <a id="PycrossBuildExecRuntimeInfo-exec_python_files_to_run"></a>exec_python_files_to_run |  Optional FilesToRunProvider for the exec interpreter.    |
| <a id="PycrossBuildExecRuntimeInfo-exec_python_executable"></a>exec_python_executable |  The path to the exec Python interpreter, either absolute or relative to execroot.    |
| <a id="PycrossBuildExecRuntimeInfo-target_python_files"></a>target_python_files |  A depset containing all files for the target interpreter.    |
| <a id="PycrossBuildExecRuntimeInfo-target_python_files_to_run"></a>target_python_files_to_run |  Optional FilesToRunProvider for the target interpreter.    |
| <a id="PycrossBuildExecRuntimeInfo-target_python_executable"></a>target_python_executable |  The path to the target Python interpreter, either absolute or relative to execroot.    |


