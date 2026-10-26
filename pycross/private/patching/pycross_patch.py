"""Apply pycross patch files with the vendored rules_python unified-diff engine.

`post_install_patches` and `pre_build_patches` used to go through `patch_ng` at
strip level 0. `patch_ng` quietly dropped git-style `a/` and `b/` prefixes when
the literal path didn't exist, so nearly every real pycross patch is written in
`git diff` format and relies on that. The vendored engine
(`pycross/private/third_party/rules_python_patch`) is strict and treats the
strip level literally, like GNU `patch -pN`. This wrapper keeps pycross's
contract: at strip 0, a patch whose file headers are all git-style pairs
(`a/...` and `b/...`, or `/dev/null` on one side) is applied with strip 1.

It also turns engine failures into the `SystemExit` messages the pycross tools
have always produced.
"""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Iterator
from typing import List
from typing import Optional
from typing import Set
from typing import Tuple
from typing import Union

from unified_patch import apply_unified_patch

PathLike = Union[str, os.PathLike]

# Same shape as the engine's hunk header regex; we only need the counts.
_HUNK_HEADER_RE = re.compile(rb"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")


class PatchError(Exception):
    """A patch file could not be applied."""


class PatchParseError(PatchError):
    """A patch file has no unified diff file headers, so nothing could be parsed from it."""


def _header_path(raw: bytes) -> bytes:
    # Matches the engine: the path ends at the first tab (timestamps follow).
    return raw.split(b"\t", 1)[0].strip()


def _iter_file_headers(lines: List[bytes]) -> Iterator[Tuple[bytes, bytes]]:
    """Yield `(old_path, new_path)` for each `--- `/`+++ ` file header pair.

    Hunk bodies are skipped by their line counts, the same way the engine
    reads them, so a removed line such as `-- foo` followed by an added line
    `++ bar` isn't mistaken for a file header. A malformed hunk ends the body
    early; the engine reports the real error.
    """
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.startswith(b"--- ") and i + 1 < n and lines[i + 1].startswith(b"+++ "):
            yield _header_path(line[4:]), _header_path(lines[i + 1][4:])
            i += 2
            continue
        m = _HUNK_HEADER_RE.match(line)
        i += 1
        if not m:
            continue
        rem_old = int(m.group(1)) if m.group(1) is not None else 1
        rem_new = int(m.group(2)) if m.group(2) is not None else 1
        while i < n and (rem_old > 0 or rem_new > 0):
            hline = lines[i]
            if hline.startswith(b"\\"):
                i += 1
                continue
            if hline in (b"\n", b"\r\n") and rem_old > 0 and rem_new > 0:
                op = b" "
            else:
                op = hline[:1]
            if op == b" ":
                rem_old -= 1
                rem_new -= 1
            elif op == b"-":
                rem_old -= 1
            elif op == b"+":
                rem_new -= 1
            else:
                break
            i += 1


def _is_git_style_pair(old: bytes, new: bytes) -> bool:
    if old == b"/dev/null" and new == b"/dev/null":
        return False
    old_ok = old == b"/dev/null" or old.startswith(b"a/")
    new_ok = new == b"/dev/null" or new.startswith(b"b/")
    return old_ok and new_ok


def _git_style_strip(headers: List[Tuple[bytes, bytes]], strip: int) -> int:
    if strip == 0 and headers and all(_is_git_style_pair(old, new) for old, new in headers):
        return 1
    return strip


def effective_strip(patch_bytes: bytes, strip: int = 0) -> int:
    """Return the strip level pycross applies `patch_bytes` with.

    At `strip == 0`, a patch whose file headers are all git-style pairs
    (`a/` + `b/`, or `/dev/null` on one side) gets strip 1. Any other
    strip level, a patch with at least one plain header, or a patch with no
    headers at all is used as given.
    """
    return _git_style_strip(list(_iter_file_headers(patch_bytes.splitlines(keepends=True))), strip)


def apply_patch(root: PathLike, patch: PathLike, strip: int = 0) -> Set[str]:
    """Apply one patch file under `root` and return the root-relative paths it touched.

    Raises:
        PatchParseError: the patch has no `--- `/`+++ ` file headers (the
            message carries the engine's reason, e.g. an unsupported rename).
        PatchError: the patch is malformed, doesn't apply exactly, or is unsafe.
    """
    patch_path = Path(patch)
    try:
        patch_bytes = patch_path.read_bytes()
    except OSError as e:
        raise PatchError(str(e)) from e
    headers = list(_iter_file_headers(patch_bytes.splitlines(keepends=True)))
    try:
        return apply_unified_patch(Path(root), patch_path, strip=_git_style_strip(headers, strip))
    except (ValueError, OSError) as e:
        if not headers:
            raise PatchParseError(str(e)) from e
        raise PatchError(str(e)) from e


def apply_patch_or_exit(
    root: PathLike,
    patch: PathLike,
    strip: int = 0,
    display_name: Optional[str] = None,
) -> Set[str]:
    """Like `apply_patch`, but exits with pycross's usual error message on failure."""
    name = display_name if display_name is not None else str(patch)
    try:
        return apply_patch(root, patch, strip)
    except PatchParseError as e:
        raise SystemExit(f"error: failed to parse patch file: {name}: {e}") from e
    except PatchError as e:
        raise SystemExit(f"error: failed to apply patch file: {name}: {e}") from e
