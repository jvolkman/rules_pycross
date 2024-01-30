#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Set by GH actions, see
# https://docs.github.com/en/actions/learn-github-actions/environment-variables#default-environment-variables
TAG=${GITHUB_REF_NAME}
PREFIX="rules_pycross-${TAG:1}"
ARCHIVE="rules_pycross-$TAG.tar.gz"

# NB: configuration for 'git archive' is in /.gitattributes
git archive --format=tar --prefix=${PREFIX}/ ${TAG} | gzip > $ARCHIVE
SHA=$(git archive --format=tar --prefix=${PREFIX}/ ${TAG} | gzip | shasum -a 256 | awk '{print $1}')

cat << EOF
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

# change this to something that works in your environment.
load("@python//3.12.0:defs.bzl", python_interpreter = "interpreter")

load("@rules_pycross//pycross:repositories.bzl", "rules_pycross_dependencies")
rules_pycross_dependencies(python_interpreter)
\`\`\`
EOF
