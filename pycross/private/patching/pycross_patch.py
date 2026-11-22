"""Apply unified diffs for pycross's `post_install_patches` and `pre_build_patches`.

This is a strict, stdlib-only patch applier. It runs in Bazel actions and in
repository rules, where pycross has no virtualenv, so it can't use third-party
packages.

It reads plain unified diffs (`diff -u`) and `git diff` or `git format-patch`
output, including mail headers, signatures and several commits in one file. It
understands git's extended headers: new and deleted files (including empty
ones), mode changes, renames and copies. Quoted git file names are decoded.

Hunks are applied strictly:

- Context lines must match exactly. Only line endings may differ, and there is
  no fuzz.
- If a hunk's context has moved, it is found by searching outward from the line
  the hunk names. Hunks must apply in order.
- A `-U0` hunk that only adds lines inserts them after the line it names.
- `\\ No newline at end of file` is honored.
- Added lines use the line endings of the file being patched.

The patch is rejected if it has binary changes, symlinks or submodules. It is
also rejected if it uses absolute paths, `..`, or a path that resolves outside
the patch root. Creating a file that exists, deleting only part of a file, or
changing a file that doesn't exist all fail.

The whole patch is checked before anything is written, so a patch that fails
leaves the tree as it was.

At strip level 0, a patch whose file names all carry git's `a/` and `b/`
prefixes is applied with strip level 1. pycross has always done this; most
pycross patches come from `git diff`.
"""

from __future__ import annotations

import os
import re
import stat
import tempfile
from dataclasses import dataclass
from dataclasses import field
from pathlib import Path
from typing import Dict
from typing import List
from typing import Optional
from typing import Set
from typing import Tuple
from typing import Union

PathLike = Union[str, "os.PathLike[str]"]

