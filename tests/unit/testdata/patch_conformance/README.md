# Patch conformance fixtures

`//tests/unit:patch_conformance_test` runs these fixtures through
`pycross/private/patching/pycross_patch.py`.

| Directory | Source | Upstream path | License |
|---|---|---|---|
| `diffy/` | [bmwill/diffy](https://github.com/bmwill/diffy) at `eba5e533f3c385a9740bb446c7e0995ae50ca062` | `tests/compat/{git,gnu_patch}` | MIT or Apache-2.0 (`diffy/LICENSE-*`) |
| `go_gitdiff/` | [bluekeyes/go-gitdiff](https://github.com/bluekeyes/go-gitdiff) at `3597f724e5b4ecdac61ac4d7fb37421113096aac` | `gitdiff/testdata/apply` | MIT (`go_gitdiff/LICENSE`) |

The diffy cases were checked against `git apply` and GNU patch. Each case
directory has `in/foo.patch`, the files it applies to, and the expected `out/`
files. The test reads each case's strip level, and the cases where pycross
deliberately differs, from tables in `patch_conformance_test.py`.

The go-gitdiff `bin_fragment_*` fixtures test its binary decoder rather than
file patches, so they aren't copied.

File contents are unchanged. File names are percent-encoded, because Bazel can't
handle some upstream names, such as ones with tabs or quotes. To update the
fixtures, check out both repositories and run:

```sh
python3 import_fixtures.py <diffy checkout> <go-gitdiff checkout>
```

Then update the commits above.
