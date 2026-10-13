# Copyright 2026 The rules_pycross Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Merges per-wheel import indexes into a binary's import index (PyMakeVenvIndex).

Usage: venv_import_index_merger.py --output OUT [--entry ROOT INDEX]...
Arguments can come from a file with `@file`, one per line.
"""

import argparse
import json

from pycross.private.tools.import_index import dist_info_key
from pycross.private.tools.import_index import merge_wheel_indexes as merge

__all__ = ["dist_info_key", "merge", "main"]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, fromfile_prefix_chars="@")
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--entry",
        action="append",
        nargs=2,
        default=[],
        metavar=("ROOT", "INDEX"),
        help="a wheel root and its per-wheel index file, in sys.path order",
    )
    args = parser.parse_args(argv)

    entries = []
    for root, path in args.entry:
        with open(path, encoding="utf-8") as f:
            entries.append((root, json.load(f)))
    merged = merge(entries)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(merged, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
