<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The backends extension.

<a id="backends"></a>

## backends

<pre>
backends = use_extension("@rules_pycross//pycross/extensions:backends.bzl", "backends")
backends.register(<a href="#backends.register-name">name</a>, <a href="#backends.register-default">default</a>, <a href="#backends.register-override_json">override_json</a>, <a href="#backends.register-package_repo_hook_bzl">package_repo_hook_bzl</a>, <a href="#backends.register-package_repo_hook_fn">package_repo_hook_fn</a>,
                  <a href="#backends.register-pyproject_backends">pyproject_backends</a>, <a href="#backends.register-rule_bzl">rule_bzl</a>, <a href="#backends.register-sdist_hook_bzl">sdist_hook_bzl</a>, <a href="#backends.register-sdist_hook_fn">sdist_hook_fn</a>, <a href="#backends.register-tool_packages">tool_packages</a>)
</pre>

Register build backends for pycross sdist builds.


**TAG CLASSES**

<a id="backends.register"></a>

### register

Register a build backend for pycross sdist builds.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="backends.register-name"></a>name |  Pycross rule name (e.g. 'meson_build').   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="backends.register-default"></a>default |  If True, this backend is used when no pyproject_backends entry matches. Only one backend may be the default. Root module wins if multiple are set.   | Boolean | optional |  `False`  |
| <a id="backends.register-override_json"></a>override_json |  Optional label of a generated JSON file containing overrides for this backend.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="backends.register-package_repo_hook_bzl"></a>package_repo_hook_bzl |  Optional label of a .bzl file providing a hook for thin repo generation.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="backends.register-package_repo_hook_fn"></a>package_repo_hook_fn |  Optional function name in package_repo_hook_bzl. Defaults to '<name>_package_repo_hook' (replacing '_build' suffix).   | String | optional |  `""`  |
| <a id="backends.register-pyproject_backends"></a>pyproject_backends |  pyproject.toml build-system.build-backend values that map to this backend. Entries may include a bracketed list of required build-system.requires package names, e.g. 'setuptools.build_meta[setuptools-rust]'. When multiple backends match the same build-backend value, the one with the most satisfied build_requires wins.   | List of strings | optional |  `[]`  |
| <a id="backends.register-rule_bzl"></a>rule_bzl |  Label of the .bzl file containing the rule, e.g. '@rules_pycross//pycross/private/build/rules:meson_build.bzl'.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="backends.register-sdist_hook_bzl"></a>sdist_hook_bzl |  Optional label of a .bzl file providing a hook for sdist repo execution.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="backends.register-sdist_hook_fn"></a>sdist_hook_fn |  Optional function name in sdist_hook_bzl. Defaults to '<name>_sdist_hook' (replacing '_build' suffix).   | String | optional |  `""`  |
| <a id="backends.register-tool_packages"></a>tool_packages |  PEP 503 normalized PyPI package names of tools this backend needs at build time (e.g. ['meson', 'ninja', 'meson-python']).   | List of strings | optional |  `[]`  |