_HUNK_HEADER_RE = re.compile(rb"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
_GIT_STYLE_NAMES_RE = re.compile(rb'^"?a/.*[ \t]"?b/')
_DRIVE_RE = re.compile(r"^[A-Za-z]:")
_DEV_NULL = b"/dev/null"
# A format-patch signature separator. Some mailers trim the trailing space.
_SIGNATURE_LINES = (b"-- ", b"--")
_C_ESCAPES = {
    ord("a"): 0x07,
    ord("b"): 0x08,
    ord("t"): 0x09,
    ord("n"): 0x0A,
    ord("v"): 0x0B,
    ord("f"): 0x0C,
    ord("r"): 0x0D,
    ord('"'): ord('"'),
    ord("\\"): ord("\\"),
}


class PatchError(Exception):
    """A patch file could not be applied."""


class PatchParseError(PatchError):
    """A patch file is malformed or contains no file changes."""


@dataclass
class _Line:
    op: bytes  # b" ", b"-" or b"+"
    body: bytes  # The line without its op character or line ending.
    eol: bytes  # The line ending in the patch: b"\n", b"\r\n" or b"".
    no_eol: bool  # Followed by "\ No newline at end of file".


@dataclass
class _Hunk:
    old_start: int
    old_count: int
    line_no: int  # Line number of the `@@` header in the patch file.
    lines: List[_Line] = field(default_factory=list)


@dataclass
class _FilePatch:
    """The changes to one file, with names as they appear in the patch (not yet stripped)."""

    line_no: int
    old_name: Optional[bytes] = None  # From `--- `.
    new_name: Optional[bytes] = None  # From `+++ `.
    git_names: Optional[bytes] = None  # The rest of a `diff --git ` line.
    rename_from: Optional[bytes] = None
    rename_to: Optional[bytes] = None
    copy_from: Optional[bytes] = None
    copy_to: Optional[bytes] = None
    created: bool = False
    deleted: bool = False
    new_mode: Optional[int] = None
    hunks: List[_Hunk] = field(default_factory=list)

    @property
    def has_git_changes(self) -> bool:
        return bool(
            self.hunks
            or self.created
            or self.deleted
            or self.new_mode is not None
            or self.rename_from is not None
            or self.rename_to is not None
            or self.copy_from is not None
            or self.copy_to is not None
        )


def _split_lines(data: bytes) -> List[bytes]:
    """Split on `\\n` only, keeping line endings. A lone `\\r` is not a line break."""
    parts = data.split(b"\n")
    lines = [part + b"\n" for part in parts[:-1]]
    if parts[-1]:
        lines.append(parts[-1])
    return lines


def _split_eol(line: bytes) -> Tuple[bytes, bytes]:
    if line.endswith(b"\r\n"):
        return line[:-2], b"\r\n"
    if line.endswith(b"\n"):
        return line[:-1], b"\n"
    return line, b""


def _chomp(line: bytes) -> bytes:
    return _split_eol(line)[0]


def _unquote(data: bytes, line_no: int) -> Tuple[bytes, bytes]:
    """Decode the C-style quoted name at the start of `data`, as git writes it.

    Returns the decoded name and the rest of `data` after the closing quote.
    """
    out = bytearray()
    i = 1
    while i < len(data):
        c = data[i]
        if c == ord('"'):
            return bytes(out), data[i + 1 :]
        if c != ord("\\"):
            out.append(c)
            i += 1
            continue
        escape = data[i + 1 : i + 2]
        if escape and escape[0] in _C_ESCAPES:
            out.append(_C_ESCAPES[escape[0]])
            i += 2
            continue
        octal = data[i + 1 : i + 4]
        if re.fullmatch(rb"[0-3][0-7][0-7]", octal):
            out.append(int(octal, 8))
            i += 4
            continue
        raise PatchParseError(f"line {line_no}: invalid escape in quoted file name: {data!r}")
    raise PatchParseError(f"line {line_no}: unterminated quoted file name: {data!r}")


def _header_name(rest: bytes, line_no: int) -> bytes:
    """Return the file name from the text after `--- `, `+++ `, `rename from `, and so on."""
    if rest.startswith(b'"'):
        return _unquote(rest, line_no)[0]
    # A tab separates the name from an optional timestamp.
    return rest.split(b"\t", 1)[0].rstrip(b" ")


def _skip_components(name: bytes, strip: int) -> Optional[bytes]:
    """Drop `strip` leading path components, like git's `skip_tree_prefix`.

    A run of slashes counts as one separator, as in `_clean_path`.
    """
    if name.startswith(b"/") or b".." in name.split(b"/"):
        return None
    if strip == 0:
        return name
    remaining = strip
    for i, c in enumerate(name):
        if c != ord("/") or name[i - 1] == ord("/"):
            continue
        remaining -= 1
        if remaining == 0:
            return name[i + 1 :].lstrip(b"/")
    return None


def _git_header_name(names: bytes, strip: int, line_no: int) -> Optional[bytes]:
    """Find the file name in `diff --git <old> <new>` when both names are the same.

    The names aren't delimited when they contain spaces, so this follows git:
    pick the first split where both halves are equal after stripping. Returns
    None if there is no such split.
    """
    if names.startswith(b'"'):
        first, rest = _unquote(names, line_no)
        first = _skip_components(first, strip)
        if first is None or not rest[:1].isspace():
            return None
        rest = rest[1:]
        if rest.startswith(b'"'):
            second, tail = _unquote(rest, line_no)
            if tail:
                return None
        else:
            second = rest
        return first if _skip_components(second, strip) == first else None

    name = _skip_components(names, strip)
    if name is None:
        return None
    quote = name.find(b'"')
    if quote >= 0:
        # The first name is unquoted, so a quote starts the second name.
        second, tail = _unquote(name[quote:], line_no)
        second = _skip_components(second, strip)
        if second is None or tail:
            return None
        first = name[:quote]
        return second if first[:-1] == second and first[-1:].isspace() else None
    for i, c in enumerate(name):
        if c in b" \t" and _skip_components(name[i + 1 :], strip) == name[:i]:
            return name[:i]
    return None


def _parse_mode(text: bytes, line_no: int) -> int:
    try:
        mode = int(text.strip(), 8)
    except ValueError:
        raise PatchParseError(f"line {line_no}: invalid file mode: {text!r}") from None
    if stat.S_IFMT(mode) != stat.S_IFREG:
        raise PatchParseError(
            f"line {line_no}: unsupported file mode {text.decode(errors='replace')}; "
            "only regular files can be patched (no symlinks or submodules)"
        )
    return mode


class _Parser:
    def __init__(self, data: bytes):
        self.lines = _split_lines(data)
        self.n = len(self.lines)

    def parse(self) -> List[_FilePatch]:
        files = []
        i = 0
        while i < self.n:
            line = _chomp(self.lines[i])
            if line.startswith(b"diff --git "):
                fp, i = self._parse_git_section(i)
                files.append(fp)
                continue
            header = self._file_header_at(i)
            if header is not None:
                fp = _FilePatch(line_no=i + 1, old_name=header[0], new_name=header[1])
                i = self._parse_hunks(header[2], fp)
                if not fp.hunks:
                    raise PatchParseError(f"line {fp.line_no}: file header has no hunks")
                files.append(fp)
                continue
            self._check_unsupported(line, i)
            if line.startswith(b"@@ "):
                if _HUNK_HEADER_RE.match(line):
                    raise PatchParseError(f"line {i + 1}: hunk has no '--- '/'+++ ' file header before it")
                raise PatchParseError(f"line {i + 1}: invalid hunk header: {line!r}")
            # Anything else (mail headers, commit messages, diffstats) is ignored.
            i += 1
        return files

    def _check_unsupported(self, line: bytes, i: int) -> None:
        if line.startswith((b"GIT binary patch", b"Binary files ")):
            raise PatchParseError(f"line {i + 1}: binary patches are not supported")

    def _file_header_at(self, i: int) -> Optional[Tuple[Optional[bytes], Optional[bytes], int]]:
        """Match a file header at line `i`.

        Returns `(old_name, new_name, next_line)`, or None. Besides the usual
        `--- ` and `+++ ` pair, this accepts the forms GNU patch does: the two
        lines in reverse order, or only one of them, followed by a hunk.
        """
        first = _chomp(self.lines[i])
        if not first.startswith((b"--- ", b"+++ ")) or i + 1 >= self.n:
            return None
        second = _chomp(self.lines[i + 1])
        name = _header_name(first[4:], i + 1)
        if first.startswith(b"--- ") and second.startswith(b"+++ "):
            return name, _header_name(second[4:], i + 2), i + 2
        if (
            first.startswith(b"+++ ")
            and second.startswith(b"--- ")
            and i + 2 < self.n
            and _HUNK_HEADER_RE.match(self.lines[i + 2])
        ):
            return _header_name(second[4:], i + 2), name, i + 2
        if _HUNK_HEADER_RE.match(second):
            if first.startswith(b"--- "):
                return name, None, i + 1
            return None, name, i + 1
        return None

    def _parse_git_section(self, i: int) -> Tuple[_FilePatch, int]:
        fp = _FilePatch(line_no=i + 1, git_names=_chomp(self.lines[i])[len(b"diff --git ") :])
        i += 1
        while i < self.n:
            line = _chomp(self.lines[i])
            line_no = i + 1
            if line.startswith(b"old mode "):
                _parse_mode(line[len(b"old mode ") :], line_no)
            elif line.startswith(b"new mode "):
                fp.new_mode = _parse_mode(line[len(b"new mode ") :], line_no)
            elif line.startswith(b"deleted file mode "):
                _parse_mode(line[len(b"deleted file mode ") :], line_no)
                fp.deleted = True
            elif line.startswith(b"new file mode "):
                fp.new_mode = _parse_mode(line[len(b"new file mode ") :], line_no)
                fp.created = True
            elif line.startswith(b"rename from "):
                fp.rename_from = _header_name(line[len(b"rename from ") :], line_no)
            elif line.startswith(b"rename to "):
                fp.rename_to = _header_name(line[len(b"rename to ") :], line_no)
            elif line.startswith(b"copy from "):
                fp.copy_from = _header_name(line[len(b"copy from ") :], line_no)
            elif line.startswith(b"copy to "):
                fp.copy_to = _header_name(line[len(b"copy to ") :], line_no)
            elif line.startswith(b"index "):
                # `index <old>..<new> <mode>` carries the mode when it doesn't change. A
                # symlink or submodule update has no other mode line.
                fields = line.split()
                if len(fields) > 2:
                    _parse_mode(fields[2], line_no)
            elif line.startswith((b"similarity index ", b"dissimilarity index ")):
                pass
            else:
                self._check_unsupported(line, i)
                break
            i += 1

        header = self._file_header_at(i) if i < self.n else None
        if header is not None:
            fp.old_name, fp.new_name = header[0], header[1]
            i = self._parse_hunks(header[2], fp)
        if not fp.has_git_changes:
            raise PatchParseError(f"line {fp.line_no}: 'diff --git' section has no changes")
        return fp, i

    def _parse_hunks(self, i: int, fp: _FilePatch) -> int:
        while i < self.n and self.lines[i].startswith(b"@@"):
            header = _chomp(self.lines[i])
            m = _HUNK_HEADER_RE.match(header)
            if not m:
                raise PatchParseError(f"line {i + 1}: invalid hunk header: {header!r}")
            hunk = _Hunk(
                old_start=int(m.group(1)),
                old_count=1 if m.group(2) is None else int(m.group(2)),
                line_no=i + 1,
            )
            rem_old = hunk.old_count
            rem_new = 1 if m.group(4) is None else int(m.group(4))
            i += 1
            while rem_old > 0 or rem_new > 0:
                if i >= self.n:
                    raise PatchParseError(f"line {hunk.line_no}: patch ends inside the hunk")
                content, eol = _split_eol(self.lines[i])
                if not content and rem_old > 0 and rem_new > 0:
                    # Some tools and editors drop the space from blank context lines.
                    op, body = b" ", b""
                else:
                    op, body = content[:1], content[1:]
                if op == b" " and rem_old > 0 and rem_new > 0:
                    rem_old -= 1
                    rem_new -= 1
                elif op == b"-" and rem_old > 0:
                    rem_old -= 1
                elif op == b"+" and rem_new > 0:
                    rem_new -= 1
                else:
                    raise PatchParseError(
                        f"line {i + 1}: line doesn't fit the hunk at line {hunk.line_no}: {self.lines[i]!r}"
                    )
                i += 1
                no_eol = i < self.n and self.lines[i].startswith(b"\\")
                if no_eol:
                    i += 1
                hunk.lines.append(_Line(op, body, eol, no_eol))
            fp.hunks.append(hunk)

        if fp.hunks and i < self.n:
            # A diff line right after the last hunk usually means the hunk's line counts
            # are wrong. GNU patch ignores it; refuse instead of silently dropping it.
            line = _chomp(self.lines[i])
            if line[:1] in (b"+", b"-", b" ") and line not in _SIGNATURE_LINES and self._file_header_at(i) is None:
                raise PatchParseError(
                    f"line {i + 1}: diff line after the end of the hunk; check the hunk's line counts: "
                    f"{self.lines[i]!r}"
                )
        return i


def _clean_path(name: bytes, strip: int, line_no: int) -> str:
    """Strip `strip` leading components from a patch file name and check that it's safe."""
    try:
        path = name.decode("utf-8")
    except UnicodeDecodeError:
        raise PatchError(f"line {line_no}: file name is not UTF-8: {name!r}") from None
    if path.startswith("/") or "\\" in path or "\0" in path or _DRIVE_RE.match(path):
        raise PatchError(f"line {line_no}: unsafe file name: {path!r}")
    parts = [part for part in path.split("/") if part]
    if ".." in parts:
        raise PatchError(f"line {line_no}: unsafe file name: {path!r}")
    if strip >= len(parts):
        raise PatchError(f"line {line_no}: can't strip {strip} components from file name {path!r}")
    parts = [part for part in parts[strip:] if part != "."]
    if not parts or _DRIVE_RE.match(parts[0]):
        raise PatchError(f"line {line_no}: unsafe file name: {path!r}")
    return "/".join(parts)


def _is_git_style(fp: _FilePatch) -> bool:
    """Whether the names in `fp` carry git's `a/` and `b/` prefixes."""
    if fp.old_name is not None and fp.new_name is not None:
        old, new = fp.old_name, fp.new_name
        if old == _DEV_NULL and new == _DEV_NULL:
            return False
        return (old == _DEV_NULL or old.startswith(b"a/")) and (new == _DEV_NULL or new.startswith(b"b/"))
    if fp.git_names is not None and fp.old_name is None and fp.new_name is None:
        return bool(_GIT_STYLE_NAMES_RE.match(fp.git_names))
    return False


def _effective_strip(files: List[_FilePatch], strip: int) -> int:
    if strip == 0 and files and all(_is_git_style(fp) for fp in files):
        return 1
    return strip


@dataclass
class _Change:
    """One file change, with names resolved to root-relative paths. At most one name is None."""

    fp: _FilePatch
    old: Optional[str]  # None when the file is created.
    new: Optional[str]  # None when the file is deleted.
    rename: bool = False
    copy: bool = False


def _resolve(fp: _FilePatch, strip: int) -> _Change:
    line_no = fp.line_no
    rename = fp.rename_from is not None or fp.rename_to is not None
    copy = fp.copy_from is not None or fp.copy_to is not None
    if fp.created and fp.deleted:
        raise PatchParseError(f"line {line_no}: file is both created and deleted")
    if rename and copy:
        raise PatchParseError(f"line {line_no}: file is both renamed and copied")
    if (rename or copy) and (fp.created or fp.deleted):
        raise PatchParseError(f"line {line_no}: a renamed or copied file can't be created or deleted")

    if rename or copy:
        src, dst = (fp.rename_from, fp.rename_to) if rename else (fp.copy_from, fp.copy_to)
        if src is None or dst is None:
            raise PatchParseError(f"line {line_no}: incomplete rename or copy")
        # These names have no `a/` or `b/` prefix, so git strips one component less.
        sub = max(0, strip - 1)
        return _Change(fp, _clean_path(src, sub, line_no), _clean_path(dst, sub, line_no), rename, not rename)

    if fp.old_name is not None or fp.new_name is not None:
        old_name = fp.old_name if fp.old_name is not None else fp.new_name
        new_name = fp.new_name if fp.new_name is not None else fp.old_name
        if old_name == _DEV_NULL and new_name == _DEV_NULL:
            raise PatchParseError(f"line {line_no}: both file names are /dev/null")
        old = None if old_name == _DEV_NULL else _clean_path(old_name, strip, line_no)
        new = None if new_name == _DEV_NULL else _clean_path(new_name, strip, line_no)
    else:
        # A git section without hunks (an empty file, or a mode change): the only name is
        # on the `diff --git` line.
        name = _git_header_name(fp.git_names or b"", strip, line_no)
        if name is None:
            raise PatchParseError(f"line {line_no}: can't find the file name in the 'diff --git' line")
        old = new = _clean_path(name, 0, line_no)

    if fp.created:
        if new is None:
            raise PatchParseError(f"line {line_no}: new file mode, but the new name is /dev/null")
        old = None
    if fp.deleted:
        if old is None:
            raise PatchParseError(f"line {line_no}: deleted file mode, but the old name is /dev/null")
        new = None
    return _Change(fp, old, new)


def _find_hunk(file_lines: List[bytes], preferred: int, old_lines: List[bytes], min_pos: int) -> Optional[int]:
    """Find where `old_lines` occur, searching outward from `preferred` but not before `min_pos`."""

    last = len(file_lines) - len(old_lines)
    if not old_lines:
        return preferred if min_pos <= preferred <= last else None
    if min_pos > last:
        return None

    def matches(pos: int) -> bool:
        return min_pos <= pos <= last and all(
            _chomp(file_lines[pos + k]) == expected for k, expected in enumerate(old_lines)
        )

    # Searching from the nearest valid position visits candidates in the same order, and keeps
    # a huge line number in the hunk header from turning into a huge loop.
    preferred = min(max(preferred, min_pos), last)
    for delta in range(max(preferred - min_pos, last - preferred) + 1):
        for pos in (preferred - delta, preferred + delta):
            if matches(pos):
                return pos
    return None


def _apply_hunks(content: bytes, hunks: List[_Hunk], rel: str) -> bytes:
    file_lines = _split_lines(content)
    if any(line.endswith(b"\r\n") for line in file_lines):
        file_eol: Optional[bytes] = b"\r\n"
    elif any(line.endswith(b"\n") for line in file_lines):
        file_eol = b"\n"
    else:
        file_eol = None  # Use each added line's own ending from the patch.

    offset = 0
    min_pos = 0
    for number, hunk in enumerate(hunks, start=1):
        old_lines = [line.body for line in hunk.lines if line.op != b"+"]
        # Where the hunk's old lines start in the original file. A hunk with no old lines
        # inserts after line `old_start`.
        orig_start = hunk.old_start if hunk.old_count == 0 else max(hunk.old_start - 1, 0)
        pos = _find_hunk(file_lines, max(orig_start + offset, 0), old_lines, min_pos)
        if pos is None:
            raise PatchError(
                f"hunk #{number} (patch line {hunk.line_no}) failed to apply to {rel} "
                f"at line {hunk.old_start}: context mismatch"
            )

        replacement = []
        cur = pos
        for line in hunk.lines:
            if line.op == b"-":
                cur += 1
                continue
            if line.op == b" ":
                text = file_lines[cur]
                cur += 1
            else:
                text = line.body
            body, eol = _split_eol(text)
            if line.no_eol:
                replacement.append(body)
            elif line.op == b" " and eol:
                replacement.append(text)
            else:
                replacement.append(body + (file_eol or line.eol or b"\n"))
        file_lines[pos:cur] = replacement
        # Carry forward both earlier hunks' line count changes and any drift found by the search.
        offset = pos + len(replacement) - (orig_start + hunk.old_count)
        min_pos = pos + len(replacement)
    return b"".join(file_lines)


class _Tree:
    """The files under `root` as the patch changes them. Nothing is written until `commit`.

    Paths are root-relative POSIX strings. Symlinks are never followed or patched: a
    symlink counts as an existing non-directory, and paths beyond one are rejected.
    """

    def __init__(self, root: Path):
        self.root = root
        self.root_resolved = root.resolve()
        self._content: Dict[str, Optional[bytes]] = {}  # None means deleted.
        self._executable: Dict[str, bool] = {}
        self._order: List[str] = []

    @staticmethod
    def _ancestors(rel: str) -> List[str]:
        parts = rel.split("/")
        return ["/".join(parts[:i]) for i in range(1, len(parts))]

    def _path(self, rel: str) -> Path:
        for ancestor in self._ancestors(rel):
            if (self.root / ancestor).is_symlink():
                raise PatchError(f"'{rel}' is beyond a symbolic link")
        path = self.root / rel
        resolved = path.resolve()
        if resolved == self.root_resolved or not resolved.is_relative_to(self.root_resolved):
            raise PatchError(f"'{rel}' resolves outside the patch root")
        return path

    def _touch(self, rel: str) -> None:
        if rel not in self._content and rel not in self._executable:
            self._order.append(rel)

    def _under_planned_file(self, rel: str) -> bool:
        return any(self._content.get(ancestor) is not None for ancestor in self._ancestors(rel))

    def is_file(self, rel: str) -> bool:
        """Whether `rel` will be a file (or symlink) after the changes planned so far."""
        if self._under_planned_file(rel):
            return False
        if rel in self._content:
            return self._content[rel] is not None
        path = self._path(rel)
        return path.is_symlink() or (path.exists() and not path.is_dir())

    def _is_dir(self, rel: str) -> bool:
        """Whether `rel` will be a directory after the changes planned so far.

        A directory whose files are all deleted goes away, as `commit` removes it.
        """
        if self._under_planned_file(rel) or self._content.get(rel) is not None:
            return False
        prefix = rel + "/"
        if any(key.startswith(prefix) and content is not None for key, content in self._content.items()):
            return True
        path = self._path(rel)
        if path.is_symlink() or not path.is_dir():
            return False
        if not any(key.startswith(prefix) for key, content in self._content.items() if content is None):
            return True
        for dirpath, dirnames, filenames in os.walk(path):
            if not dirnames and not filenames:
                return True  # An empty directory stays.
            for name in filenames + [d for d in dirnames if os.path.islink(os.path.join(dirpath, d))]:
                entry = Path(dirpath, name).relative_to(self.root).as_posix()
                if entry not in self._content:
                    return True
        return False

    def exists(self, rel: str) -> bool:
        return self.is_file(rel) or self._is_dir(rel)

    def check_file(self, rel: str) -> None:
        if self.is_file(rel):
            return
        if self.exists(rel):
            raise PatchError(f"'{rel}' is not a regular file")
        raise PatchError(f"patch targets non-existent file '{rel}'")

    def _check_disk_file(self, rel: str) -> Path:
        path = self._path(rel)
        if path.is_symlink() or not path.is_file():
            raise PatchError(f"'{rel}' is not a regular file")
        return path

    def read(self, rel: str) -> bytes:
        self.check_file(rel)
        content = self._content.get(rel)
        if content is not None:
            return content
        return self._check_disk_file(rel).read_bytes()

    def is_executable(self, rel: str) -> bool:
        if rel in self._executable:
            return self._executable[rel]
        return bool(self._check_disk_file(rel).stat().st_mode & 0o111)

    def write(self, rel: str, content: bytes) -> None:
        self._touch(rel)
        self._content[rel] = content

    def create(self, rel: str, content: bytes, executable: bool) -> None:
        if self.exists(rel):
            raise PatchError(f"patch creates '{rel}', which already exists")
        for ancestor in self._ancestors(rel):
            if self.is_file(ancestor):
                raise PatchError(f"can't create '{rel}': '{ancestor}' is a file")
        self.write(rel, content)
        # Always set the mode: the file may replace a deleted executable at the same path.
        self.set_executable(rel, executable)

    def delete(self, rel: str) -> None:
        self._touch(rel)
        self._content[rel] = None
        self._executable.pop(rel, None)

    def set_executable(self, rel: str, executable: bool) -> None:
        if rel not in self._content:
            self._check_disk_file(rel)
        self._touch(rel)
        self._executable[rel] = executable

    def commit(self) -> None:
        # Delete first, so a deleted file's path can become a directory and vice versa.
        for rel in self._order:
            if rel in self._content and self._content[rel] is None:
                path = self.root / rel
                if os.path.lexists(path):
                    if os.name == "nt":
                        try:
                            os.chmod(path, stat.S_IWRITE | stat.S_IREAD)
                        except OSError:
                            pass
                    path.unlink()
                self._remove_empty_parents(path.parent)
        default_mode: Optional[int] = None
        for rel in self._order:
            path = self.root / rel
            content = self._content.get(rel)
            if content is not None:
                path.parent.mkdir(parents=True, exist_ok=True)
                orig_mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else None
                fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=".pycross_patch_")
                try:
                    with os.fdopen(fd, "wb") as f:
                        f.write(content)
                    if orig_mode is not None:
                        perm = orig_mode
                    else:
                        if default_mode is None:
                            umask = os.umask(0)
                            os.umask(umask)
                            default_mode = 0o666 & ~umask
                        perm = default_mode
                    if rel in self._executable:
                        if self._executable[rel]:
                            perm |= (perm & 0o444) >> 2
                        else:
                            perm &= ~0o111
                    os.chmod(tmp_name, perm)
                    if os.name == "nt" and orig_mode is not None and not (orig_mode & stat.S_IWUSR):
                        os.chmod(path, orig_mode | stat.S_IWUSR)
                    os.replace(tmp_name, path)
                except BaseException:
                    try:
                        if os.name == "nt":
                            os.chmod(tmp_name, stat.S_IWRITE | stat.S_IREAD)
                        os.unlink(tmp_name)
                    except OSError:
                        pass
                    raise
            elif rel in self._executable:
                perm = stat.S_IMODE(path.stat().st_mode)
                if self._executable[rel]:
                    perm |= (perm & 0o444) >> 2
                else:
                    perm &= ~0o111
                os.chmod(path, perm)

    def _remove_empty_parents(self, directory: Path) -> None:
        while directory != self.root:
            try:
                directory.rmdir()
            except OSError:
                return
            directory = directory.parent


