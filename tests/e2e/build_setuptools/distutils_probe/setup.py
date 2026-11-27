import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from setuptools import setup
from setuptools.command.build_ext import customize_compiler
from setuptools.command.build_ext import new_compiler
from setuptools.command.build_py import build_py as _build_py

_ELF_MAGIC = b"\x7fELF"
_SHT_DYNAMIC = 6
_DT_NULL = 0
_DT_RPATH = 15
_DT_RUNPATH = 29

_MACHO_HEADERS = {
    b"\xcf\xfa\xed\xfe": ("<", 32),  # 64-bit little-endian
    b"\xfe\xed\xfa\xcf": (">", 32),  # 64-bit big-endian
    b"\xce\xfa\xed\xfe": ("<", 28),  # 32-bit little-endian
    b"\xfe\xed\xfa\xce": (">", 28),  # 32-bit big-endian
}
_LC_RPATH = 0x8000001C


def _read_elf_rpaths(data: bytes) -> list[str]:
    ei_class = data[4]
    ei_data = data[5]
    if ei_data == 1:
        endian = "<"
    elif ei_data == 2:
        endian = ">"
    else:
        raise AssertionError(f"Unsupported ELF endianness: {ei_data}")

    if ei_class == 2:
        e_shoff = struct.unpack_from(endian + "Q", data, 40)[0]
        e_shentsize, e_shnum = struct.unpack_from(endian + "HH", data, 58)
        shdr_fmt = endian + "IIQQQQIIQQ"
        dyn_fmt = endian + "qQ"
    elif ei_class == 1:
        e_shoff = struct.unpack_from(endian + "I", data, 32)[0]
        e_shentsize, e_shnum = struct.unpack_from(endian + "HH", data, 46)
        shdr_fmt = endian + "IIIIIIIIII"
        dyn_fmt = endian + "iI"
    else:
        raise AssertionError(f"Unsupported ELF class: {ei_class}")

    dyn_size = struct.calcsize(dyn_fmt)
    sections = [struct.unpack_from(shdr_fmt, data, e_shoff + idx * e_shentsize) for idx in range(e_shnum)]

    rpaths: list[str] = []
    for sh in sections:
        sh_type, sh_offset, sh_size, sh_link, sh_entsize = sh[1], sh[4], sh[5], sh[6], sh[9]
        if sh_type != _SHT_DYNAMIC:
            continue
        str_sh = sections[sh_link]
        dynstr = data[str_sh[4] : str_sh[4] + str_sh[5]]
        step = sh_entsize or dyn_size
        for off in range(sh_offset, sh_offset + sh_size, step):
            d_tag, d_val = struct.unpack_from(dyn_fmt, data, off)
            if d_tag == _DT_NULL:
                break
            if d_tag not in (_DT_RPATH, _DT_RUNPATH):
                continue
            end = dynstr.index(b"\x00", d_val)
            raw = dynstr[d_val:end].decode("utf-8", errors="surrogateescape")
            rpaths.extend(raw.split(":"))
    return rpaths


def _read_macho_rpaths(data: bytes) -> list[str]:
    endian, offset = _MACHO_HEADERS[data[:4]]
    (ncmds,) = struct.unpack_from(endian + "I", data, 16)
    rpaths: list[str] = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from(endian + "II", data, offset)
        if cmd == _LC_RPATH:
            (str_offset,) = struct.unpack_from(endian + "I", data, offset + 8)
            raw = data[offset + str_offset : offset + cmdsize].split(b"\x00", 1)[0]
            rpaths.append(raw.decode("utf-8", errors="surrogateescape"))
        offset += cmdsize
    return rpaths


def _read_binary_rpaths(binary_path: Path) -> list[str]:
    data = binary_path.read_bytes()
    magic = data[:4]
    if magic == _ELF_MAGIC:
        return _read_elf_rpaths(data)
    if magic in _MACHO_HEADERS:
        return _read_macho_rpaths(data)
    raise AssertionError(f"Unsupported binary format for {binary_path}: {magic!r}")


def _sandbox_root_prefixes() -> list[str]:
    prefixes = ["bazel-out"]
    cwd = str(Path.cwd().absolute())
    prefixes.append(cwd)
    if "/bazel-out/" in cwd:
        execroot = cwd.split("/bazel-out/", 1)[0]
        if execroot:
            prefixes.append(execroot)
    sdist_rel = os.environ.get("PYCROSS_SDIST_DIR", "")
    if sdist_rel:
        rel_parts = Path(sdist_rel).parts
        cwd_path = Path(cwd)
        if len(cwd_path.parts) > len(rel_parts) and cwd_path.parts[-len(rel_parts) :] == rel_parts:
            execroot = str(cwd_path.parents[len(rel_parts) - 1])
            if execroot and execroot != "/" and execroot not in prefixes:
                prefixes.append(execroot)
    return prefixes


