"""Tests for pycross/private/tools/modules_mapping.py."""

import json
import tempfile
import unittest
from pathlib import Path

from pycross.private.tools import modules_mapping
from pycross.private.tools.modules_mapping import Distribution
from pycross.private.tools.modules_mapping import build_mapping
from pycross.private.tools.modules_mapping import simplify


def make_index(name, top=None, dirs=(), namespaces=None, version="1.0", pth=None):
    """A per-wheel index (see wheel_index.py). `top` defaults to the top-level dirs."""
    if top is None:
        top = {d: [d] for d in dirs if "/" not in d}
    return {
        "version": 1,
        "distribution": {"name": name, "version": version},
        "dist_info": "{}-{}.dist-info".format(name.replace("-", "_"), version),
        "top": top,
        "pth": sorted(pth or {}),
        "pth_paths": pth or {},
        "dirs": sorted(dirs),
        "namespaces": namespaces or {},
    }


def mapping_for(*indexes):
    dists = {}
    for index in indexes:
        name = modules_mapping.canonical_name(index["distribution"]["name"])
        dists.setdefault(name, Distribution(name)).add_index(index)
    return build_mapping(dists.values())


class ModulesMappingTest(unittest.TestCase):
    def test_regular_packages_and_modules(self):
        mapping = mapping_for(
            make_index("python-dateutil", dirs=["dateutil", "dateutil/tz"]),
            make_index("six", top={"six": ["six.py"]}),
            make_index(
                "PyYAML", top={"yaml": ["yaml"], "_yaml": ["_yaml.cpython-311-x86_64-linux-gnu.so"]}, dirs=["yaml"]
            ),
        )
        self.assertEqual(
            mapping,
            {"dateutil": "python_dateutil", "six": "six", "yaml": "pyyaml", "_yaml": "pyyaml"},
        )

    def test_pep420_namespaces_are_never_mapped(self):
        storage = make_index(
            "google-cloud-storage",
            dirs=["google", "google/cloud", "google/cloud/storage", "google/cloud/storage/sub"],
            namespaces={"google": [], "google/cloud": []},
        )
        pubsub = make_index(
            "google-cloud-pubsub",
            dirs=["google", "google/cloud", "google/cloud/pubsub", "google/pubsub"],
            namespaces={"google": [], "google/cloud": []},
        )
        protos = make_index(
            "googleapis-common-protos",
            dirs=["google", "google/api", "google/cloud", "google/cloud/location"],
            namespaces={
                "google": [],
                "google/api": ["annotations_pb2", "http_pb2"],
                "google/cloud": ["extended_operations_pb2"],
            },
        )
        self.assertEqual(
            mapping_for(storage, pubsub, protos),
            {
                "google.api.annotations_pb2": "googleapis_common_protos",
                "google.api.http_pb2": "googleapis_common_protos",
                "google.cloud.extended_operations_pb2": "googleapis_common_protos",
                "google.cloud.location": "googleapis_common_protos",
                "google.cloud.pubsub": "google_cloud_pubsub",
                "google.cloud.storage": "google_cloud_storage",
                "google.pubsub": "google_cloud_pubsub",
            },
        )
        # Alone in the set, a distribution still doesn't claim the namespace: another
        # distribution outside the set can add to it.
        self.assertEqual(mapping_for(storage), {"google.cloud.storage": "google_cloud_storage"})

    def test_pkgutil_namespace_with_module_files(self):
        tarfile = make_index(
            "backports.tarfile",
            dirs=["backports", "backports/tarfile"],
            namespaces={"backports": []},
        )
        selectable = make_index(
            "backports.entry_points_selectable",
            dirs=["backports"],
            namespaces={"backports": ["entry_points_selectable"]},
        )
        self.assertEqual(
            mapping_for(tarfile, selectable),
            {
                "backports.entry_points_selectable": "backports_entry_points_selectable",
                "backports.tarfile": "backports_tarfile",
            },
        )

    def test_well_known_nvidia_namespace(self):
        # nvidia wheels each ship an empty nvidia/__init__.py, which makes it a regular package.
        cublas = make_index("nvidia-cublas-cu12", dirs=["nvidia", "nvidia/cublas", "nvidia/cublas/lib"])
        cudnn = make_index("nvidia-cudnn-cu12", dirs=["nvidia", "nvidia/cudnn", "nvidia/cudnn/lib"])
        self.assertEqual(
            mapping_for(cublas, cudnn),
            {"nvidia.cublas": "nvidia_cublas_cu12", "nvidia.cudnn": "nvidia_cudnn_cu12"},
        )
        self.assertEqual(mapping_for(cublas), {"nvidia.cublas": "nvidia_cublas_cu12"})

    def test_conflicting_regular_packages_collapse_to_unique_children(self):
        mapping = mapping_for(
            make_index("opencv-python", dirs=["cv2", "cv2/data", "cv2/gapi"]),
            make_index("opencv-contrib-python", dirs=["cv2", "cv2/data", "cv2/contrib"]),
            make_index("six", top={"six": ["six.py"]}),
            make_index("six-fork", top={"six": ["six.py"]}),
        )
        self.assertEqual(
            mapping,
            {"cv2.contrib": "opencv_contrib_python", "cv2.gapi": "opencv_python"},
        )

    def test_versions_of_one_distribution_do_not_conflict(self):
        mapping = mapping_for(
            make_index("numpy", dirs=["numpy", "numpy/core"], version="1.26.4"),
            make_index("numpy", dirs=["numpy", "numpy/_core"], version="2.3.4"),
        )
        self.assertEqual(mapping, {"numpy": "numpy"})

    def test_plugin_under_another_distributions_package(self):
        core = make_index(
            "azure-core",
            dirs=["azure", "azure/core", "azure/core/pipeline", "azure/core/tracing", "azure/core/tracing/ext"],
            namespaces={"azure": []},
        )
        plugin = make_index(
            "azure-core-tracing-opentelemetry",
            dirs=[
                "azure",
                "azure/core",
                "azure/core/tracing",
                "azure/core/tracing/ext",
                "azure/core/tracing/ext/opentelemetry_span",
            ],
            namespaces={"azure": [], "azure/core": [], "azure/core/tracing": [], "azure/core/tracing/ext": []},
        )
        self.assertEqual(
            mapping_for(core, plugin),
            {
                "azure.core": "azure_core",
                "azure.core.tracing.ext.opentelemetry_span": "azure_core_tracing_opentelemetry",
            },
        )

    def test_excluded_top_level_names(self):
        mapping = mapping_for(
            make_index(
                "sloppy",
                top={
                    "__init__": ["__init__.py"],
                    "__main__": ["__main__.py"],
                    "conftest": ["conftest.py"],
                    "setup": ["setup.py"],
                    "sloppy": ["sloppy"],
                    "tests": ["tests"],
                    "docs": ["docs"],
                    "tools": ["tools.py"],
                },
                dirs=["docs", "sloppy", "tests", "tests/unique_helpers"],
                namespaces={"tests": ["conftest_helpers"]},
            ),
            # The denylist applies to names under .pth roots too, since they're top-level names.
            make_index(
                "rooted",
                dirs=["lib", "lib/rootedpkg", "lib/tests"],
                namespaces={"lib": []},
                pth={"rooted.pth": ["lib"]},
            ),
        )
        # Only the re-rooted `tests` is a top-level name; `lib.tests` stays mapped.
        self.assertEqual(
            mapping,
            {"sloppy": "sloppy", "rootedpkg": "rooted", "lib.rootedpkg": "rooted", "lib.tests": "rooted"},
        )

    def test_pth_paths_add_roots(self):
        rerun = make_index(
            "rerun-sdk",
            top={"rerun_bindings": ["rerun_bindings"], "rerun_sdk": ["rerun_sdk"]},
            dirs=["rerun_bindings", "rerun_sdk", "rerun_sdk/rerun", "rerun_sdk/rerun/blueprint", "rerun_sdk/rerun_cli"],
            namespaces={"rerun_sdk": ["rerun_helper"]},
            pth={"rerun_sdk.pth": ["rerun_sdk"]},
        )
        self.assertEqual(
            mapping_for(rerun),
            {
                "rerun": "rerun_sdk",
                "rerun_bindings": "rerun_sdk",
                "rerun_cli": "rerun_sdk",
                "rerun_helper": "rerun_sdk",
                "rerun_sdk.rerun": "rerun_sdk",
                "rerun_sdk.rerun_cli": "rerun_sdk",
                "rerun_sdk.rerun_helper": "rerun_sdk",
            },
        )
        # Re-rooted names take part in conflict resolution like any other top-level name.
        other = make_index("other-rerun", dirs=["rerun"])
        self.assertNotIn("rerun", mapping_for(rerun, other))

    def test_module_next_to_namespace_dir_is_concrete(self):
        mapping = mapping_for(
            make_index("a", top={"foo": ["foo", "foo.py"]}, dirs=["foo"], namespaces={"foo": []}),
        )
        self.assertEqual(mapping, {"foo": "a"})

    def test_simplify(self):
        self.assertEqual(
            simplify(
                {
                    "_pytest": "pytest",
                    "_pytest._argcomplete": "pytest",
                    "_pytest.config.argparsing": "pytest",
                    "bosdyn.client": "bosdyn_client",
                    "bosdyn.client.control": "bosdyn_client",
                    "bosdyn.orbit": "bosdyn_orbit",
                    "foo": "a",
                    "foo.bar": "b",
                    "foo.bar.baz": "b",
                }
            ),
            {
                "_pytest": "pytest",
                "bosdyn.client": "bosdyn_client",
                "bosdyn.orbit": "bosdyn_orbit",
                "foo": "a",
                "foo.bar": "b",
            },
        )


class ModulesMappingCliTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def write_index(self, filename, index):
        path = self.tmp / filename
        path.write_text(json.dumps(index))
        return path

    def run_tool(self, *argv):
        output = self.tmp / "modules_mapping.json"
        flagfile = self.tmp / "args"
        flagfile.write_text("\n".join(["--output", str(output)] + [str(a) for a in argv]))
        modules_mapping.main(modules_mapping.parse_flags(["--flagfile=" + str(flagfile)]))
        return json.loads(output.read_text())

    def test_indexes_and_site_path_fallback(self):
        storage = self.write_index(
            "storage.json",
            make_index(
                "google-cloud-storage",
                dirs=["google", "google/cloud", "google/cloud/storage"],
                namespaces={"google": [], "google/cloud": []},
            ),
        )
        dateutil = self.write_index("dateutil.json", make_index("python-dateutil", dirs=["dateutil"]))
        mapping = self.run_tool(
            "--index",
            storage,
            "--index",
            dateutil,
            # The same index through two deps (e.g. a package and its extras) isn't a conflict.
            "--index",
            dateutil,
            # Packages without an index fall back to their site_paths.
            "--site-path",
            "Zope.Interface=zope/interface",
            "--site-path",
            "google-cloud-pubsub=google/cloud/pubsub",
            "--site-path",
            "attrs=attr",
            "--site-path",
            "attrs=attrs",
            "--site-path",
            "cffi=_cffi_backend.cpython-311-x86_64-linux-gnu.so",
        )
        self.assertEqual(
            mapping,
            {
                "_cffi_backend": "cffi",
                "attr": "attrs",
                "attrs": "attrs",
                "dateutil": "python_dateutil",
                "google.cloud.pubsub": "google_cloud_pubsub",
                "google.cloud.storage": "google_cloud_storage",
                "zope.interface": "zope_interface",
            },
        )

    def test_name_from_dist_info_when_metadata_has_none(self):
        index = make_index("ignored", dirs=["foo"])
        index["distribution"] = {"name": None, "version": None}
        index["dist_info"] = "Foo_Bar-1.0.dist-info"
        mapping = self.run_tool("--index", self.write_index("foo.json", index))
        self.assertEqual(mapping, {"foo": "foo_bar"})

    def test_rejects_newer_index_version(self):
        index = make_index("foo", dirs=["foo"])
        index["version"] = 2
        with self.assertRaises(SystemExit) as cm:
            self.run_tool("--index", self.write_index("foo.json", index))
        self.assertIn("version 2", str(cm.exception))

    def test_empty(self):
        self.assertEqual(self.run_tool(), {})


if __name__ == "__main__":
    unittest.main()
