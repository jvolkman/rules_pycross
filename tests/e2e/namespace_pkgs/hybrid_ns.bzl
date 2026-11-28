"""Dev test extension exposing synthetic wheels for hybrid pkgutil namespace testing."""

# buildifier: disable=bzl-visibility
load("@rules_pycross//pycross/private:wheel_file.bzl", "pycross_wheel_file")

_CORE_FILENAME = "hybrid_core-1.0.0-py3-none-any.whl"
_CORE_SHA256 = "bcbd9bebd50559b262b934a0a2740976085895598b82495993ebca3d76a91bdc"
_PLUGIN_FILENAME = "hybrid_plugin-1.0.0-py3-none-any.whl"
_PLUGIN_SHA256 = "2fa9c87aa8154e6c9647b27797620566cca53ea271218ae1ff7a6ce66ee1940b"

def _hybrid_ns_ext_impl(mctx):
    root = str(mctx.path(Label("//:MODULE.bazel")).dirname)
    prefix = "file://" if root.startswith("/") else "file:///"
    wheels_dir = "{}{}/wheels".format(prefix, root)
    pycross_wheel_file(
        name = "hybrid_core_whl",
        filename = _CORE_FILENAME,
        sha256 = _CORE_SHA256,
        urls = ["{}/{}".format(wheels_dir, _CORE_FILENAME)],
    )
    pycross_wheel_file(
        name = "hybrid_plugin_whl",
        filename = _PLUGIN_FILENAME,
        sha256 = _PLUGIN_SHA256,
        urls = ["{}/{}".format(wheels_dir, _PLUGIN_FILENAME)],
    )

hybrid_ns_ext = module_extension(implementation = _hybrid_ns_ext_impl)
