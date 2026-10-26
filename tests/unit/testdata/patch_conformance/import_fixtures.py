"""Copy the patch conformance fixtures from diffy and go-gitdiff checkouts.

Usage:
    python3 import_fixtures.py <diffy checkout> <go-gitdiff checkout>

File contents are copied unchanged. File names are percent-encoded (see
`encode_name`) because Bazel can't handle some of the upstream names, such as
ones with tabs or quotes. `patch_conformance_test.py` decodes them.
"""

import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# go-gitdiff's bin_fragment_* fixtures test its binary fragment decoder, not file patches.
GO_GITDIFF_SKIP = re.compile(r"^bin_fragment_|\.go$|\.hex$")


def encode_name(name: str) -> str:
    return "".join(c if re.fullmatch(r"[A-Za-z0-9._-]", c) else "".join(f"%{b:02X}" for b in c.encode()) for c in name)


def copy_tree(src: Path, dst: Path) -> None:
    dst.mkdir(parents=True)
    for child in sorted(src.iterdir()):
        target = dst / encode_name(child.name)
        if child.is_dir():
            copy_tree(child, target)
        else:
            shutil.copyfile(child, target)


def main(diffy: Path, go_gitdiff: Path) -> None:
    out = HERE / "diffy"
    shutil.rmtree(out, ignore_errors=True)
    for suite in ("git", "gnu_patch"):
        for case in sorted((diffy / "tests/compat" / suite).iterdir()):
            if case.is_dir():
                copy_tree(case, out / suite / case.name)
    for license_file in ("LICENSE-APACHE", "LICENSE-MIT"):
        shutil.copyfile(diffy / license_file, out / license_file)

    out = HERE / "go_gitdiff"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir()
    for f in sorted((go_gitdiff / "gitdiff/testdata/apply").iterdir()):
        if not GO_GITDIFF_SKIP.search(f.name):
            shutil.copyfile(f, out / encode_name(f.name))
    shutil.copyfile(go_gitdiff / "LICENSE", out / "LICENSE")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
