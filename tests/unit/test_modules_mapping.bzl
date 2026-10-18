"""Tests for modules_mapping"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:modules_mapping.bzl",
    "build_modules_mapping_for_testing",
    "get_module_name_for_testing",
)

# buildifier: disable=unused-variable
def _test_get_module_name_valid_impl(env, target):
    g = get_module_name_for_testing
    env.expect.that_str(g("requests")).equals("requests")
    env.expect.that_str(g("google/cloud/storage")).equals("google.cloud.storage")
    env.expect.that_str(g("six.py")).equals("six")
    env.expect.that_str(g("rerun_sdk.pth")).equals("rerun_sdk")
    env.expect.that_str(g("_cffi_backend.cpython-313-x86_64-linux-gnu.so")).equals("_cffi_backend")
    env.expect.that_str(g("PyQt5/QtCore.abi3.so")).equals("PyQt5.QtCore")
    env.expect.that_str(g("PyQt5/sip.cpython-313-x86_64-linux-gnu.so")).equals("PyQt5.sip")
    env.expect.that_str(g("pkg/mod.abi3-x86_64.so")).equals("pkg.mod")
    env.expect.that_str(g("pkg/ext.pyd")).equals("pkg.ext")
    env.expect.that_str(g("zope/interface/__init__.py")).equals("zope.interface")
    env.expect.that_str(g("nvidia/cusparse/__init__.py")).equals("nvidia.cusparse")

def _test_get_module_name_valid(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_get_module_name_valid_impl)

# buildifier: disable=unused-variable
def _test_get_module_name_rejects_non_modules_impl(env, target):
    g = get_module_name_for_testing
    rejected = [
        "",
        "__init__.py",
        "PyQt5/QtCore.pyi",
        "PyQt5/py.typed",
        "PyQt5/bindings/QtCore/qfile.sip",
        "PyQt5/bindings/QtCore/QtCore.toml",
        "PyQt5/Qt5/qsci/api/python/PyQt5.api",
        "PyQt5/Qt5/lib/libQt5Core.so.5",
        "PyQt5/Qt5/qml/QtQuick.2/libqtquick2plugin.so",
        "PyQt5/Qt5/translations/qt_de.qm",
        "google/api/annotations.proto",
        "google/api/annotations_pb2.pyi",
        "google/cloud/bigquery_storage_v1alpha/gapic_metadata.json",
        "opentelemetry/propagators/py.typed",
        "typings/IPython/__init__.pyi",
        "mmh3/murmurhash3.c",
        "mmh3/murmurhash3.h",
        "examples/gallery/README.md",
        "nvidia/cusparse/lib/libcusparse.so.12",
        "numpy.libs/libscipy_openblas64_-1234abcd.so",
        "foo.bar/baz.py",
        "google_cloud_aiplatform-1.156.0-py3.12-nspkg.pth",
    ]
    for path in rejected:
        env.expect.that_bool(g(path) == None).equals(True)

def _test_get_module_name_rejects_non_modules(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_get_module_name_rejects_non_modules_impl)

# buildifier: disable=unused-variable
def _test_build_modules_mapping_collapses_split_packages_impl(env, target):
    pkg_infos = [
        struct(
            package_name = "zope-interface",
            site_paths = [
                "zope/interface/__init__.py",
                "zope/interface/_compat.py",
                "zope/interface/_zope_interface_coptimizations.c",
                "zope/interface/_zope_interface_coptimizations.cpython-313-x86_64-linux-gnu.so",
                "zope/interface/adapter.py",
                "zope/interface/common",
            ],
        ),
        struct(
            package_name = "nvidia-cusparse-cu12",
            site_paths = [
                "nvidia/cusparse/__init__.py",
                "nvidia/cusparse/include",
                "nvidia/cusparse/lib/__init__.py",
                "nvidia/cusparse/lib/libcusparse.so.12",
            ],
        ),
        struct(
            package_name = "googleapis-common-protos",
            site_paths = [
                "google/api",
                "google/api/annotations.proto",
                "google/api/annotations_pb2.pyi",
                "google/rpc",
                "google/rpc/status.proto",
            ],
        ),
    ]
    mapping = build_modules_mapping_for_testing(pkg_infos)
    env.expect.that_dict(mapping).contains_exactly({
        "zope.interface": "zope_interface",
        "nvidia.cusparse": "nvidia_cusparse_cu12",
        "google.api": "googleapis_common_protos",
        "google.rpc": "googleapis_common_protos",
    })

def _test_build_modules_mapping_collapses_split_packages(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_build_modules_mapping_collapses_split_packages_impl)

# buildifier: disable=unused-variable
def _test_build_modules_mapping_preserves_distinct_packages_in_namespace_impl(env, target):
    pkg_infos = [
        struct(
            package_name = "google-cloud-core",
            site_paths = ["google/cloud"],
        ),
        struct(
            package_name = "google-cloud-storage",
            site_paths = ["google/cloud/storage"],
        ),
    ]
    mapping = build_modules_mapping_for_testing(pkg_infos)
    env.expect.that_dict(mapping).contains_exactly({
        "google.cloud": "google_cloud_core",
        "google.cloud.storage": "google_cloud_storage",
    })

def _test_build_modules_mapping_preserves_distinct_packages_in_namespace(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_build_modules_mapping_preserves_distinct_packages_in_namespace_impl)

def modules_mapping_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_get_module_name_valid,
            _test_get_module_name_rejects_non_modules,
            _test_build_modules_mapping_collapses_split_packages,
            _test_build_modules_mapping_preserves_distinct_packages_in_namespace,
        ],
    )
