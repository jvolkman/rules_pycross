import os
import sys
from pathlib import Path
from typing import Optional

PG_VERSION_DEFINE = "#define PG_VERSION "

postgresql_prefix = Path(os.environ["POSTGRESQL_PREFIX"])
ldpath = os.environ["LD_LIBRARY_PATH"]
lib_dir = postgresql_prefix / "lib"
include_dir = postgresql_prefix / "include"

def query(arg: str) -> Optional[str]:
    if arg == "libdir":
        return str(lib_dir)

    elif arg == "includedir":
        return str(include_dir)

    elif arg == "includedir-server":
        return str(include_dir / "server")

    elif arg == "ldflags":
        flags = [f"-L{path}" for path in ldpath.split(":")]
        return " ".join(flags)
    
    elif arg == "cppflags":
        return "none"

    elif arg == "version":
        with open(include_dir / "pg_config.h") as f:
            for line in f:
                line = line.strip()
                if line.startswith(PG_VERSION_DEFINE):
                    version_str = line[len(PG_VERSION_DEFINE):]
                    version_str = version_str.strip('"')  # Remove quotes
                    return f"PostgreSQL {version_str}"


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else None
    response = None
    if len(sys.argv) > 1 and sys.argv[1].startswith("--"):
        response = query(sys.argv[1][2:])

    if not response:
        print("unknown")
        sys.exit(1)

    print(response, file=sys.stderr)
    print(response)


if __name__ == "__main__":
    main()
