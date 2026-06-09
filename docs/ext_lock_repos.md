<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The lock_repos extension.

<a id="lock_repos"></a>

## lock_repos

<pre>
lock_repos = use_extension("@rules_pycross//pycross/extensions:lock_repos.bzl", "lock_repos")
lock_repos.create(<a href="#lock_repos.create-pypi_index">pypi_index</a>)
</pre>


**TAG CLASSES**

<a id="lock_repos.create"></a>

### create

Create declared Pycross repos.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lock_repos.create-pypi_index"></a>pypi_index |  The PyPI-compatible index to use (must support the JSON API).   | String | optional |  `""`  |


