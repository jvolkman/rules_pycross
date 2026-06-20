"""Tests for variant data model and pins serialization in lock_model.py."""

from __future__ import annotations

import json
import unittest

from packaging.specifiers import SpecifierSet

from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import RawLockSet
from pycross.private.tools.lock_model import ResolvedLockSet
from pycross.private.tools.lock_model import VariantItem
from pycross.private.tools.lock_model import VariantSet
from pycross.private.tools.lock_model import package_canonical_name


class VariantItemQualifiedNameTest(unittest.TestCase):
    """Test VariantItem.qualified_name for each kind."""

    def test_extra_kind(self):
        item = VariantItem(package="proj", kind="extra", name="cpu")
        self.assertEqual(item.qualified_name, "extra_cpu")

    def test_group_kind(self):
        item = VariantItem(package="proj", kind="group", name="test")
        self.assertEqual(item.qualified_name, "group_test")

    def test_project_kind(self):
        item = VariantItem(package="myapp", kind="project")
        self.assertEqual(item.qualified_name, "package_myapp")

    def test_project_kind_ignores_name(self):
        """Even if name is set, project kind uses the package field."""
        item = VariantItem(package="myapp", kind="project", name="ignored")
        self.assertEqual(item.qualified_name, "package_myapp")


class VariantSetSettingNameTest(unittest.TestCase):
    """Test VariantSet.setting_name generation."""

    def test_two_extras(self):
        cs = VariantSet(
            items=(
                VariantItem(package="proj", kind="extra", name="cpu"),
                VariantItem(package="proj", kind="extra", name="cu124"),
            )
        )
        self.assertEqual(cs.setting_name, "variants_extra_cpu_extra_cu124")

    def test_mixed_types(self):
        cs = VariantSet(
            items=(
                VariantItem(package="proj", kind="extra", name="cpu"),
                VariantItem(package="proj", kind="group", name="test"),
            )
        )
        self.assertEqual(cs.setting_name, "variants_extra_cpu_group_test")

    def test_single_item(self):
        cs = VariantSet(items=(VariantItem(package="proj", kind="extra", name="gpu"),))
        self.assertEqual(cs.setting_name, "variants_extra_gpu")

    def test_empty_items(self):
        cs = VariantSet(items=())
        self.assertEqual(cs.setting_name, "variants_")


class VariantItemDefaultTest(unittest.TestCase):
    """Test VariantItem.default field behaviour."""

    def test_default_is_false(self):
        item = VariantItem(package="proj", kind="extra", name="cpu")
        self.assertFalse(item.default)

    def test_default_can_be_true(self):
        item = VariantItem(package="proj", kind="extra", name="cpu", default=True)
        self.assertTrue(item.default)

    def test_default_does_not_affect_qualified_name(self):
        item_false = VariantItem(package="proj", kind="extra", name="cpu", default=False)
        item_true = VariantItem(package="proj", kind="extra", name="cpu", default=True)
        self.assertEqual(item_false.qualified_name, item_true.qualified_name)


