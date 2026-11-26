import contextlib
import os
import pkgutil
import re
import shutil
import tempfile
from textwrap import dedent
from typing import Any
from typing import Dict
from typing import List
from typing import Optional
from typing import Tuple


def normalize_arch(cpu: str, *, os_name: Optional[str] = None) -> str:
    """Normalize a CPU architecture name to its Python/uname convention."""
    cpu = cpu.lower()
    os_lower = os_name.lower() if os_name else ""
    if cpu in ("aarch64", "arm64"):
        return "arm64" if os_lower.startswith(("darwin", "macosx")) else "aarch64"
    if cpu in ("x86_64", "amd64"):
        return "x86_64"
    if cpu in ("i386", "i486", "i586", "i686", "x86", "x86_32"):
        return "i686"
    if cpu in ("ppc64le", "powerpc64le"):
        return "ppc64le"
    if cpu in ("s390x", "riscv64"):
        return cpu
    if cpu.startswith("arm"):
        return "armv7l" if cpu in ("arm", "armv7", "armv7a") else cpu
    return cpu


def parse_target_triple(host_gnu_type: str) -> Tuple[str, str]:
    """Parse a GNU target triple into a normalized ``(os_name, arch)`` pair."""
    parts = host_gnu_type.lower().split("-")
    if len(parts) == 4:
        # e.g. aarch64-unknown-linux-gnu
        raw_arch, raw_os = parts[0], parts[2]
    elif len(parts) == 3:
        # e.g. aarch64-apple-darwin, aarch64-apple-darwin21.6.0, aarch64-linux-gnu
        raw_arch, raw_os = parts[0], parts[1]
        if raw_os == "apple" or parts[2].startswith("darwin"):
            raw_os = "darwin"
    else:
        raise ValueError(f"Cannot determine target platform from HOST_GNU_TYPE: {host_gnu_type}")

    os_name = "darwin" if (raw_os == "apple" or raw_os.startswith("darwin")) else raw_os
    return os_name, normalize_arch(raw_arch, os_name=os_name)


class TemplateContext:
    def __init__(self):
        self.locals = {}
        self.globals = {
            "__builtins__": __builtins__,
        }

    def update(self, other):
        self.locals.update(other)

    def expand(self, template):
        return re.sub(r"\{\{(.*?)\}\}", self._replace, template)

    def _replace(self, match):
        expr = match.group(1)
        return str(eval(expr, self.locals, self.globals))


@contextlib.contextmanager
def overwrite_file(name, mode="w", perms=None):
    """A context manager that will overwrite the given file
    only after it was closed with no error"""

    fp = tempfile.NamedTemporaryFile(mode, delete=False)
    try:
        yield fp
        fp.close()
        if perms is not None:
            os.chmod(fp.name, perms)
        shutil.move(fp.name, name)
    except Exception:
        fp.close()
        try:
            os.unlink(fp.name)
        except OSError:
            pass
        raise


def mkdir_if_needed(d):
    if not os.path.exists(d):
        os.makedirs(d)
    elif os.path.islink(d) or os.path.isfile(d):
        raise ValueError("Unable to make directory %r" % d)


def fixup_shebang(src):
    """Alter the shebang line if it's too long, as can happen sometimes with
    long Bazel sandbox paths. This trick is taken from what pip does."""
    if not src.startswith("#!"):
        return src

    # full line, including newline
    try:
        end = src.index("\n") + 1
    except ValueError:
        end = len(src)
    shebang = src[:end]

    if len(shebang.encode("utf-8")) <= 127:
        return src

    interp = shebang[2:].strip()
    preamble = dedent(
        f"""\
        #!/bin/sh
        '''exec' {interp} $0 "$@"
        '''
        """
    )
    return preamble + src[end:]


def install_script(name, dst, context=None, perms=0o755):
    srcname = os.path.join("scripts", name)
    src = pkgutil.get_data(__package__, srcname)
    if src and context is not None:
        src = context.expand(src.decode())
    src = fixup_shebang(src)
    mkdir_if_needed(os.path.dirname(dst))

    with overwrite_file(dst, perms=perms) as fp:
        fp.write(src)


def target_extension_suffixes(sysconfig_vars: Dict[str, Any]) -> Optional[List[str]]:
    """Return the target interpreter's importlib.machinery.EXTENSION_SUFFIXES.

    Mirrors CPython's _PyImport_DynLoadFiletab (Python/dynload_shlib.c) for POSIX targets, using
    the target's sysconfig variables. Build backends (setuptools, setuptools-rust) pick limited-API
    suffixes from this list, and since Python 3.15 those include the platform, e.g.
    ".abi3-x86_64-linux-gnu.so", so the exec interpreter's list must not leak into cross builds.

    Returns None for non-CPython targets.
    """
    soabi = sysconfig_vars.get("SOABI")
    if not soabi or not soabi.startswith("cpython-"):
        return None

    version = tuple(int(p) for p in str(sysconfig_vars.get("VERSION", "0.0")).split(".")[:2])
    freethreaded = bool(sysconfig_vars.get("Py_GIL_DISABLED"))

    suffixes = [sysconfig_vars.get("EXT_SUFFIX") or ".%s.so" % soabi]
    alt_soabi = sysconfig_vars.get("ALT_SOABI")
    if alt_soabi:
        suffixes.append(".%s.so" % alt_soabi)

    if version >= (3, 15):
        platform = sysconfig_vars.get("SOABI_PLATFORM")
        if not freethreaded:
            if platform:
                suffixes.append(".abi3-%s.so" % platform)
            suffixes.append(".abi3.so")
        if platform:
            suffixes.append(".abi3t-%s.so" % platform)
        suffixes.append(".abi3t.so")
    else:
        suffixes.append(".abi3.so")

    suffixes.append(".so")
    return suffixes
