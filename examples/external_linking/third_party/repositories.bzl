"""A centralized module defining third_party repositories."""

load("//third_party/boringssl:repositories.bzl", boringssl_repositories = "repositories")
load("//third_party/openblas:repositories.bzl", openblas_repositories = "repositories")
load("//third_party/openssl:repositories.bzl", openssl_repositories = "repositories")
load("//third_party/postgresql:repositories.bzl", postgresql_repositories = "repositories")
load("//third_party/zlib:repositories.bzl", zlib_repositories = "repositories")

# buildifier: disable=unnamed-macro
def repositories():
    """Load all repositories."""
    boringssl_repositories()
    openblas_repositories()
    openssl_repositories()
    postgresql_repositories()
    zlib_repositories()
