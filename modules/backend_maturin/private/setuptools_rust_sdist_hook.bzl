"""Setuptools Rust-specific sdist hook with cargo crate vendoring."""

load(":rust_common_sdist_hook.bzl", "rust_common_sdist_hook")

def setuptools_rust_sdist_hook(rctx, result):
    """Setuptools Rust sdist hook that vendors cargo crates.

    Args:
        rctx: The repository context.
        result: The struct returned by _sdist_repo_common containing package metadata.

    Returns:
        A list of extra BUILD file snippet strings (e.g. for vendored_crates filegroup).
    """
    return rust_common_sdist_hook(rctx, result)
