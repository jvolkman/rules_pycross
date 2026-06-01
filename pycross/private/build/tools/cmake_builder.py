"""CMake / scikit-build-core PEP 517 builder."""

import os
import shlex
import sys
import textwrap

from pycross.private.build.tools.utils.context import BuildContext
from pycross.private.build.tools.utils.context import load_layers
from pycross.private.build.tools.utils.lifecycle import BackendStrategy
from pycross.private.build.tools.utils.lifecycle import run_standard_build_lifecycle
from pycross.private.build.tools.utils.venv_utils import build_crossenv_venv
from pycross.private.build.tools.utils.venv_utils import build_standard_venv
from pycross.private.build.tools.utils.context import replace_placeholder


def setup_venv(ctx: BuildContext) -> None:
    is_cross = ctx.exec_python != ctx.target_python
    if is_cross or ctx.bazel_config.get("always_use_crossenv"):
        build_crossenv_venv(ctx)
    else:
        build_standard_venv(ctx)


def generate_toolchain_file(ctx: BuildContext, cc_config: dict) -> None:
    def get_var(name: str, default_fallback: str = "") -> str:
        val = ctx.sysconfig_vars.get(name)
        if val is not None:
            return val
        if cc_config and name in cc_config:
            return replace_placeholder(ctx.prefix, cc_config[name])
        return default_fallback

    cc = get_var("CC")
    cxx = get_var("CXX")
    if not cc or not cxx:
        raise ValueError(
            "CC and CXX must be provided by the Bazel CC toolchain. Ensure a cc_layer is configured for this build."
        )
    cflags = get_var("CFLAGS", "").replace('"', '\\"')
    cxxflags = get_var("CXXFLAGS", "").replace('"', '\\"')
    ldflags = get_var("LDFLAGS", "").replace('"', '\\"')

    # Add runtime libs to ldflags
    runtime_libs = []
    if cc_config:
        for lib_path_str in cc_config.get("runtime_libs", []):
            runtime_libs.append(replace_placeholder(ctx.prefix, lib_path_str))
    
    if runtime_libs:
        ldflags = ldflags + " " + " ".join(runtime_libs)

    # Determine system and processor
    target_system = cc_config.get("target_os", "Linux")
    if target_system == "darwin":
        cmake_system_name = "Darwin"
    elif target_system == "linux":
        cmake_system_name = "Linux"
    elif target_system == "windows":
        cmake_system_name = "Windows"
    else:
        cmake_system_name = target_system.capitalize()

    cmake_system_processor = cc_config.get("target_cpu", "x86_64")

    # Write the toolchain file
    toolchain_content = textwrap.dedent(f"""\
        set(CMAKE_SYSTEM_NAME {cmake_system_name})
        set(CMAKE_SYSTEM_PROCESSOR {cmake_system_processor})

        set(CMAKE_C_COMPILER "{cc}")
        set(CMAKE_CXX_COMPILER "{cxx}")

        set(CMAKE_C_FLAGS "{cflags}" CACHE STRING "" FORCE)
        set(CMAKE_CXX_FLAGS "{cxxflags}" CACHE STRING "" FORCE)
        
        set(CMAKE_EXE_LINKER_FLAGS "{ldflags}" CACHE STRING "" FORCE)
        set(CMAKE_SHARED_LINKER_FLAGS "{ldflags}" CACHE STRING "" FORCE)
        set(CMAKE_MODULE_LINKER_FLAGS "{ldflags}" CACHE STRING "" FORCE)
        
        # Disable stripping during CMake installation step because the host
        # strip utility cannot handle cross-compiled binaries (e.g. Mach-O).
        # Bazel/rules_pycross handles stripping separately if needed.
        set(CMAKE_STRIP "true" CACHE STRING "" FORCE)
        """)

    toolchain_path = ctx.temp_dir / "cc_layer" / "CMakeToolchain.txt"
    toolchain_path.parent.mkdir(parents=True, exist_ok=True)
    toolchain_path.write_text(toolchain_content)

    # Pass the toolchain file to scikit-build-core (or scikit-build)
    # We can use SKBUILD_CMAKE_ARGS environment variable, or pass it via config_settings.
    # scikit-build-core accepts CMAKE_ARGS env var as well.
    existing_cmake_args = ctx.build_env.get("CMAKE_ARGS", "")
    new_cmake_args = f"-DCMAKE_TOOLCHAIN_FILE={toolchain_path.absolute()}"
    ctx.build_env["CMAKE_ARGS"] = f"{existing_cmake_args} {new_cmake_args}".strip()

    # We also need to strip CC/CXX/CFLAGS etc from the environment so CMake doesn't
    # mix toolchain file settings with environment overrides.
    for key in ["CC", "CXX", "CFLAGS", "CXXFLAGS", "LDFLAGS", "LDSHAREDFLAGS", "AR", "ARFLAGS"]:
        ctx.build_env.pop(key, None)


def pre_build(ctx: BuildContext) -> None:
    # 1. Provide CMake toolchain file for cross-compilation and compiler injection
    cc_layer_config = next((m for m in load_layers(ctx) if "CC" in m), None)
    if cc_layer_config:
        generate_toolchain_file(ctx, cc_layer_config)

    # 2. Setup CMAKE_PREFIX_PATH so CMake's find_package() can locate packages 
    # installed in build_deps (like pybind11). 
    # scikit-build-core auto-adds sysconfig site-packages, but our build_deps 
    # are unzipped wheels dynamically added to PYTHONPATH.
    prefix_paths = [str(p.absolute()) for p in ctx.python_paths]
    
    # Also add the individual package directories, as CMake packages are often
    # stored in `<site-packages>/<pkg_name>/share/cmake`
    for p in ctx.python_paths:
        for child in p.iterdir():
            if child.is_dir() and not child.name.endswith(".dist-info"):
                prefix_paths.append(str(child.absolute()))

    existing_prefix_path = ctx.build_env.get("CMAKE_PREFIX_PATH", "")
    all_prefix_paths = prefix_paths
    if existing_prefix_path:
        all_prefix_paths.append(existing_prefix_path)
    
    ctx.build_env["CMAKE_PREFIX_PATH"] = os.pathsep.join(all_prefix_paths)


def main():
    strategy = BackendStrategy(
        setup_venv=setup_venv,
        pre_build=pre_build,
    )
    run_standard_build_lifecycle(sys.argv[1], strategy)


if __name__ == "__main__":
    main()
