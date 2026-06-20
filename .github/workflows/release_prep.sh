#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Argument provided by reusable workflow caller
TAG=$1
VERSION="${TAG#v}"
# The prefix is chosen to match what GitHub generates for source archives
PREFIX="rules_pycross-${VERSION}"
ARCHIVE="rules_pycross-$TAG.tar.gz"

# NB: configuration for 'git archive' is in /.gitattributes
git archive --format=tar --prefix=${PREFIX}/ ${TAG} | gzip > "${RUNNER_TEMP}/base.tar.gz"

# Stamp module versions using buildozer.
# This updates module() version and cross-module bazel_dep() references
# so the release archive contains the correct version strings.
BUILDOZER="${RUNNER_TEMP}/buildozer"
curl -fsSL -o "${BUILDOZER}" \
  "https://github.com/bazelbuild/buildtools/releases/download/v7.3.1/buildozer-linux-amd64"
chmod +x "${BUILDOZER}"

# Extract archive, stamp MODULE.bazel files, re-tar.
EXTRACT="$(mktemp -d)"
tar xzf "${RUNNER_TEMP}/base.tar.gz" -C "${EXTRACT}"

# Run buildozer from the extracted archive root so it finds MODULE.bazel.
pushd "${EXTRACT}/${PREFIX}"
"${BUILDOZER}" \
    "set version ${VERSION}" \
  "//MODULE.bazel:rules_pycross" \
  "//modules/backend_maturin/MODULE.bazel:rules_pycross_backend_maturin" \
  "//modules/backend_maturin/MODULE.bazel:rules_pycross"
popd

tar czf "${ARCHIVE}" -C "${EXTRACT}" "${PREFIX}"

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
bazel_dep(name = "rules_pycross", version = "${VERSION}")
\`\`\`

### Maturin backend (optional):

\`\`\`starlark
bazel_dep(name = "rules_pycross_backend_maturin", version = "${VERSION}")
\`\`\`

**SHA-256:** \`${SHA}\`
EOF
