"""
Tools to guess environment markers given a tag.

See https://peps.python.org/pep-0508/#environment-markers
"""
from packaging.tags import Tag
import re
from typing import Dict

def normalize_os(tag: Tag) -> str:
    if tag.platform.startswith("linux"):
        return "linux"
    elif tag.platform.startswith("manylinux"):
        return "linux"
    elif tag.platform.startswith("macos"):
        return "darwin"
    elif tag.platform.startswith("win"):
        return "windows"
    else:
        return ""

def normalize_arch(tag: Tag) -> str:
    if "x86_64" in tag.platform:
        return "x86_64"
    elif "amd64" in tag.platform:
        return "x86_64"
    elif "aarch64" in tag.platform:
        return "aarch64"
    elif "arm64" in tag.platform:
        return "aarch64"
    elif "x86" in tag.platform:
        return "x86"
    elif "i386" in tag.platform:
        return "x86"
    elif "i686" in tag.platform:
        return "x86"
    elif tag.platform == "win32":
        return "x86"
    else:
        return ""

def guess_os_name(tag: Tag) -> str:
    return {
        "linux": "posix",
        "darwin": "posix",
        "windows": "nt",
    }.get(normalize_os(tag), "")


def guess_sys_platform(tag: Tag) -> str:
    return {
        "linux": "linux",
        "darwin": "darwin",
        "windows": "win32",
    }.get(normalize_os(tag), "")


def guess_platform_machine(tag: Tag) -> str:
    normal_os = normalize_os(tag)
    if normal_os == "linux":
        return {
            "aarch64": "aarch64",
            "x86": "i386",
            "x86_64": "x86_64",
        }.get(normalize_arch(tag), "")
    elif normal_os == "darwin":
        return {
            "aarch64": "arm64",
            "x86_64": "x86_64",
        }.get(normalize_arch(tag), "")
    elif normal_os == "windows":
        return {
            "x86": "i386",
            "x86_64": "x86_64",
        }


def guess_platform_python_implementation(tag: Tag) -> str:
    # See https://peps.python.org/pep-0425/#python-tag
    abbrev = tag.interpreter[:2]
    return {
        "py": "Generic Python",
        "cp": "CPython",
        "ip": "IronPython",
        "pp": "PyPy",
        "jy": "Jython",
    }.get(abbrev, "")


def guess_platform_release(tag: Tag) -> str:
    # Not possible from a tag.
    return ""


def guess_platform_system(tag: Tag) -> str:
    return {
        "linux": "Linux",
        "darwin": "Darwin",
        "windows": "Windows",
    }.get(normalize_os(tag), "")


def guess_platform_version(tag: Tag) -> str:
    # Not possible from a tag.
    return ""


def guess_python_version(tag: Tag) -> str:
    m = re.match("[a-z_]+([0-9]+)", tag.interpreter)
    if not m:
        return ""

    version = m.group(1)
    if len(version) == 1:
        return f"{version}.0"  # Not great, but we're lacking info.
    else:
        return f"{version[0]}.{version[1:]}"


def guess_python_full_version(tag: Tag) -> str:
    version = guess_python_version(tag)
    if not version:
        return ""

    return version + ".0"  # Not much else we can do.


def guess_implementation_name(tag: Tag) -> str:
    # See https://peps.python.org/pep-0425/#python-tag
    abbrev = tag.interpreter[:2]
    return {
        "py": "python",
        "cp": "cpython",
        "ip": "ironpython",
        "pp": "pypy",
        "jy": "jython",
    }.get(abbrev, "")


def guess_implementation_version(tag: Tag) -> str:
    return guess_python_full_version(tag)


def guess_environment_markers(tag: Tag) -> Dict[str, str]:
    return {
        "os_name": guess_os_name(tag),
        "sys_platform": guess_sys_platform(tag),
        "platform_machine": guess_platform_machine(tag),
        "platform_python_implementation": guess_platform_python_implementation(tag),
        "platform_release": guess_platform_release(tag),
        "platform_system": guess_platform_system(tag),
        "platform_version": guess_platform_version(tag),
        "python_version": guess_python_version(tag),
        "python_full_version": guess_python_full_version(tag),
        "implementation_name": guess_implementation_name(tag),
        "implementation_version": guess_implementation_version(tag),
    }
