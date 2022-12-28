import os
import pathlib
from typing import Any

from absl import app
from absl.flags import argparse_flags


def init_policies_for_machine(machine: str):
    import platform
    old_machine_fn = platform.machine
    try:
        platform.machine = lambda: machine
        import auditwheel.policy
    finally:
        platform.machine = old_machine_fn


def main(args: Any) -> None:
    init_policies_for_machine("aarch64")

    from auditwheel import wheel_abi

    winfo = wheel_abi.analyze_wheel_abi(str(args.wheel_file))
    print(winfo)


def parse_flags(argv) -> Any:
    parser = argparse_flags.ArgumentParser(
        description="Repair linux wheel."
    )

    parser.add_argument(
        "--wheel-file",
        type=pathlib.Path,
        help="Path to wheel file.",
        required=True,
    )

    return parser.parse_args(argv[1:])


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    app.run(main, flags_parser=parse_flags)
