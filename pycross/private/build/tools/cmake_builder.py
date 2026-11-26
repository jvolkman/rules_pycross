"""CMake / scikit-build-core PEP 517 builder."""

import os
import sys
from pathlib import Path

from pycross.private.build.tools.utils.cc_toolchain import join_flags
from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import load_layers
from pycross.private.build.tools.utils.lifecycle import BackendStrategy
from pycross.private.build.tools.utils.lifecycle import run_standard_build_lifecycle


def _cmake_escape(value: str) -> str:
    """Escape a string for use inside CMake's set() double-quoted arguments.

    CMake interprets backslashes and semicolons specially inside quoted strings.
    Semicolons are CMake list separators and must be escaped.
    """
    return value.replace("\\", "\\\\").replace('"', '\\"').replace(";", "\\;")


def generate_toolchain_file(ctx: BuildContext, cc_config: dict) -> None:
    cc_layer = ctx.cc_layer
    if cc_layer is None or not cc_layer.cc_path or not cc_layer.cxx_path:
        raise ValueError(
            "CC and CXX must be provided by the Bazel CC toolchain. Ensure a cc_layer is configured for this build."
        )
    cc = str(cc_layer.cc_path)
    cxx = str(cc_layer.cxx_path)
    cflags = _cmake_escape(join_flags(cc_layer.cflags))
    cxxflags = _cmake_escape(join_flags(cc_layer.cxxflags))
    ldflags = _cmake_escape(join_flags(cc_layer.ldflags))

    # Determine system and processor
    target_system = cc_config.get("target_os", "Linux")
    cmake_system_name = {
        "darwin": "Darwin",
        "linux": "Linux",
        "windows": "Windows",
    }.get(target_system, target_system.capitalize())

    cmake_system_processor = cc_config.get("target_cpu", "x86_64")
    if target_system == "darwin" and cmake_system_processor == "aarch64":
        cmake_system_processor = "arm64"

    # CMake does not support passing flags in CMAKE_AR directly without
    # additional workarounds. We extract just the binary path and drop flags.
    ar_path = Path(cc_layer.ar_list[0]) if cc_layer.ar_list else None
    ranlib_path = cc_layer.ranlib_path

    layer_dir = ctx.temp_dir / "cc_layer"
    layer_lib_dir = cc_layer.layer_lib_dir
    include_paths = [_cmake_escape(inc_dir.as_posix()) for inc_dir in cc_layer.include_dirs]

    # Write the toolchain file
    toolchain_lines = [
        f"set(CMAKE_SYSTEM_NAME {cmake_system_name})",
        f"set(CMAKE_SYSTEM_PROCESSOR {cmake_system_processor})",
        "",
        f'set(CMAKE_C_COMPILER "{_cmake_escape(cc)}")',
        f'set(CMAKE_CXX_COMPILER "{_cmake_escape(cxx)}")',
    ]

    if ar_path:
        toolchain_lines.append(f'set(CMAKE_AR "{_cmake_escape(ar_path.as_posix())}" CACHE STRING "" FORCE)')
    if ranlib_path:
        toolchain_lines.append(f'set(CMAKE_RANLIB "{_cmake_escape(ranlib_path.as_posix())}" CACHE STRING "" FORCE)')

    toolchain_lines.extend(
        [
            "",
            f'set(CMAKE_C_FLAGS_INIT "{cflags}")',
            f'set(CMAKE_CXX_FLAGS_INIT "{cxxflags}")',
            "",
            f'set(CMAKE_EXE_LINKER_FLAGS_INIT "{ldflags}")',
            f'set(CMAKE_SHARED_LINKER_FLAGS_INIT "{ldflags}")',
            f'set(CMAKE_MODULE_LINKER_FLAGS_INIT "{ldflags}")',
            "",
            f'list(PREPEND CMAKE_LIBRARY_PATH "{_cmake_escape(layer_lib_dir.absolute().as_posix())}")',
        ]
    )
    if include_paths:
        include_path_args = " ".join(f'"{p}"' for p in include_paths)
        toolchain_lines.append(f"list(PREPEND CMAKE_INCLUDE_PATH {include_path_args})")
    toolchain_lines.extend(
        [
            "",
            "# Disable stripping during CMake installation step because the host",
            "# strip utility cannot handle cross-compiled binaries (e.g. Mach-O).",
            "# Bazel/rules_pycross handles stripping separately if needed.",
            'set(CMAKE_STRIP "true" CACHE STRING "" FORCE)',
            "",
            "# Normalize shared library permissions across platforms. Without this,",
            "# macOS builds install .so files with the execute bit (0755) while",
            "# Linux/Debian builds strip it (0644), breaking wheel reproducibility.",
            'set(CMAKE_INSTALL_SO_NO_EXE 1 CACHE BOOL "" FORCE)',
        ]
    )

    toolchain_content = "\n".join(toolchain_lines) + "\n"

    toolchain_path = layer_dir / "CMakeToolchain.txt"
    toolchain_path.parent.mkdir(parents=True, exist_ok=True)
    toolchain_path.write_text(toolchain_content)

    # scikit-build-core respects the CMAKE_ARGS env var and forwards its
    # contents to every cmake invocation it makes.
    existing_cmake_args = ctx.build_env.get("CMAKE_ARGS", "")
    new_cmake_args = f"-DCMAKE_TOOLCHAIN_FILE={toolchain_path.absolute()}"
    ctx.build_env["CMAKE_ARGS"] = f"{existing_cmake_args} {new_cmake_args}".strip()


def pre_build(ctx: BuildContext) -> None:
    # 1. Provide CMake toolchain file for cross-compilation and compiler injection
    cc_layer_config = next((m for m in load_layers(ctx) if "CC" in m), None)
    if ctx.cc_layer and cc_layer_config:
        generate_toolchain_file(ctx, cc_layer_config)

    # 2. Setup CMAKE_PREFIX_PATH so CMake's find_package() can locate packages
    # installed in build_deps (like pybind11).
    # scikit-build-core auto-adds sysconfig site-packages, but our build_deps
    # are unzipped wheel directories added to PYTHONPATH — not real installs.
    #
    # We add both the site-packages directories AND the individual package
    # subdirectories as prefixes.  CMake's find_package() searches for config
    # files at <prefix>/<name>*/ and <prefix>/share/<name>*/ — but only when
    # <prefix> is the package root, not the site-packages parent.  For example
    # pybind11 ships its cmake config at:
    #   <site-packages>/pybind11/share/cmake/pybind11/pybind11Config.cmake
    # so we need <site-packages>/pybind11 on CMAKE_PREFIX_PATH.
    prefix_paths = []
    for p in ctx.python_paths:
        prefix_paths.append(str(p.absolute()))
        # Add top-level package directories (skip dist-info metadata dirs).
        if p.is_dir():
            for child in p.iterdir():
                if child.is_dir() and not child.name.endswith(".dist-info"):
                    prefix_paths.append(str(child.absolute()))

    existing_prefix_path = ctx.build_env.get("CMAKE_PREFIX_PATH", "")
    if existing_prefix_path:
        prefix_paths.append(existing_prefix_path)

    # When CMAKE_PREFIX_PATH is set as an environment variable, CMake reads it
    # using the platform-native path separator (: on Unix, ; on Windows).
    ctx.build_env["CMAKE_PREFIX_PATH"] = os.pathsep.join(prefix_paths)


def main():
    strategy = BackendStrategy(
        pre_build=pre_build,
        export_cc_env=False,
    )
    run_standard_build_lifecycle(sys.argv[1], strategy)


if __name__ == "__main__":
    main()
