"""Maturin-specific sdist repository rule with cargo crate vendoring."""

load(":cargo.bzl", "find_cargo_lock_in_sdist", "vendor_crates_from_lock")
load(":sdist_repo.bzl", "SDIST_REPO_ATTRS", "sdist_repo_common")

def _maturin_sdist_repo_impl(rctx):
    result = sdist_repo_common(rctx)
    macro_attrs = result.macro_attrs

    # Extract cargo_lock label from backend_attrs if present.
    cargo_lock_json = rctx.attr.backend_attrs.get("cargo_lock")
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

    if has_vendored:
        macro_attrs["vendored_crates"] = "\":vendored_crates\""

    result.render(macro_attrs, result.backend_macro, has_vendored)

maturin_sdist_repo = repository_rule(
    implementation = _maturin_sdist_repo_impl,
    attrs = SDIST_REPO_ATTRS,
)
