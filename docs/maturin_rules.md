<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API for rules_pycross_backend_maturin.

<a id="pycross_generate_cargo_lock"></a>

## pycross_generate_cargo_lock

<pre>
load("@rules_pycross_backend_maturin//:defs.bzl", "pycross_generate_cargo_lock")

pycross_generate_cargo_lock(<a href="#pycross_generate_cargo_lock-name">name</a>, <a href="#pycross_generate_cargo_lock-output">output</a>, <a href="#pycross_generate_cargo_lock-sdist">sdist</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pycross_generate_cargo_lock-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="pycross_generate_cargo_lock-output"></a>output |  -   | String | optional |  `""`  |
| <a id="pycross_generate_cargo_lock-sdist"></a>sdist |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


