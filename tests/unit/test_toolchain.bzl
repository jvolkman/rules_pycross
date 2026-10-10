"""Tests for pycross/toolchain.bzl helpers."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("//pycross:toolchain.bzl", "is_compile_interpreter_path_for_testing")

def _subject(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])

# buildifier: disable=unused-variable
def _test_compile_interpreter_path_filter_impl(env, target):
    kept = [
        "bin/python3",
        "bin/python3.11",
        "lib/libpython3.11.so.1.0",
        "lib/python3.11/os.py",
        "lib/python3.11/encodings/utf_8.py",
        "lib/python3.11/lib-dynload/_struct.cpython-311-x86_64-linux-gnu.so",
        "../python_3_11_x86_64-unknown-linux-gnu/lib/python3.11/os.py",
        "Lib/os.py",
        "Lib/encodings/utf_8.py",
    ]
    for p in kept:
        env.expect.that_bool(is_compile_interpreter_path_for_testing(p)).equals(True)

    excluded = [
        "lib/python3.11/site-packages/pip/__init__.py",
        "../python_3_11_x86_64-unknown-linux-gnu/lib/python3.11/site-packages/setuptools/__init__.py",
        "lib/tcl8.6/init.tcl",
        "lib/tk8.6/tk.tcl",
        "lib/Tix8.4.3/Tix.tcl",
        "include/python3.11/Python.h",
        "lib/python3.11/idlelib/idle.py",
        "lib/python3.11/lib2to3/main.py",
        "lib/python3.11/distutils/core.py",
        "lib/python3.11/turtledemo/__main__.py",
        "lib/python3.11/tkinter/__init__.py",
        "lib/python3.11/test/support/__init__.py",
        "lib/python3.11/ensurepip/__init__.py",
        "lib/python3.11/config-3.11-x86_64-linux-gnu/libpython3.11.a",
        "Include/Python.h",
        "tcl/tcl8.6/init.tcl",
        "Lib/site-packages/pip/__init__.py",
        "Lib/idlelib/idle.py",
        "Lib/test/support/__init__.py",
    ]
    for p in excluded:
        env.expect.that_bool(is_compile_interpreter_path_for_testing(p)).equals(False)

def _test_compile_interpreter_path_filter(name):
    _subject(name)
    analysis_test(name = name, target = name + "_subject", impl = _test_compile_interpreter_path_filter_impl)

def toolchain_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_compile_interpreter_path_filter,
        ],
    )
