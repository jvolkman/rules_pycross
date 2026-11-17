import ctypes
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_INCLUDE_DIR = _HERE / "include"
_LIB_DIR = _HERE / "lib"

_lib = ctypes.CDLL(str(_LIB_DIR / "libfoo.so"))
_lib.foo_value.restype = ctypes.c_int
_lib.foo_inc.restype = ctypes.c_int
_lib.foo_counter_addr.restype = ctypes.c_void_p


def include_dir() -> str:
    return str(_INCLUDE_DIR)


def lib_dir() -> str:
    return str(_LIB_DIR)


def value() -> int:
    return _lib.foo_value()


def inc() -> int:
    return _lib.foo_inc()


def counter_addr() -> int:
    return _lib.foo_counter_addr()
