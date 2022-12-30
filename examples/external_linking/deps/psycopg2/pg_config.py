import os
import sys
from pathlib import Path
from typing import Optional

PG_VERSION_DEFINE = "#define PG_VERSION "

def query(arg: str) -> Optional[str]:
    build_root = Path(os.environ["PYCROSS_BUILD_ROOT"])
    lib_dir = build_root / "lib"

    # Search for the actual postgresql include path.
    include_paths = [Path(p) for p in os.environ["PYCROSS_INCLUDE_PATH"].split(":")]
    for p in include_paths:
        if (p / "pg_config.h").is_file():
            include_dir = p
            if (include_dir / "server").is_dir():
                server_include_dir = include_dir / "server"
            elif (include_dir / "postgresql/server").is_dir():
                server_include_dir = include_dir / "postgresql/server"
            break
    else:
        # We didn't find it, so just set the include dir to the one in our work environment.
        include_dir = build_root / "include"
        server_include_dir = include_dir

    if arg == "libdir":
        return str(lib_dir)

    elif arg == "includedir":
        return str(include_dir)

    elif arg == "includedir-server":
        return str(server_include_dir)

    elif arg == "ldflags":
        return f"-L{lib_dir}"
    
    elif arg == "cppflags":
        return "none"

    elif arg == "version":
        config_file = include_dir / "pg_config.h"
        if not config_file.is_file():
            return "PostgreSQL 0.0"
        with open(config_file) as f:
            for line in f:
                line = line.strip()
                if line.startswith(PG_VERSION_DEFINE):
                    version_str = line[len(PG_VERSION_DEFINE):]
                    version_str = version_str.strip('"')  # Remove quotes
                    return f"PostgreSQL {version_str}"


def main():
    response = None
    if len(sys.argv) > 1 and sys.argv[1].startswith("--"):
        response = query(sys.argv[1][2:])

    if not response:
        print("unknown")
        sys.exit(1)

    print(response)


if __name__ == "__main__":
    main()