def _apply_change(tree: _Tree, change: _Change) -> Set[str]:
    fp = change.fp
    old, new = change.old, change.new
    new_executable = None if fp.new_mode is None else bool(fp.new_mode & 0o111)

    if old is None:
        assert new is not None  # Checked in _resolve.
        tree.create(new, _apply_hunks(b"", fp.hunks, new), bool(new_executable))
        return {new}

    if new is None:
        tree.check_file(old)
        if _apply_hunks(tree.read(old), fp.hunks, old):
            raise PatchError(f"patch deletes '{old}' but doesn't remove all of its lines")
        tree.delete(old)
        return {old}

    if change.rename or change.copy:
        tree.check_file(old)
        if tree.exists(new):
            raise PatchError(f"patch {'renames' if change.rename else 'copies'} to '{new}', which already exists")
        executable = tree.is_executable(old) if new_executable is None else new_executable
        content = _apply_hunks(tree.read(old), fp.hunks, old)
        if change.rename:
            tree.delete(old)
        tree.create(new, content, executable)
        return {old, new}

    # A modification patches the new name; the old one may be a backup such as `x.py.orig`.
    # Like GNU patch, use the old name if only that file exists (`diff -u x.py x.py.new`).
    target = new
    if old != new and fp.git_names is None and not tree.is_file(new) and tree.is_file(old):
        target = old
    tree.check_file(target)
    if fp.hunks:
        tree.write(target, _apply_hunks(tree.read(target), fp.hunks, target))
    if new_executable is not None:
        tree.set_executable(target, new_executable)
    return {target}


