"""Implementation of the pycross_lock_repo rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")

def get_venv_site_path(venv_path):
    """
    Find and return the site-packages path under venv_path.

    Args:
      venv_path: the virtual env path.

    Returns:
      The site-packages path.
    """

    # First, try windows.
    site_path = venv_path.get_child("Lib", "site-packages")
    if site_path.exists:
        return site_path

    # If that doesn't work, try posix: lib/python3.X/site-packages
    lib_path = venv_path.get_child("lib")
    if not lib_path.exists:
        fail("Cannot find lib path")

    # We don't know the Python version, so we just find a directory that starts with "python".
    python_path = None
    for child in lib_path.readdir():
        if child.basename.startswith("python"):
            python_path = child
    if not python_path:
        fail("Cannot find python path")

    site_path = python_path.get_child("site-packages")
    if not site_path.exists:
        fail("Cannot find site-packages path")

    return site_path

def get_venv_python_executable(venv_path):
    """
    Find and return the python executable under venv_path.

    Args:
      venv_path: the virtual env path.

    Returns:
      The python executable path.
    """

    # posix
    python_exe = venv_path.get_child("bin", "python")
    if python_exe.exists:
        return python_exe

    # windows
    python_exe = venv_path.get_child("Scripts", "python.exe")
    if python_exe.exists:
        return python_exe

    fail("Unable to find the python executable")

_venv_build = """\
package(default_visibility = ["//visibility:public"])

alias(
    name = "python",
    actual = "{venv_python_exe}",
)
"""

def create_venv(rctx, python_executable, venv_path, path_entries = []):
    """
    Create a virtual environment.

    The environment will have a BUILD file with a `python` target pointing to the python executable.

    Args:
      rctx: the repository_context.
      python_executable: the python_executable to use.
      venv_path: the path to the environment to create, relative to the repository.
      path_entries: optional list of PYTHONPATH entries to add.

    Returns:
      A struct containing
        python_executable: the path to the python executable within the environment
        site_path: the path to the `site-packages` directory
    """
    venv_path = rctx.path(venv_path)
    venv_args = [
        str(python_executable),
        "-m",
        "venv",
        "--without-pip",
        str(venv_path),
    ]
    result = rctx.execute(venv_args)
    if result.return_code:
        fail("venv creation exited with {}".format(result.return_code()))

    if not venv_path.exists:
        fail("Failed to create virtual environment.")

    exe_path = get_venv_python_executable(venv_path)
    site_path = get_venv_site_path(venv_path)

    if path_entries:
        pth_text = "\n".join([str(entry) for entry in path_entries]) + "\n"
        rctx.file(site_path.get_child("path.pth"), pth_text)

    relative_exe_path = paths.relativize(str(exe_path), str(venv_path))
    rctx.file(venv_path.get_child("BUILD.bazel"), _venv_build.format(venv_python_exe = relative_exe_path))

    return struct(
        python_executable = exe_path,
        site_path = site_path,
    )

def install_venv_wheels(rctx, venv_path, pip_whl, wheels):
    """
    Install wheels into the virtual env.

    Args:
      rctx: the repository_context.
      venv_path: the path to the environment to create, relative to the repository.
      pip_whl: the path to a `pip` wheel used to install other wheels.
      wheels: the wheels to install.
    """
    venv_path = rctx.path(venv_path)
    python_exe = get_venv_python_executable(venv_path)
    env = dict(PYTHONPATH = str(rctx.path(pip_whl)))
    wheel_paths = [str(rctx.path(wheel)) for wheel in wheels]
    result = rctx.execute([
        str(python_exe),
        "-m",
        "pip",
        "install",
    ] + wheel_paths, environment = env)
    if result.return_code:
        fail("wheel install failed: {}".format(result.stderr))
