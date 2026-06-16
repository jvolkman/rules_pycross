"""Simple test: import a module by name."""

import importlib
import sys

if __name__ == "__main__":
    module_name = sys.argv[1]
    mod = importlib.import_module(module_name)
    print(f"Successfully imported {module_name}: {mod}")
