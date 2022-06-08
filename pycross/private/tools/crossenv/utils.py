import contextlib
import importlib.util
import os
import pkgutil
import re
import shutil
import tempfile
from pathlib import Path
from textwrap import dedent
from typing import Any
from typing import Dict
from typing import List
from typing import Optional

# We're using %-style formatting everywhere because it's more convenient for
# building Python and Bourne Shell source code. We'll build some helpers to
# make it just a bit more like f-strings.


class FormatMapping:
    """Map strings such that %(foo.bar)s works in %-format strings"""

    def __init__(self, mapping):
        self.mapping = mapping

    def __getitem__(self, key):
        parts = key.split(".")
        obj = self.mapping[parts[0]]
        for p in parts[1:]:
            obj = getattr(obj, p)
        return obj


def F(s, values):
    values = FormatMapping(values)
    return s % values


class TemplateContext:
    def __init__(self):
        self.locals = {}
        self.globals = {
            "__builtins__": __builtins__,
        }

    def update(self, other):
        self.locals.update(other)

    def update_globals(self, other):
        self.globals.update(other)

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
    except Exception as e:
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


def remove_path(p):
    if os.path.islink(p) or not os.path.isdir(p):
        os.unlink(p)
    else:
        shutil.rmtree(p)


def symlink(src, dst):
    if os.path.exists(dst):
        os.unlink(dst)
    os.symlink(src, dst)


def make_launcher(src, dst):
    with overwrite_file(dst, perms=0o755) as fp:
        fp.write(
            dedent(
                F(
                    """\
            #!/bin/sh
            exec %(src)s "$@"
            """,
                    locals(),
                )
            )
        )


def fixup_shebang(src):
    """Alter the shebang line if it's too long, as can happen somethings with
    e.g., Jenkins. This trick is taken from what pip does."""
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
        F(
            """\
        #!/bin/sh
        '''exec' %(interp)s $0 "$@"
        '''
        """,
            locals(),
        )
    )
    return preamble + src[end:]


def install_script(name, dst, context=None, perms=0o755):
    srcname = os.path.join("scripts", name)
    src = pkgutil.get_data(__package__, srcname)
    if context is not None:
        src = context.expand(src.decode())
    src = fixup_shebang(src)
    mkdir_if_needed(os.path.dirname(dst))

    with overwrite_file(dst, perms=perms) as fp:
        fp.write(src)


def find_sysconfig_data(
    paths: List[os.PathLike], given_file: Optional[os.PathLike] = None
) -> Dict[str, Any]:
    pattern = "_sysconfigdata_*.py*"
    maybe = []
    for path in paths:
        maybe.extend(Path(path).glob(pattern))

    if given_file:
        sysconfig_paths = [given_file]
    else:
        found = set()
        for filename in maybe:
            if os.path.isfile(filename) and os.path.splitext(filename)[1] in (
                ".py",
                ".pyc",
            ):
                found.add(filename)

        # Multiples can happen, but so long as they all have the same
        # info we should be okay. Seen in buildroot
        # When choosing the correct one, prefer, in order:
        #   1) The .py file
        #   2) The .pyc file
        #   3) Any .opt-*.pyc files
        # so sort by the length of the longest extension
        sysconfig_paths = sorted(found, key=lambda x: len(str(x).split(".", 1)[1]))

    target_sysconfigdata = None
    target_sysconfigdata_file = None
    for path in sysconfig_paths:
        basename = os.path.basename(path)
        name, _ = os.path.splitext(basename)
        spec = importlib.util.spec_from_file_location(name, path)
        syscfg = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(syscfg)
        if target_sysconfigdata is None:
            target_sysconfigdata = syscfg
            target_sysconfigdata_file = path
        elif target_sysconfigdata.build_time_vars != syscfg.build_time_vars:
            raise ValueError(
                f"Malformed Python installation: Conflicting build info in {target_sysconfigdata_file} and {path}"
            )
    if not target_sysconfigdata:
        path_strs = [str(p) for p in sysconfig_paths]
        raise FileNotFoundError(
            f"No {pattern} found in target paths. Looked in {', '.join(path_strs)}"
        )

    return target_sysconfigdata.build_time_vars
