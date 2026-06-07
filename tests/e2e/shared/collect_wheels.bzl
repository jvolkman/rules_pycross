"""Macro to collect built wheels across multiple target platforms."""

load("@bazel_lib//lib:run_binary.bzl", "run_binary")
load("@bazel_lib//lib:transitions.bzl", "platform_transition_filegroup")

def collect_wheels(name, wheels, platforms, **kwargs):
    """Builds wheels for each target platform and collects them into a single target.

    Args:
        name: Name of the resulting target.
        wheels: List of wheel labels (e.g., ["@uv//numpy:whl"]).
        platforms: List of platform labels to build for.
        **kwargs: Additional arguments forwarded to the filegroup.
    """
    all_srcs = []

    native.filegroup(
        name = name + "_wheels_filegroup",
        srcs = wheels,
    )

    for platform in platforms:
        suffix = platform.split(":")[-1]
        transition_name = "_{}_{}".format(name, suffix)

        platform_transition_filegroup(
            name = transition_name,
            srcs = [name + "_wheels_filegroup"],
            target_platform = platform,
        )
        all_srcs.append(":{}".format(transition_name))

    native.filegroup(
        name = name + "_all_transitions",
        srcs = all_srcs,
    )

    run_binary(
        name = name,
        tool = "//shared:collect_wheels_tool",
        args = [
            "--out-dir",
            "$(@D)",
            "$(execpaths :" + name + "_all_transitions)",
        ],
        srcs = [name + "_all_transitions"],
        out_dirs = [name],
        **kwargs
    )
