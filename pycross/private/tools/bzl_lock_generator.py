from pathlib import Path
from typing import Any

from pycross.private.tools import raw_lock_resolver
from pycross.private.tools import resolved_lock_renderer
from pycross.private.tools.args import FlagFileArgumentParser


def parse_flags() -> Any:
    parser = FlagFileArgumentParser(description="Generate pycross dependency bzl file.")

    raw_lock_resolver.add_shared_flags(parser)
    resolved_lock_renderer.add_shared_flags(parser)
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The path to the output JSON file.",
    )

    return parser.parse_args()


def main(args: Any) -> None:
    resolved_lock = raw_lock_resolver.resolve(args)
    with open(args.output, "w") as f:
        resolved_lock_renderer.render(resolved_lock, args, f)


if __name__ == "__main__":
    main(parse_flags())
