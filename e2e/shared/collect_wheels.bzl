"""Macro to collect built wheels across multiple target platforms."""

load("@bazel_lib//lib:transitions.bzl", "platform_transition_filegroup")

def collect_wheels(name, wheels, platforms, **kwargs):
    """Builds wheels for each target platform and collects them into a single target.

    Creates a platform_transition_filegroup per platform that builds the given
    wheel targets in that platform's configuration, then aggregates all results
    into a single filegroup.

    Example usage:

        load("//shared:collect_wheels.bzl", "collect_wheels")

        collect_wheels(
            name = "all_wheels",
            wheels = [
                "@uv//_wheel:numpy",
                "@uv//_wheel:pandas",
            ],
            platforms = [
                "@llvm//platforms:linux_x86_64",
                "@llvm//platforms:macos_aarch64",
            ],
        )

    Then:
        bazel build //:all_wheels
        bazel cquery 'deps(//:all_wheels, 1)' --output=files

    Args:
        name: Name of the resulting filegroup target.
        wheels: List of wheel labels (e.g., ["@uv//_wheel:numpy"]).
        platforms: List of platform labels to build for.
        **kwargs: Additional arguments forwarded to the filegroup
            (e.g., visibility).
    """
    all_srcs = []

    for platform in platforms:
        # Derive a short suffix from the platform label for target naming.
        # e.g., "@llvm//platforms:linux_x86_64" -> "linux_x86_64"
        suffix = platform.split(":")[-1]
        transition_name = "_{}_{}".format(name, suffix)

        platform_transition_filegroup(
            name = transition_name,
            srcs = wheels,
            target_platform = platform,
        )
        all_srcs.append(":{}".format(transition_name))

    native.filegroup(
        name = name,
        srcs = all_srcs,
        **kwargs
    )
