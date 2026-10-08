# How to Contribute

## Formatting

Starlark files should be formatted by buildifier.
We suggest using a pre-commit hook to automate this.
First [install pre-commit](https://pre-commit.com/#installation),
then run

```shell
pre-commit install
```

Otherwise later tooling on CI may yell at you about formatting/linting violations.

## Updating BUILD files

Some targets are generated from sources.
Currently this is just the `bzl_library` targets.
Run `bazel run //:gazelle` to keep them up-to-date.

## Remote cache

CI uses a BuildBuddy remote cache. Pull request runs use a public read-only API key and don't upload results; only trusted runs (pushes to `main`, scheduled and manual runs) write to the cache.
You can use the same read-only cache locally with `--config=remote-ro` (defined in the root `.bazelrc`):

```sh
bazel test --config=remote-ro //tests/unit/...
```

The root `.bazelrc` (and so `remote-ro`) applies only in the root workspace and `examples/bzlmod`, not in the nested e2e workspaces under `tests/e2e/`.

## Using this as a development dependency of other rules

To test changes from another module that depends on rules_pycross (for example
a ruleset or a project of your own), point Bazel at this checkout. Run this
from this directory:

```sh
echo "common --override_module=rules_pycross=$(pwd)" >> ~/.bazelrc
```

This means that any usage of `@rules_pycross` on your system will point to this folder.

## Releasing

1. Determine the next release version, following semver (could automate in the future from changelog)
1. Tag the repo and push it (or create a tag in GH UI)
1. Watch the automation run on GitHub actions
