To run this example (on either Linux or macOS):
* Install bazelisk somehow: `brew install bazelisk` or just [download](https://github.com/bazelbuild/bazelisk/releases) it. Make sure it's aliased as `bazel`
* Clone this repo and check out the `dev/external` branch.
* Change directory to `examples/external_linking`
* Build a linux wheel: `bazel build //deps/psycopg2 --platforms @zig_sdk//platform:linux_x86_64`

The output file will be `bazel-bin/deps/psycopg2/psycopg2/psycopg2-2.9.5.whl` which isn't a valid wheel name. This is due to Bazel needing to know the name of the file that will be output before the build action is invoked, and how wheel names are somewhat complicated to pre-determine.

The actual wheel filename can be found in `bazel-bin/deps/psycopg2/psycopg2/psycopg2-2.9.5.whl.name`:
```
cat bazel-bin/deps/psycopg2/psycopg2/psycopg2-2.9.5.whl.name
psycopg2-2.9.5-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl 
```
