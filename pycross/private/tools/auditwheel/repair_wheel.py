import argparse
import os
import pathlib
from typing import Any

from absl import app
from absl.flags import argparse_flags

from pycross.private.tools.auditwheel import monkeypatch


def main(args: Any) -> None:
    monkeypatch.apply_auditwheel_patches(args.target_machine)

    from auditwheel.wheel_abi import analyze_wheel_abi
    winfo = analyze_wheel_abi(args.wheel_file)

    ap_parser = argparse.ArgumentParser()
    ap_sub_parsers = ap_parser.add_subparsers(metavar="command", dest="cmd")

    from auditwheel import main_repair
    main_repair.configure_parser(ap_sub_parsers)

    ap_args = ap_parser.parse_args([
        "repair",
        args.wheel_file,
        "--only-plat",
        "--plat",
        winfo.overall_tag,
        "--wheel-dir",
        args.output_dir,
    ])
    ap_args.verbose = args.verbose

    ap_args.func(ap_args, ap_parser)


def parse_flags(argv) -> Any:
    parser = argparse_flags.ArgumentParser(
        description="Repair linux wheel."
    )

    parser.add_argument(
        "--wheel-file",
        help="Path to wheel file.",
        required=True,
    )

    parser.add_argument(
        "--target-machine",
        help="The machine name for the target platform (x86_64, aarch64, ...)",
        required=True,
    )

    parser.add_argument(
        "--output-dir",
        help="Path to directory where new wheel is written.",
        required=True,
    )

    parser.add_argument(
        "--verbose",
        action="count",
        dest="verbose",
        default=0,
        help="Give more output. Option is additive",
    )

    return parser.parse_args(argv[1:])


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    app.run(main, flags_parser=parse_flags)
