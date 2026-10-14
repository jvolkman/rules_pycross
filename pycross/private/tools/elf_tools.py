"""Read-only pure-Python ELF metadata extractor (`soname`, `needed`, `rpath`, `runpath`).

Used by `wheel_index.py` during `PycrossWheelInstall` to record the `"native"` section of each
wheel's `index.json` without external tools or bootstrap dependencies.
"""

from __future__ import annotations

import posixpath
import struct
from pathlib import Path
from typing import Any
from typing import BinaryIO
from typing import Optional

NATIVE_CONSUMER_FILENAME = ".pycross-native-consumer.json"
NATIVE_PROVIDER_FILENAME = ".pycross-native.json"

ELF_MAGIC_BYTES = b"\x7fELF"

ELFCLASS32 = 1
ELFCLASS64 = 2

ELFDATA2LSB = 1
ELFDATA2MSB = 2

ET_EXEC = 2
ET_DYN = 3

SHT_STRTAB = 3
SHT_DYNAMIC = 6

DT_NULL = 0
DT_NEEDED = 1
DT_SONAME = 14
DT_RPATH = 15
DT_RUNPATH = 29


def is_candidate_so(name: str) -> bool:
    """Whether `name` looks like a shared object or Python extension on Linux."""
    return name.endswith(".so") or ".so." in name


def _get_strtab_entry(strtab: bytes, offset: int) -> str:
    if offset < 0 or offset >= len(strtab):
        return ""
    end = strtab.find(b"\0", offset)
    raw = strtab[offset:] if end < 0 else strtab[offset:end]
    return raw.decode("utf-8", "replace")


def _split_rpath(text: str) -> list[str]:
    if not text:
        return []
    return [entry for entry in text.split(":") if entry]