class RawLockSetVariantsRoundtripTest(unittest.TestCase):
    """Test RawLockSet serialization roundtrip with variants."""

    def test_roundtrip(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            variants=[
                VariantSet(
                    items=(
                        VariantItem(package="proj", kind="extra", name="cpu"),
                        VariantItem(package="proj", kind="extra", name="cu124"),
                    )
                ),
            ],
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        self.assertEqual(restored.variants, lock.variants)
        self.assertEqual(len(restored.variants), 1)
        self.assertEqual(len(restored.variants[0].items), 2)
        self.assertEqual(restored.variants[0].items[0].name, "cpu")
        self.assertEqual(restored.variants[0].items[1].name, "cu124")

    def test_roundtrip_with_default_true(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            variants=[
                VariantSet(
                    items=(
                        VariantItem(package="proj", kind="extra", name="cpu", default=True),
                        VariantItem(package="proj", kind="extra", name="cu124"),
                    )
                ),
            ],
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        self.assertEqual(restored.variants, lock.variants)
        self.assertTrue(restored.variants[0].items[0].default)
        self.assertFalse(restored.variants[0].items[1].default)

    def test_roundtrip_preserves_kind(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            variants=[
                VariantSet(
                    items=(
                        VariantItem(package="proj", kind="extra", name="cpu"),
                        VariantItem(package="proj", kind="group", name="test"),
                    )
                ),
            ],
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        self.assertEqual(restored.variants[0].items[0].kind, "extra")
        self.assertEqual(restored.variants[0].items[1].kind, "group")


class PinsSerializationTest(unittest.TestCase):
    """Test that pins are simplified/expanded during serialization."""

    def test_unconditional_pin_serializes_as_bare_string(self):
        """A pin with only the empty-string key should serialize as a bare string."""
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            pins={"torch": {"": PackageKey("torch@2.6.0")}},
        )
        json_str = lock.to_json()
        parsed = json.loads(json_str)
        # The bare-string simplification should produce a plain string value.
        self.assertEqual(parsed["pins"]["torch"], "torch@2.6.0")

    def test_varianting_pins_stay_as_dict(self):
        """Pins with multiple constraint keys should remain as dicts."""
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            pins={
                "torch": {
                    "extra_cpu": PackageKey("torch@2.12.1"),
                    "extra_cu124": PackageKey("torch@2.6.0"),
                }
            },
        )
        json_str = lock.to_json()
        parsed = json.loads(json_str)
        self.assertIsInstance(parsed["pins"]["torch"], dict)
        self.assertEqual(parsed["pins"]["torch"]["extra_cpu"], "torch@2.12.1")
        self.assertEqual(parsed["pins"]["torch"]["extra_cu124"], "torch@2.6.0")

    def test_bare_string_deserializes_to_unconditional(self):
        """Deserializing a bare pin string should expand to {'': PackageKey(...)}."""
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            pins={"torch": {"": PackageKey("torch@2.6.0")}},
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        torch_name = package_canonical_name("torch")
        self.assertIn(torch_name, restored.pins)
        pin_value = restored.pins[torch_name]
        self.assertIsInstance(pin_value, dict)
        self.assertIn("", pin_value)
        self.assertEqual(pin_value[""], PackageKey("torch@2.6.0"))


class ResolvedLockSetVariantsRoundtripTest(unittest.TestCase):
    """Test ResolvedLockSet serialization roundtrip with variants."""

    def test_roundtrip(self):
        resolved = ResolvedLockSet(
            variants=[
                VariantSet(
                    items=(
                        VariantItem(package="proj", kind="extra", name="cpu"),
                        VariantItem(package="proj", kind="extra", name="cu124"),
                    )
                ),
            ],
        )
        json_str = resolved.to_json()
        restored = ResolvedLockSet.from_json(json_str)
        self.assertEqual(restored.variants, resolved.variants)

    def test_roundtrip_with_default(self):
        resolved = ResolvedLockSet(
            variants=[
                VariantSet(
                    items=(
                        VariantItem(package="proj", kind="extra", name="cpu", default=True),
                        VariantItem(package="proj", kind="extra", name="cu124"),
                    )
                ),
            ],
        )
        json_str = resolved.to_json()
        restored = ResolvedLockSet.from_json(json_str)
        self.assertEqual(restored.variants, resolved.variants)
        self.assertTrue(restored.variants[0].items[0].default)


class EmptyVariantsTest(unittest.TestCase):
    """Test that empty variants are omitted from serialized JSON."""

    def test_raw_lock_set_empty_variants_omitted(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            variants=[],
        )
        json_str = lock.to_json()
        parsed = json.loads(json_str)
        self.assertNotIn("variants", parsed)

    def test_raw_lock_set_empty_variants_roundtrip(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            variants=[],
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        self.assertEqual(restored.variants, [])

    def test_resolved_lock_set_empty_variants_omitted(self):
        resolved = ResolvedLockSet(variants=[])
        json_str = resolved.to_json()
        parsed = json.loads(json_str)
        self.assertNotIn("variants", parsed)


class ProjectLevelVariantsTest(unittest.TestCase):
    """Test VariantSet with project-level variant items."""

    def test_project_setting_name(self):
        cs = VariantSet(
            items=(
                VariantItem(package="app-a", kind="project"),
                VariantItem(package="app-b", kind="project"),
            )
        )
        self.assertEqual(cs.setting_name, "variants_package_app-a_package_app-b")

    def test_project_items_have_empty_name(self):
        item = VariantItem(package="app-a", kind="project")
        self.assertEqual(item.name, "")

    def test_project_variants_roundtrip(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            variants=[
                VariantSet(
                    items=(
                        VariantItem(package="app-a", kind="project"),
                        VariantItem(package="app-b", kind="project"),
                    )
                ),
            ],
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        self.assertEqual(restored.variants, lock.variants)
        self.assertEqual(restored.variants[0].items[0].kind, "project")
        self.assertEqual(restored.variants[0].items[0].package, "app-a")
        self.assertEqual(restored.variants[0].items[1].package, "app-b")


if __name__ == "__main__":
    unittest.main()