def _assert_rpath_preserved(binary_path: Path) -> None:
    rpaths = _read_binary_rpaths(binary_path)
    if "../lib" not in rpaths:
        raise AssertionError(f"Expected '../lib' in RPATH of {binary_path}, got: {rpaths!r}")
    forbidden = _sandbox_root_prefixes()
    for entry in rpaths:
        for bad in forbidden:
            if bad in entry:
                raise AssertionError(f"RPATH entry {entry!r} in {binary_path} leaked build path {bad!r}")


class build_py(_build_py):
    def run(self):
        subprocess.check_call([sys.executable, "-c", "from distutils.util import byte_compile"])

        # Exercise both compiler.link_executable (used by setup.py feature probes
        # where distutils invokes linker_exe = bare CC without LDFLAGS) and
        # compiler.link_shared_object (CPython-style extension link via LDSHARED).
        #
        # The probe verifies that the main-repo native_dep header is on the
        # include path, that transitive native_dep linkopts are forwarded
        # (-lm on Linux glibc for sin(); -framework Security on macOS for
        # SecRandomCopyBytes(); musl folds libm into libc), that quoted flags
        # keep their quotes, and that relative RPATHs (-Wl,-rpath,../lib) are
        # preserved verbatim without build-root absolutization.
        with tempfile.TemporaryDirectory() as tmpdir:
            src = Path(tmpdir) / "probe.c"
            src.write_text(
                "#include <math.h>\n"
                "#include <probe_hdr.h>\n"
                "#ifdef __APPLE__\n"
                "extern int SecRandomCopyBytes(const void *, unsigned long, void *);\n"
                "#endif\n"
                "static const char build_date[] = __DATE__;\n"
                "static const char probe_str[] = PROBE_STR;\n"
                '_Static_assert(sizeof(probe_str) == sizeof("a b"), "PROBE_STR");\n'
                "int main(int argc, char **argv) {\n"
                "    (void)argv; (void)build_date; (void)probe_str;\n"
                "    volatile double x = (double)argc;\n"
                "    volatile double y = sin(x);\n"
                "#ifdef __APPLE__\n"
                "    unsigned char buf[1] = {0};\n"
                "    int rc = SecRandomCopyBytes((const void *)0, 1, buf);\n"
                "    return (rc != 0 ? 1 : 0) + (y > 2.0 ? 1 : 0) + (PROBE_HDR_VALUE - 42);\n"
                "#else\n"
                "    return (y > 2.0 ? 1 : 0) + (PROBE_HDR_VALUE - 42);\n"
                "#endif\n"
                "}\n"
            )
            compiler = new_compiler()
            customize_compiler(compiler)
            objs = compiler.compile([str(src)], output_dir=tmpdir)
            compiler.link_executable(objs, "probe", output_dir=tmpdir)

            if compiler.compiler_type != "msvc":
                ext_src = Path(tmpdir) / "probe_ext.c"
                ext_src.write_text(
                    "#include <math.h>\n"
                    "#include <probe_hdr.h>\n"
                    "#ifdef __APPLE__\n"
                    "extern int SecRandomCopyBytes(const void *, unsigned long, void *);\n"
                    "#endif\n"
                    "extern int pycross_unresolved_ext_symbol(int);\n"
                    "int probe_ext_entry(int x) {\n"
                    "    volatile double d = (double)x;\n"
                    "    volatile double y = sin(d);\n"
                    "    int rc = pycross_unresolved_ext_symbol(x) + (y > 2.0 ? 1 : 0) + (PROBE_HDR_VALUE - 42);\n"
                    "#ifdef __APPLE__\n"
                    "    unsigned char buf[1] = {0};\n"
                    "    rc += SecRandomCopyBytes((const void *)0, 1, buf) != 0 ? 1 : 0;\n"
                    "#endif\n"
                    "    return rc;\n"
                    "}\n"
                )
                ext_objs = compiler.compile([str(ext_src)], output_dir=tmpdir, extra_preargs=["-fPIC"])
                compiler.link_shared_object(ext_objs, "probe_ext.so", output_dir=tmpdir)
                _assert_rpath_preserved(Path(tmpdir) / "probe_ext.so")

        super().run()


setup(
    name="distutils_probe",
    version="0.1",
    packages=["distutils_probe_pkg"],
    cmdclass={"build_py": build_py},
)
