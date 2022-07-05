# Example

This sub-workspace provides an example of the `pycross` rules. It should work out-of-the-box on Debian-like and MacOS
platforms (Windows should also work, but I haven't defined a Windows `pycross_target_environment` nor have I tested
on Windows yet).

Try running IPython: `bazel run //tools:ipython`

To add dependencies:
1. install [Poetry](https://github.com/python-poetry/poetry) - it's not currently a dependency
2. run `poetry add <new-package>`, where `<new-package>` is the name of the thing you want to add
3. run `bazel run :update_example_lock` to update the `.bzl` lock file

Following that, the new package should be available at `//deps:<new_package>`
