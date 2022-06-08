import dataclasses
import json
import os
import platform
import pprint
import sys
import sysconfig
from pathlib import Path
from typing import Any
from typing import Dict
from typing import List
from typing import Optional

from . import utils

SYSCONFIG_DATA_NAME = "_pycross_sysconfig_data"


@dataclasses.dataclass
class Uname:
    machine: str
    release: str
    sysname: str


@dataclasses.dataclass
class TargetContext:
    abiflags: Optional[str]
    effective_glibc: Optional[str]
    home: str
    macosx_deployment_target: Optional[str]
    manylinux_tags: List[str]
    multiarch: Optional[str]
    platform: str  # e.g. apple-aarch64
    project_base: str  # bin dir of target executable
    sysconfigdata_name: str
    sysconfigdata_path: str
    sysconfig_platform: str  # e.g. apple-x86_64
    uname_machine: str  # from uname; e.g. x86_64
    uname_release: str  # from uname
    uname_sysname: str  # from uname


@dataclasses.dataclass
class Context:
    exec_python_executable: str  # The exec python
    exec_stdlib: str  # e.g. .../lib/python3.9
    lib_path: str  # Where our patching scripts are written (i.e., venv/lib)
    target: TargetContext


def guess_target_platform(host_gnu_type: str) -> str:
    # It was probably natively compiled, but not necessarily for this
    # architecture. Guess from HOST_GNU_TYPE.
    # TODO: Handle windows somehow (ha, ha)
    host = host_gnu_type.lower().split("-")
    if len(host) == 4:  # i.e., aarch64-unknown-linux-gnu
        plat, machine = [host[2], host[0]]
    elif len(host) == 3:  # i.e., aarch64-linux-gnu, unlikely.
        plat, machine = [host[1], host[0]]
    else:
        raise ValueError(
            f"Cannot determine target platform from HOST_GNU_TYPE: {host_gnu_type}"
        )

    if plat == "apple":
        plat = "darwin"

    return f"{plat}-{machine}"


def guess_uname(
    target_platform: str,
    host_gnu_type: str,
    uname_machine: Optional[str],
    macosx_deployment_target: Optional[str],
) -> Uname:
    uname_release = "0.0.0"
    uname_sysname = ""

    # target_platform is _probably_ something like linux-x86_64, but it can
    # vary.
    target_info = target_platform.split("-")
    if not target_info:
        uname_sysname = sys.platform
    elif len(target_info) >= 1:
        uname_sysname = target_info[0]

    if uname_machine is None:
        if len(target_info) > 1 and target_info[-1] == "powerpc64le":
            # Test that this is still a special case when we can.
            # On uname.machine=ppc64le, _PYTHON_HOST_PLATFORM is linux-powerpc64le
            uname_machine = "ppc64le"
        else:
            uname_machine = host_gnu_type.split("-")[0]

    if macosx_deployment_target:
        try:
            major, minor = macosx_deployment_target.split(".")
            major, minor = int(major), int(minor)
        except ValueError:
            raise ValueError(
                f"Unexpected value {macosx_deployment_target} for MACOSX_DEPLOYMENT_TARGET"
            )
        if major == 10:
            uname_release = "%s.0.0" % (minor + 4)
        elif major == 11:
            uname_release = "%s.0.0" % (minor + 20)
        else:
            raise ValueError(
                f"Unexpected major version {major} for MACOSX_DEPLOYMENT_TARGET"
            )

    return Uname(machine=uname_machine, release=uname_release, sysname=uname_sysname)


def guess_sysconfig_platform(
    uname: Uname, target_platform: str, macosx_deployment_target: Optional[str]
) -> str:
    if uname.sysname.lower() == "darwin":
        return "macosx-{}-{}".format(
            macosx_deployment_target,
            uname.machine,
        )
    elif uname.sysname == "linux":
        # Use self.host_machine here as powerpc64le gets converted
        # to ppc64le in self.host_machine
        return f"linux-{uname.machine}"
    else:
        return target_platform


def build_context(
    target_python_exe: str,
    lib_path: str,
    sysconfig_vars: Dict[str, Any],
    sysconfig_data_file: str,
    manylinux_tags: List[str],
    target_platform: Optional[str],
    uname_machine: Optional[str],
) -> Context:
    project_base = Path(target_python_exe).absolute().parent
    home = project_base.parent  # Not sure if this is always correct

    host_gnu_type = sysconfig_vars["HOST_GNU_TYPE"]
    macosx_deployment_target = sysconfig_vars.get("MACOSX_DEPLOYMENT_TARGET")

    if target_platform is None:
        target_platform = guess_target_platform(host_gnu_type)

    target_uname = guess_uname(
        target_platform=target_platform,
        host_gnu_type=host_gnu_type,
        uname_machine=uname_machine,
        macosx_deployment_target=macosx_deployment_target,
    )

    target_sysconfig_platform = guess_sysconfig_platform(
        uname=target_uname,
        target_platform=target_platform,
        macosx_deployment_target=macosx_deployment_target,
    )

    target_context = TargetContext(
        abiflags=sysconfig_vars.get("ABIFLAGS"),
        effective_glibc="TODO",  # TODO
        home=str(home),
        macosx_deployment_target=macosx_deployment_target,
        manylinux_tags=manylinux_tags,
        multiarch=sysconfig_vars.get("MULTIARCH"),
        platform=target_platform,
        project_base=str(project_base),
        sysconfigdata_name=SYSCONFIG_DATA_NAME,
        sysconfigdata_path=sysconfig_data_file,
        sysconfig_platform=target_sysconfig_platform,
        uname_machine=target_uname.machine,
        uname_release=target_uname.release,
        uname_sysname=target_uname.sysname,
    )

    context = Context(
        exec_python_executable=os.path.abspath(sys.executable),
        exec_stdlib=os.path.abspath(os.path.dirname(os.__file__)),
        lib_path=lib_path,
        target=target_context,
    )

    return context


