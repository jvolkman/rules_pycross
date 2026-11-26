"""Cargo/Rust helper functions for repository rules."""

load("@toml.bzl//toml:toml.bzl", "decode")

_CRATES_IO = "registry+https://github.com/rust-lang/crates.io-index"

def find_cargo_lock_in_sdist(rctx, sdist_root, source_dir = ""):
    """Find Cargo.lock in sdist.

    Checks pyproject.toml (maturin and setuptools-rust config) under
    ``source_dir`` (or ``sdist_root`` when unset) for the manifest directory
    and walks up to ``sdist_root`` to support Cargo workspaces.

    Args:
        rctx: The repository context.
        sdist_root: The archive-root directory of the extracted sdist (or hook files dir).
        source_dir: Optional package subdirectory within the sdist archive.

    Returns:
        The Path to the Cargo.lock file, or None if not found.
    """
    source_dir_parts = [p for p in source_dir.split("/") if p and p != "."]
    pkg_dir = sdist_root
    for part in source_dir_parts:
        pkg_dir = pkg_dir.get_child(part)

    pyproject_path = pkg_dir.get_child("pyproject.toml")
    manifest_path = "Cargo.toml"

    if pyproject_path.exists:
        pyproject = decode(rctx.read(pyproject_path))

        # Check Maturin
        tool_cfg = pyproject.get("tool", {})
        maturin_config = tool_cfg.get("maturin", {})
        if type(maturin_config) == "dict" and "manifest-path" in maturin_config:
            manifest_path = maturin_config["manifest-path"]
        else:
            # Check Setuptools-Rust
            sr_config = tool_cfg.get("setuptools-rust", {})
            ext_modules = sr_config.get("ext-modules", []) if type(sr_config) == "dict" else []
            if type(ext_modules) == "list" and ext_modules and type(ext_modules[0]) == "dict":
                manifest_path = ext_modules[0].get("path", "Cargo.toml")

    parts = list(source_dir_parts)
    for part in manifest_path.split("/")[:-1]:
        if not part or part == ".":
            continue
        if part == "..":
            if parts:
                parts.pop()
        else:
            parts.append(part)

    # Walk from the manifest directory up to sdist_root (Cargo places
    # Cargo.lock at the workspace root when manifest-path or source_dir
    # points into a member subdirectory).
    for depth in range(len(parts), -1, -1):
        d = sdist_root
        for part in parts[:depth]:
            d = d.get_child(part)
        lock = d.get_child("Cargo.lock")
        if lock.exists:
            return lock

    return None

def vendor_crates_from_lock(rctx, cargo_lock_path):
    """Download and vendor crates listed in a Cargo.lock file using Bazel's downloader.

    Args:
        rctx: The repository context.
        cargo_lock_path: The path to the Cargo.lock file.
    """
    rctx.report_progress("Vendoring cargo dependencies for " + rctx.name)

    lock_data = decode(rctx.read(cargo_lock_path))

    downloads = []
    for pkg in lock_data.get("package", []):
        source = pkg.get("source", "")
        checksum = pkg.get("checksum", "")
        if source != _CRATES_IO or not checksum:
            continue

        name = pkg["name"]
        version = pkg["version"]

        archive_name = "{}-{}.tar.gz".format(name, version)
        archive_path = "_cargo_download/" + archive_name

        token = rctx.download(
            url = "https://static.crates.io/crates/{name}/{name}-{version}.crate".format(
                name = name,
                version = version,
            ),
            output = archive_path,
            sha256 = checksum,
            block = False,
        )
        downloads.append((token, name, version, archive_path, checksum))

    for token, name, version, archive_path, checksum in downloads:
        res = token.wait()
        if not res.success:
            fail("Failed to download crate {}-{}".format(name, version))

        crate_dir = "vendor/{}-{}".format(name, version)
        rctx.extract(
            archive = archive_path,
            output = crate_dir,
            stripPrefix = "{}-{}".format(name, version),
        )

        rctx.file(
            crate_dir + "/.cargo-checksum.json",
            json.encode({"package": checksum, "files": {}}),
        )

    # Clean up downloads
    rctx.delete("_cargo_download")
