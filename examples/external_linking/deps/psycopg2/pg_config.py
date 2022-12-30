import os
import sys
from pathlib import Path
from typing import Optional

PG_VERSION_DEFINE = "#define PG_VERSION "

build_root = Path(os.environ["PYCROSS_BUILD_ROOT"])
lib_dir = build_root / "lib"
include_dir = build_root / "include"

def query(arg: str) -> Optional[str]:
    if arg == "libdir":
        return str(lib_dir)

    elif arg == "includedir":
        return str(include_dir)

    elif arg == "includedir-server":
        return str(include_dir / "server")

    elif arg == "ldflags":
        return f"-L{lib_dir}"
    
    elif arg == "cppflags":
        return "none"

    elif arg == "version":
        return f"PostgreSQL 15.1"
        # with open(include_dir / "pg_config.h") as f:
        #     for line in f:
        #         line = line.strip()
        #         if line.startswith(PG_VERSION_DEFINE):
        #             version_str = line[len(PG_VERSION_DEFINE):]
        #             version_str = version_str.strip('"')  # Remove quotes
        #             return f"PostgreSQL {version_str}"


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
