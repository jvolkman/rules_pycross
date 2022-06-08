# Example

This example makes use of *very* experimental support for Python cross-compilation.
It's likely to fail in most cases, but can build simple wheels with native code.

For example: if running on MacOS, you can build a Linux wheel like:
```
bazel build //deps:setproctitle --platforms //:linux_x86_64
```
