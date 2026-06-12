import os
import sys
from hooks import hook_dep

def main():
    print("Hello from Python pre-build hook!")
    print("Hook dep says:", hook_dep.hello())
    
    # Write a marker file to be bundled into the wheel
    init_py = "pkg/setproctitle/__init__.py"
    if os.path.exists(init_py):
        with open(init_py, "a") as f:
            f.write(f"\nPY_PRE_BUILD_HOOK_MARKER = \"{hook_dep.hello()}\"\n")
        print("Wrote marker to", init_py)
    else:
        print("Error: Could not find", init_py, file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
