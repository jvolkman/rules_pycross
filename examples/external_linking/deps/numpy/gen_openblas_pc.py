import json
import os
from pathlib import Path

bazel_root = Path(os.environ["PYCROSS_BAZEL_ROOT"])

openblas_lib = Path(os.environ["OPENBLAS_LIB"])
openblas_include = Path(os.environ["OPENBLAS_INCLUDE"])

# We are in sdist directory. Let's create a pkgconfig directory.
pkgconfig_dir = Path("pkgconfig")
pkgconfig_dir.mkdir(exist_ok=True)

# Resolve absolute paths to openblas lib and include
abs_openblas_lib = (bazel_root / openblas_lib).resolve()
abs_openblas_include = (bazel_root / openblas_include).resolve()

# Write openblas.pc
openblas_pc = f"""\
prefix=
libdir={abs_openblas_lib.parent}
includedir={abs_openblas_include}

Name: openblas
Description: OpenBLAS
Version: 0.3.20
Libs: -L${{libdir}} -lopenblas
Cflags: -I${{includedir}}
"""

with open(pkgconfig_dir / "openblas.pc", "w") as f:
    f.write(openblas_pc)

# Update build env to include PKG_CONFIG_PATH
env_file = os.environ.get("PYCROSS_ENV_VARS_FILE")
if env_file:
    with open(env_file, "r") as f:
        env_vars = json.load(f)

    abs_pkgconfig_dir = pkgconfig_dir.resolve()

    existing_pc_path = env_vars.get("PKG_CONFIG_PATH", "")
    if existing_pc_path:
        env_vars["PKG_CONFIG_PATH"] = f"{abs_pkgconfig_dir}{os.pathsep}{existing_pc_path}"
    else:
        env_vars["PKG_CONFIG_PATH"] = str(abs_pkgconfig_dir)

    with open(env_file, "w") as f:
        json.dump(env_vars, f)

# Update config settings to pass meson arguments
config_file = os.environ.get("PYCROSS_CONFIG_SETTINGS_FILE")
if config_file:
    with open(config_file, "r") as f:
        config_settings = json.load(f)

    setup_args = config_settings.get("setup-args", [])
    setup_args.extend(
        [
            "-Dblas=openblas",
            "-Dlapack=openblas",
        ]
    )
    config_settings["setup-args"] = setup_args
    config_settings["build-dir"] = "build"

    with open(config_file, "w") as f:
        json.dump(config_settings, f)
