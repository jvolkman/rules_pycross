#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Set by GH actions, see
# https://docs.github.com/en/actions/learn-github-actions/environment-variables#default-environment-variables
TAG=${GITHUB_REF_NAME}
# The prefix is chosen to match what GitHub generates for source archives
# This guarantees that users can easily switch from a released artifact to a source archive
# with minimal differences in their code (e.g. strip_prefix remains the same)
PREFIX="rules_pycross-${TAG:1}"
ARCHIVE="rules_pycross-$TAG.tar.gz"

# NB: configuration for 'git archive' is in /.gitattributes
git archive --format=tar --prefix=${PREFIX}/ ${TAG} | gzip > $ARCHIVE
SHA=$(shasum -a 256 $ARCHIVE | awk '{print $1}')

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
EOF

awk 'f;/--SNIP--/{f=1}' e2e/smoke/WORKSPACE.bazel
echo "\`\`\`" 
