#!/bin/sh

set -e

DEST=pycross/private/pypi_requirements.bzl
if [ ! -f "$DEST" ]; then
    echo "Expected $DEST to exist; make sure you're running from the repo root."
    exit 1
fi


bazel run //pycross/private:requirements.update
GEN="$(bazel query '@rules_pycross_pypi_deps//:requirements.bzl' --output=location | cut -d: -f1)"

cp "$GEN" "$DEST"
