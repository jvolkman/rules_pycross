import shlex
from argparse import ArgumentParser


class FlagFileArgumentParser(ArgumentParser):
    """An ArgumentParser that supports a --flagfile parameter.

    If --flagfile is passed, the file specified file is read and its lines are interpreted
    as command line arguments. Assumes Bazel's "shell" param file semantics.
    """

    def parse_known_args(self, args=None, namespace=None):
        flagfile_parser = ArgumentParser()
        flagfile_parser.add_argument("--flagfile", type=open)
        ff_namespace, args = flagfile_parser.parse_known_args(args)
        if ff_namespace.flagfile:
            with ff_namespace.flagfile as f:
                additional_args = shlex.split(f.read())
                print(additional_args)
            args.extend(additional_args)

        # Pass the original namespace, if given, not the intermediate flagfile
        # namespace.
        return super().parse_known_args(args, namespace)
