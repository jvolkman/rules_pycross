#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Set by GH actions, see
# https://docs.github.com/en/actions/learn-github-actions/environment-variables#default-environment-variables
TAG=${GITHUB_REF_NAME}
PREFIX="rules_pycross-${TAG:1}"
SHA=$(git archive --format=tar --prefix=${PREFIX}/ ${TAG} | gzip | shasum -a 256 | awk '{print $1}')

cat << EOF
WORKSPACE snippet:
\`\`\`starlark
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
    name = "jvolkman_rules_pycross",
    sha256 = "${SHA}",
    strip_prefix = "${PREFIX}",
    url = "https://github.com/jvolkman/rules_pycross/archive/refs/tags/${TAG}.tar.gz",
)

# Fetches the rules_pycross dependencies.
# If you want to have a different version of some dependency,
# you should fetch it *before* calling this.
# Alternatively, you can skip calling this function, so long as you've
# already fetched all the dependencies.
load("@jvolkman_rules_pycross//pycross:repositories.bzl", "rules_pycross_dependencies")
rules_pycross_dependencies()

\`\`\`
EOF
