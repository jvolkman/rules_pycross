"""
A tool that takes an input PEP 425 tag and an optional list of environment
marker overrides and outputs the result of guessed markers with overrides.
"""

import argparse
from packaging import tags

from . import env_markers


def main():
    parser = argparse.ArgumentParser(
        description = "Generate target python information."
    )

    parser.add_argument(
        "--platform-tag",
        type=str,
        required=True,
        help="The PEP 425 tag that describes the target platform.",
    )

    parser.add_argument(
        "--marker-override",
        type=str,
        nargs="*",
        help="Environment marker overrides in the format `marker=override`."
    )

    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="The output file.",
    )

    args = parser.parse_args()
    platform_tag = args.platform_tag
    output = args.output

    overrides = {}
    for override_str in args.marker_override:
        marker, val = override_str.split("=", maxsplit=1)
        overrides[marker] = val

    guessed_markers = env_markers.guess_environment_markers()

    project_file = args.project_file
    lock_file = args.lock_file

    if not os.path.isfile(project_file):
        parser.error(f"Missing project file: {project_file}")

    with tempfile.TemporaryDirectory(prefix="locker") as tempdir:
        temp_project_file = os.path.join(tempdir, "pyproject.toml")
        temp_lock_file = os.path.join(tempdir, "pdm.lock")

        shutil.copyfile(project_file, temp_project_file)
        if os.path.isfile(lock_file):
            shutil.copyfile(lock_file, temp_lock_file)

        args = [sys.executable, "-m", "pdm", "lock"]
        subprocess.run(args, check=True, cwd=tempdir)

        shutil.copyfile(temp_lock_file, lock_file)


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
