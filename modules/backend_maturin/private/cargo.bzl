"""Cargo/Rust helper functions for repository rules."""

load("@toml.bzl//toml:toml.bzl", "decode")

_CRATES_IO = "registry+https://github.com/rust-lang/crates.io-index"

def find_cargo_lock_in_sdist(rctx, sdist_root):
    """Find Cargo.lock in sdist.

    Checks pyproject.toml (maturin and setuptools-rust config) first,
    then falls back to recursive search.

    Args:
        rctx: The repository context.
        sdist_root: The root directory of the extracted sdist.

    Returns:
        The Path to the Cargo.lock file, or None if not found.
    """
    pyproject_path = sdist_root.get_child("pyproject.toml")
    cargo_dir = sdist_root
    manifest_path = "Cargo.toml"

    if pyproject_path.exists:
        pyproject = decode(rctx.read(pyproject_path))

        # Check Maturin
        maturin_config = pyproject.get("tool", {}).get("maturin", {})
        if maturin_config:
            manifest_path = maturin_config.get("manifest-path", "Cargo.toml")
        else:
            # Check Setuptools-Rust
            ext_modules = pyproject.get("tool", {}).get("setuptools-rust", {}).get("ext-modules", [])
            if ext_modules and type(ext_modules) == "list":
                manifest_path = ext_modules[0].get("path", "Cargo.toml")

        parts = manifest_path.split("/")
        for part in parts[:-1]:
            cargo_dir = cargo_dir.get_child(part)

    lock = cargo_dir.get_child("Cargo.lock")
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