def _parse(data: bytes) -> List[_FilePatch]:
    files = _Parser(data).parse()
    if not files:
        raise PatchParseError("no file changes found; is this a unified diff?")
    return files


def effective_strip(patch_bytes: bytes, strip: int = 0) -> int:
    """Return the strip level pycross applies `patch_bytes` with.

    At `strip == 0`, a patch whose file names all carry git's `a/` and `b/`
    prefixes (or are `/dev/null`) gets strip 1. Otherwise `strip` is used as
    given.
    """
    try:
        return _effective_strip(_parse(patch_bytes), strip)
    except PatchError:
        return strip


def apply_patch(root: PathLike, patch: PathLike, strip: int = 0) -> Set[str]:
    """Apply one patch file under `root` and return the root-relative paths it touched.

    Raises:
        PatchParseError: the patch is malformed, unsupported, or has no file changes.
        PatchError: the patch doesn't apply exactly, or is unsafe. Nothing is written.
    """
    patch_path = Path(patch)
    try:
        data = patch_path.read_bytes()
    except OSError as e:
        raise PatchError(str(e)) from e
    files = _parse(data)
    strip = _effective_strip(files, strip)
    changes = [_resolve(fp, strip) for fp in files]

    tree = _Tree(Path(root))
    touched: Set[str] = set()
    try:
        for change in changes:
            touched |= _apply_change(tree, change)
        tree.commit()
    except OSError as e:
        raise PatchError(str(e)) from e
    return touched


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
