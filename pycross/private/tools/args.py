import shlex
from argparse import ArgumentParser


class FlagFileArgumentParser(ArgumentParser):
    """An ArgumentParser that supports a --flagfile parameter.

    If --flagfile is passed, the file specified file is read and its lines are interpreted
    as command line arguments. Assumes Bazel's "shell" param file semantics.
    """

    def parse_known_args(self, args=None, namespace=None):
        flagfile_parser = ArgumentParser(add_help=False, allow_abbrev=False)
        flagfile_parser.add_argument("--flagfile")
        ff_namespace, args = flagfile_parser.parse_known_args(args)
        if ff_namespace.flagfile:
            with open(ff_namespace.flagfile, encoding="utf-8") as f:
                additional_args = shlex.split(f.read())
            args.extend(additional_args)

        # Pass the original namespace, if given, not the intermediate flagfile
        # namespace.
        return super().parse_known_args(args, namespace)
