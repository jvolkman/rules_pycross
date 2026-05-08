#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Argument provided by reusable workflow caller
TAG=$1
# The prefix is chosen to match what GitHub generates for source archives
PREFIX="rules_pycross-${TAG:1}"
ARCHIVE="rules_pycross-$TAG.tar.gz"

# NB: configuration for 'git archive' is in /.gitattributes
git archive --format=tar --prefix=${PREFIX}/ ${TAG} | gzip > $ARCHIVE
SHA=$(shasum -a 256 $ARCHIVE | awk '{print $1}')

# Add generated API docs
docs="$(mktemp -d)"; targets="$(mktemp)"
bazel --output_base="$docs" query --output=label --output_file="$targets" 'kind("starlark_doc_extract rule", //...)'
bazel --output_base="$docs" build --target_pattern_file="$targets"
tar --create --auto-compress \
    --directory "$(bazel --output_base="$docs" info bazel-bin)" \
    --file "$GITHUB_WORKSPACE/${ARCHIVE%.tar.gz}.docs.tar.gz" .

cat << EOF
See the [changelog](CHANGELOG.md).

## Using Bzlmod:

Add to your \`MODULE.bazel\` file:

\`\`\`starlark
bazel_dep(name = "rules_pycross", version = "${TAG:1}")
\`\`\`

## Using \`WORKSPACE\`:

\`\`\`starlark
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
    name = "rules_pycross",
    sha256 = "${SHA}",
    strip_prefix = "${PREFIX}",
    url = "https://github.com/jvolkman/rules_pycross/releases/download/${TAG}/${ARCHIVE}",
)
\`\`\`
EOF
