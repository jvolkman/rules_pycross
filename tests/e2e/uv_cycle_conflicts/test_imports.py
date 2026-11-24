import importlib
import importlib.metadata as md
import sys


def main():
    want, mods = sys.argv[1], sys.argv[2].split(",")
    for mod in mods:
        importlib.import_module(mod)
    if want != "any":
        got = md.version("iniconfig")
        assert got == want, (got, want)


if __name__ == "__main__":
    main()
