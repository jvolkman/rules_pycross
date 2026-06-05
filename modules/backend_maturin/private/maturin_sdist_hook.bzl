"""Maturin-specific sdist hook with cargo crate vendoring."""

load(":cargo.bzl", "find_cargo_lock_in_sdist", "vendor_crates_from_lock")

def maturin_sdist_hook(rctx, result):
    """Maturin sdist hook that vendors cargo crates.

    Args:
        rctx: The repository context.
        result: The struct returned by _sdist_repo_common containing package metadata.

    Returns:
        A list of extra BUILD file snippet strings (e.g. for vendored_crates filegroup).
    """

    # Extract cargo_lock label from applied override config.
    cargo_lock_json = result.applied_override_config.get("cargo_lock")
    cargo_lock_label = json.decode(cargo_lock_json) if cargo_lock_json else None

    has_vendored = False
    cargo_lock_path = None
    if cargo_lock_label:
        cargo_lock_path = rctx.path(Label(cargo_lock_label))
    else:
        # Extract sdist to find Cargo.lock
        tmp_dir = "cargo_lock_check_tmp"
        rctx.extract(archive = rctx.attr.sdist, output = tmp_dir)

        sdist_root = None
        for child in rctx.path(tmp_dir).readdir():
            if child.is_dir:
                sdist_root = child
                break
        if not sdist_root:
            sdist_root = rctx.path(tmp_dir)

        lock_candidate = find_cargo_lock_in_sdist(rctx, sdist_root)
        if lock_candidate.exists:
            # Copy it out before deleting tmp
            extracted_lock = rctx.path("Cargo.lock.extracted")
            rctx.file(extracted_lock, rctx.read(lock_candidate))
            cargo_lock_path = extracted_lock

        rctx.delete(tmp_dir)

    if cargo_lock_path:
        vendor_crates_from_lock(rctx, cargo_lock_path)
        has_vendored = True

        # Clean up temporary extracted lock
        extracted = rctx.path("Cargo.lock.extracted")
        if extracted.exists:
            rctx.delete("Cargo.lock.extracted")

    extra_build_snippets = None
    if has_vendored:
        result.macro_attrs["vendored_crates"] = "\":vendored_crates\""
        extra_build_snippets = [
            """
filegroup(
    name = "vendored_crates",
    srcs = glob(["vendor/**"]),
)
""",
        ]

    return extra_build_snippets