def _parse_elf_dynamic(fh: BinaryIO) -> Optional[dict[str, Any]]:
    ident = fh.read(16)
    if len(ident) < 16 or ident[:4] != ELF_MAGIC_BYTES:
        return None

    ei_class = ident[4]
    ei_data = ident[5]
    if ei_class not in (ELFCLASS32, ELFCLASS64) or ei_data not in (ELFDATA2LSB, ELFDATA2MSB):
        return None

    endian = "<" if ei_data == ELFDATA2LSB else ">"
    is_64 = ei_class == ELFCLASS64

    if is_64:
        ehdr_fmt = struct.Struct(endian + "HHIQQQIHHHHHH")
        shdr_fmt = struct.Struct(endian + "IIQQQQIIQQ")
        dyn_fmt = struct.Struct(endian + "qQ")
    else:
        ehdr_fmt = struct.Struct(endian + "HHIIIIIHHHHHH")
        shdr_fmt = struct.Struct(endian + "IIIIIIIIII")
        dyn_fmt = struct.Struct(endian + "iI")

    ehdr_buf = fh.read(ehdr_fmt.size)
    if len(ehdr_buf) != ehdr_fmt.size:
        return None
    (
        e_type,
        _e_machine,
        _e_version,
        _e_entry,
        _e_phoff,
        e_shoff,
        _e_flags,
        _e_ehsize,
        _e_phentsize,
        _e_phnum,
        e_shentsize,
        e_shnum,
        _e_shstrndx,
    ) = ehdr_fmt.unpack(ehdr_buf)

    if e_type not in (ET_EXEC, ET_DYN) or not e_shoff or e_shentsize != shdr_fmt.size:
        return None

    fh.seek(e_shoff)
    shdrs = []
    if e_shnum == 0:
        first_buf = fh.read(shdr_fmt.size)
        if len(first_buf) != shdr_fmt.size:
            return None
        first_shdr = shdr_fmt.unpack(first_buf)
        e_shnum = first_shdr[5]  # sh_size holds actual count when >= SHN_LORESERVE
        shdrs.append(first_shdr)
        remaining = e_shnum - 1
    else:
        remaining = e_shnum

    for _ in range(remaining):
        buf = fh.read(shdr_fmt.size)
        if len(buf) != shdr_fmt.size:
            return None
        shdrs.append(shdr_fmt.unpack(buf))

    dyn_shdr = None
    for shdr in shdrs:
        if shdr[1] == SHT_DYNAMIC:
            dyn_shdr = shdr
            break
    if dyn_shdr is None:
        return None

    strtab_idx = dyn_shdr[6]  # sh_link points to the associated .dynstr section
    if strtab_idx >= len(shdrs):
        return None
    strtab_shdr = shdrs[strtab_idx]
    if strtab_shdr[1] != SHT_STRTAB:
        return None

    fh.seek(strtab_shdr[4])  # sh_offset
    dynstr = fh.read(strtab_shdr[5])  # sh_size

    fh.seek(dyn_shdr[4])  # sh_offset
    dyn_size = dyn_shdr[5]
    soname: Optional[str] = None
    needed: list[str] = []
    rpath_str = ""
    runpath_str = ""

    for _ in range(dyn_size // dyn_fmt.size):
        buf = fh.read(dyn_fmt.size)
        if len(buf) != dyn_fmt.size:
            break
        d_tag, d_val = dyn_fmt.unpack(buf)
        if d_tag == DT_NULL:
            break
        elif d_tag == DT_SONAME:
            soname = _get_strtab_entry(dynstr, d_val)
        elif d_tag == DT_NEEDED:
            val = _get_strtab_entry(dynstr, d_val)
            if val:
                needed.append(val)
        elif d_tag == DT_RPATH:
            rpath_str = _get_strtab_entry(dynstr, d_val)
        elif d_tag == DT_RUNPATH:
            runpath_str = _get_strtab_entry(dynstr, d_val)

    return {
        "soname": soname,
        "needed": needed,
        "rpath": _split_rpath(rpath_str),
        "runpath": _split_rpath(runpath_str),
    }


def read_elf_metadata(path: Path) -> Optional[dict[str, Any]]:
    """Returns `{soname, needed, rpath, runpath}` for an ELF shared object, or `None`."""
    try:
        if not path.is_file():
            return None
        with open(path, "rb") as fh:
            return _parse_elf_dynamic(fh)
    except Exception:
        return None


def candidate_origin_dirs(own_dirs: set[str], so_dir: str, entry: str) -> list[str]:
    """Return candidate cross-wheel relative directory paths for an `$ORIGIN` RPATH entry."""
    for token in ("$ORIGIN/", "${ORIGIN}/"):
        if entry.startswith(token):
            after = entry[len(token) :]
            break
    else:
        return []
    if not after:
        return []
    norm = posixpath.normpath(posixpath.join(so_dir, after) if so_dir else after)
    if norm == "." or (not norm.startswith("..") and norm in own_dirs):
        return []
    candidates: list[str] = []
    if not norm.startswith(".."):
        candidates.append(norm)
    parts = posixpath.normpath(after).split("/")
    while parts and parts[0] == "..":
        parts.pop(0)
    if parts and parts != ["."]:
        stripped = "/".join(parts)
        if stripped not in own_dirs and stripped not in candidates:
            candidates.append(stripped)
    return candidates


def is_native_consumer(
    top: Any,
    dirs: Any,
    native: dict[str, dict[str, Any]],
) -> bool:
    """Return True if a wheel's ELF files have any `$ORIGIN` RPATH/RUNPATH entry escaping the wheel."""
    if not native:
        return False
    own_dirs = set(dirs or ())
    own_dirs.update(top or ())
    for rel_so in native:
        parent = rel_so.rpartition("/")[0]
        while parent:
            own_dirs.add(parent)
            parent = parent.rpartition("/")[0]

    for rel_so, meta in native.items():
        so_dir = rel_so.rpartition("/")[0]
        rpaths = (meta.get("runpath") or []) + (meta.get("rpath") or [])
        for entry in rpaths:
            if candidate_origin_dirs(own_dirs, so_dir, entry):
                return True
    return False
