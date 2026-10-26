# `rules_python` unified-diff patch engine

- **Upstream**: https://github.com/bazel-contrib/rules_python
- **Source file**: `python/private/pypi/wheel_layout.py`
- **Commit**: `dbd9d9c9189ee3fde8a6935d68a14ec19c972bbe`
- **License**: Apache-2.0 (`LICENSE`, copied from the same commit)
- **Modifications**: `unified_patch.py` contains only the patch engine
  (`_HUNK_HEADER_RE` through `apply_unified_patch`, upstream lines 298-544),
  copied byte-for-byte, plus a license/provenance header and the imports it needs.
  The rest of `wheel_layout.py` (wheel layout, RECORD helpers) is not vendored.
  pycross's strip handling and error mapping live in `//pycross/private/patching`.

To re-vendor, replace the engine section and update the commit above. The body
must stay byte-identical to upstream:

```sh
git -C <rules_python> show <commit>:python/private/pypi/wheel_layout.py | sed -n '298,544p' | sha256sum
sed -n '30,$p' unified_patch.py | sha256sum
```

Engine body SHA-256 at the commit above: `82efb93ab10993536e4747490c8734ae723f1bdfaa6bbd6848b87627aaad1354`.
