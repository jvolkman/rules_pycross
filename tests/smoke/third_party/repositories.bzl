"""A centralized module defining third_party repositories."""

load("//third_party/zlib:repositories.bzl", zlib_repositories = "repositories")
load("//third_party/zstd:repositories.bzl", zstd_repositories = "repositories")

# buildifier: disable=unnamed-macro
def repositories():
    """Load all repositories."""
    zlib_repositories()
    zstd_repositories()
