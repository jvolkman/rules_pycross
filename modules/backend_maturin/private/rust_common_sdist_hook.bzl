"""Common sdist hook for Rust backends with cargo crate vendoring."""

load(":cargo.bzl", "find_cargo_lock_in_sdist", "vendor_crates_from_lock")

def rust_common_sdist_hook(rctx, result):
    """Common sdist hook that vendors cargo crates.

    Args:
        rctx: The repository context.
        result: The struct returned by _sdist_repo_common containing package metadata.

    Returns:
        A struct with extra_attrs and extra_build_snippets, or None.
    """

    # Extract cargo_lock label from applied override config.
    cargo_lock_json = result.applied_override_config.get("cargo_lock")
    cargo_lock_label = json.decode(cargo_lock_json) if cargo_lock_json else None

    has_vendored = False
    cargo_lock_path = None
    extracted_temp_lock = False
    if cargo_lock_label:
        cargo_lock_path = rctx.path(Label(cargo_lock_label))
    else:
        source_dir = getattr(rctx.attr, "source_dir", "")
        hook_files_dir = getattr(result, "hook_files_dir", None)
        if hook_files_dir != None:
            if hook_files_dir.exists:
                lock_candidate = find_cargo_lock_in_sdist(rctx, hook_files_dir, source_dir = source_dir)
                if lock_candidate and lock_candidate.exists:
                    cargo_lock_path = lock_candidate
        else:
            # Version-skew fallback for older rules_pycross that do not populate hook_files_dir.
            tmp_dir = "cargo_lock_check_tmp"
            rctx.extract(archive = rctx.attr.sdist, output = tmp_dir)

            sdist_root = None
            for child in rctx.path(tmp_dir).readdir():
                if child.is_dir:
                    sdist_root = child
                    break
            if not sdist_root:
                sdist_root = rctx.path(tmp_dir)

            lock_candidate = find_cargo_lock_in_sdist(rctx, sdist_root, source_dir = source_dir)
            if lock_candidate and lock_candidate.exists:
                extracted_lock = rctx.path("Cargo.lock.extracted")
                rctx.file(extracted_lock, rctx.read(lock_candidate))
                cargo_lock_path = extracted_lock
                extracted_temp_lock = True

            rctx.delete(tmp_dir)

    if cargo_lock_path:
        vendor_crates_from_lock(rctx, cargo_lock_path)
        has_vendored = True
        if extracted_temp_lock:
            rctx.delete("Cargo.lock.extracted")

    extra_attrs = {}
    extra_build_snippets = []
    if has_vendored:
        extra_attrs["vendored_crates"] = "\":vendored_crates\""
        extra_build_snippets.append("""
filegroup(
    name = "vendored_crates",
    srcs = glob(["vendor/**"]),
)
""")

    if not extra_attrs and not extra_build_snippets:
        return None

    return struct(
        extra_attrs = extra_attrs,
        extra_build_snippets = extra_build_snippets,
    )
