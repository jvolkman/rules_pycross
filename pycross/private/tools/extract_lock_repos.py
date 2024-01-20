"""Extracts the repositories section from a Pycross-generated lock file.

We extract the section by exec()ing the file as Python code.
"""
import json
import sys


def main(file):
    with open(file) as f:
        lock_text = f.read()

    # This is where we'll collect the repo definitions.
    repos = []

    # Mimics the maybe func which calls the first argument with *a and **kw.
    def maybe(func, *a, **kw):
        func(*a, **kw)

    exec_globals = {"__builtins__": None, "maybe": maybe, "repos": repos}

    def load(_file, *a, **kw):
        # Mimic a load by creating functions named in *a and **kw.
        # These functions simply store passed parameters in repos.
        for type in list(a) + list(kw):
            if type in exec_globals:
                continue

            def fn(**kw):
                repos.append({"type": type, "attrs": kw})

            exec_globals[type] = fn

    exec_globals["load"] = load

    # We need to actually call the repositories function in our exec.
    lock_text += "\n"
    lock_text += "repositories()"
    exec(lock_text, exec_globals)

    # Print the results to stdout.
    print(json.dumps(repos, indent=2))


if __name__ == "__main__":
    main(sys.argv[1])
