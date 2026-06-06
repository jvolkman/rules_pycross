import glob
import re

for filepath in glob.glob("tests/**/*.bzl", recursive=True):
    with open(filepath, "r") as f:
        content = f.read()

    # Disable bzl-visibility for any load from //pycross/private...
    # We find all `load("//pycross/private...` and append `# buildifier: disable=bzl-visibility` to the end of the line
    lines = content.split('\n')
    for i in range(len(lines)):
        if "load(\"//pycross/private" in lines[i] and "buildifier: disable=bzl-visibility" not in lines[i]:
            lines[i] = lines[i] + "  # buildifier: disable=bzl-visibility"
        
        # Replace unused variables
        # We know the specific errors from the log:
        if "actions = env.expect.action" in lines[i] and filepath.endswith("setuptools_build_test.bzl"):
            lines[i] = lines[i].replace("actions = ", "_actions = ")
        
        if "target = env.expect.that_target" in lines[i] and filepath.endswith("test_override_helpers.bzl"):
            lines[i] = lines[i].replace("target = ", "_target = ")

        if "target = env.expect.that_target" in lines[i] and filepath.endswith("test_common_attrs.bzl"):
            lines[i] = lines[i].replace("target = ", "_target = ")

        if "target = env.expect.that_target" in lines[i] and filepath.endswith("test_resolved_lock_renderer.bzl"):
            lines[i] = lines[i].replace("target = ", "_target = ")

        if "ctx = env.expect.that_target" in lines[i] and filepath.endswith("transitions_test.bzl"):
            lines[i] = lines[i].replace("ctx = ", "_ctx = ")

        if "action = env.expect.action" in lines[i] and filepath.endswith("wheel_transform_test.bzl"):
            lines[i] = lines[i].replace("action = ", "_action = ")

    new_content = '\n'.join(lines)
    if new_content != content:
        with open(filepath, "w") as f:
            f.write(new_content)
