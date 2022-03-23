import argparse
import os
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description="Generate lockfile for dependencies.")

    parser.add_argument(
        "--project-file",
        type=str,
        required=True,
        help="The path to pyproject.toml",
    )

    parser.add_argument(
        "--lock-file",
        type=str,
        required=True,
        help="The path to pdm.lock",
    )

    args = parser.parse_args()
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
