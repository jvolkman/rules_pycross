<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The lock_repos extension.

<a id="lock_file"></a>

## lock_file

<pre>
lock_file = use_extension("@rules_pycross//pycross/extensions:lock_file.bzl", "lock_file")
lock_file.instantiate(<a href="#lock_file.instantiate-name">name</a>, <a href="#lock_file.instantiate-lock_file">lock_file</a>)
</pre>


**TAG CLASSES**

<a id="lock_file.instantiate"></a>

### instantiate

Create a repo given the Pycross-generated lock file.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_file.instantiate-name"></a>name |  The repo name.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lock_file.instantiate-lock_file"></a>lock_file |  The lock file created by pycross_lock_file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