def expand_manylinux_tags(tags: List[str]) -> List[str]:
    """
    Convert legacy manylinux tags to PEP600, because pip only looks for one
    or the other
    """

    manylinux_tags = set(tags)
    extra_tags = set()

    # we'll be very strict here: don't assume that manylinux2014 implies
    # manylinux1 and so on.
    if "manylinux1" in manylinux_tags:
        extra_tags.add("manylinux_2_5")
    if "manylinux2010" in manylinux_tags:
        extra_tags.add("manylinux_2_12")
    if "manylinux2014" in manylinux_tags:
        extra_tags.add("manylinux_2_17")
    if "manylinux_2_5" in manylinux_tags:
        extra_tags.add("manylinux1")
    if "manylinux_2_12" in manylinux_tags:
        extra_tags.add("manylinux2010")
    if "manylinux_2_17" in manylinux_tags:
        extra_tags.add("manylinux2014")

    manylinux_tags.update(extra_tags)
    return sorted(manylinux_tags)


def write_sysconfig_data(
    sysconfig_data_path: Path, sysconfig_vars: Dict[str, Any]
) -> None:
    with open(sysconfig_data_path, "w") as f:
        f.write("# Generated by rules_pycross\n")
        f.write("build_time_vars = ")
        pprint.pprint(sysconfig_vars, stream=f, compact=True)


def write_pyvenv_cfg(env_path: Path, target_bin: str) -> None:
    with open(env_path / "pyvenv.cfg", "w") as f:
        f.writelines(
            [
                f"home = {target_bin}\n",
                "include-system-site-packages = false\n",
                f"version = {platform.python_version()}\n",
            ]
        )


def build_env(
    env_path: str,
    target_python_exe: str,
    sysconfig_vars: Dict[str, Any],
    manylinux_tags: List[str],
) -> Path:
    pyver = "python" + sysconfig.get_config_var("py_version_short")
    env_path = Path(env_path)
    lib_path = env_path / "lib"
    site_path = lib_path / pyver / "site-packages"
    bin_path = env_path / "bin"
    exe = bin_path / pyver
    sysconfig_data_file = site_path / (SYSCONFIG_DATA_NAME + ".py")

    bin_path.mkdir(parents=True)
    lib_path.mkdir(parents=True)
    site_path.mkdir(parents=True)

    write_sysconfig_data(sysconfig_data_file, sysconfig_vars)
    context = build_context(
        target_python_exe=target_python_exe,
        lib_path=str(lib_path),
        sysconfig_vars=sysconfig_vars,
        sysconfig_data_file=str(sysconfig_data_file),
        manylinux_tags=expand_manylinux_tags(manylinux_tags),
        target_platform=None,  # guess
        uname_machine=None,  # guess
    )

    write_pyvenv_cfg(env_path, str(context.target.project_base))

    tmpl = utils.TemplateContext()
    tmpl.update(context.__dict__)
    utils.install_script("pywrapper.py.tmpl", str(exe), tmpl)

    # Everything in lib_path follows the same pattern
    site_scripts = [
        "site.py",
        "sys-patch.py",
        "os-patch.py",
        "platform-patch.py",
        "sysconfig-patch.py",
        "distutils-sysconfig-patch.py",
    ]

    for script in site_scripts:
        src = script + ".tmpl"
        dst = os.path.join(context.lib_path, script)
        utils.install_script(src, dst, tmpl)

    utils.install_script(
        "_manylinux.py.tmpl",
        os.path.join(str(site_path), "_manylinux.py"),
        tmpl,
    )

    # Symlink alternate names to our wrapper
    for link_name in ("python", "python3"):
        link = bin_path / link_name
        if not link.exists():
            link.symlink_to(exe)

    return env_path


def main():
    import argparse

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--sysconfig-json",
        help="A JSON file containing sysconfig data.",
    )
    parser.add_argument(
        "--manylinux",
        action="append",
        default=[],
        help="""Declare compatibility with the given manylinux platform tag to
                enable pre-compiled wheels. This argument may be given multiple
                times.""",
    )
    parser.add_argument(
        "--env-dir",
        help="Path to the created environment.",
    )
    parser.add_argument(
        "--target-python",
        help="Path to the target Python interpreter executable.",
    )

    args = parser.parse_args()

    with open(args.sysconfig_json, "r") as f:
        sysconfig_vars = json.load(f)

    build_env(
        env_path=args.env_dir,
        target_python_exe=args.target_python,
        sysconfig_vars=sysconfig_vars,
        manylinux_tags=args.manylinux,
    )
