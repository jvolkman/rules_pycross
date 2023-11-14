"""A centralized module defining third_party repositories."""

load("//third_party/zstd:repositories.bzl", zstd_repositories = "repositories")

# buildifier: disable=unnamed-macro
def repositories():
    """Load all repositories."""
    zstd_repositories()
