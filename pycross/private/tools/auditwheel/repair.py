import argparse
import logging
import os
from pathlib import Path
from typing import List

from bazel_tools.tools.python.runfiles import runfiles

from pycross.private.tools.auditwheel import monkeypatch

log = logging.getLogger(__name__)


def add_patchelf_to_path():
    r = runfiles.Create()
    patchelf_location = r.Rlocation("rules_pycross_third_party_patchelf/patchelf")
    patchelf_location = Path(patchelf_location)
    path_parts = [str(patchelf_location.parent)]
    if "PATH" in os.environ:
        path_parts.append(os.environ["PATH"])
    os.environ["PATH"] = os.pathsep.join(path_parts)


def repair(wheel_file: Path, output_dir: Path, lib_path: List[Path], target_machine: str, verbosity: int = 0) -> None:
    monkeypatch.apply_auditwheel_patches(target_machine, lib_path)
    add_patchelf_to_path()

    from auditwheel.wheel_abi import analyze_wheel_abi, NonPlatformWheel
    try:
        winfo = analyze_wheel_abi(str(wheel_file))
    except NonPlatformWheel:
        log.info(NonPlatformWheel.LOG_MESSAGE)
        return

    show_parser = argparse.ArgumentParser()
    show_sub_parsers = show_parser.add_subparsers(metavar="command", dest="cmd")

    repair_parser = argparse.ArgumentParser()
    repair_sub_parsers = repair_parser.add_subparsers(metavar="command", dest="cmd")

    from auditwheel import main_repair, main_show
    main_show.configure_parser(show_sub_parsers)
    main_repair.configure_parser(repair_sub_parsers)

    show_args = show_parser.parse_args(["show", str(wheel_file)])
    show_args.verbose = verbosity
    show_args.func(show_args, show_parser)

    repair_args = repair_parser.parse_args([
        "repair",
        str(wheel_file),
        "--only-plat",
        "--plat",
        winfo.sym_tag,
        "--wheel-dir",
        str(output_dir),
    ])
    repair_args.verbose = verbosity
    repair_args.func(repair_args, repair_parser)
