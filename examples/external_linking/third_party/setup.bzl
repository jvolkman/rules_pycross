"""A centralized module defining third_party setup stuff."""

load("//third_party/openssl:setup.bzl", openssl_setup = "setup")

# buildifier: disable=unnamed-macro
def setup():
    """Load all setup stuff."""
    openssl_setup()
