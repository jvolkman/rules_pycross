"""Tests for conflict data model and pins serialization in lock_model.py."""

from __future__ import annotations

import json
import unittest

from packaging.specifiers import SpecifierSet

from pycross.private.tools.lock_model import (
    ConflictItem,
    ConflictSet,
    DependencyName,
    PackageKey,
    RawLockSet,
    ResolvedLockSet,
    package_canonical_name,
)


class ConflictItemQualifiedNameTest(unittest.TestCase):
    """Test ConflictItem.qualified_name for each kind."""

    def test_extra_kind(self):
        item = ConflictItem(package="proj", kind="extra", name="cpu")
        self.assertEqual(item.qualified_name, "extra_cpu")

    def test_group_kind(self):
        item = ConflictItem(package="proj", kind="group", name="test")
        self.assertEqual(item.qualified_name, "group_test")

    def test_project_kind(self):
        item = ConflictItem(package="myapp", kind="project")
        self.assertEqual(item.qualified_name, "package_myapp")

    def test_project_kind_ignores_name(self):
        """Even if name is set, project kind uses the package field."""
        item = ConflictItem(package="myapp", kind="project", name="ignored")
        self.assertEqual(item.qualified_name, "package_myapp")


class ConflictSetSettingNameTest(unittest.TestCase):
    """Test ConflictSet.setting_name generation."""

    def test_two_extras(self):
        cs = ConflictSet(items=(
            ConflictItem(package="proj", kind="extra", name="cpu"),
            ConflictItem(package="proj", kind="extra", name="cu124"),
        ))
        self.assertEqual(cs.setting_name, "conflicts_extra_cpu_extra_cu124")

    def test_mixed_types(self):
        cs = ConflictSet(items=(
            ConflictItem(package="proj", kind="extra", name="cpu"),
            ConflictItem(package="proj", kind="group", name="test"),
        ))
        self.assertEqual(cs.setting_name, "conflicts_extra_cpu_group_test")

    def test_single_item(self):
        cs = ConflictSet(items=(
            ConflictItem(package="proj", kind="extra", name="gpu"),
        ))
        self.assertEqual(cs.setting_name, "conflicts_extra_gpu")

    def test_empty_items(self):
        cs = ConflictSet(items=())
        self.assertEqual(cs.setting_name, "conflicts_")


class ConflictItemDefaultTest(unittest.TestCase):
    """Test ConflictItem.default field behaviour."""

    def test_default_is_false(self):
        item = ConflictItem(package="proj", kind="extra", name="cpu")
        self.assertFalse(item.default)

    def test_default_can_be_true(self):
        item = ConflictItem(package="proj", kind="extra", name="cpu", default=True)
        self.assertTrue(item.default)

    def test_default_does_not_affect_qualified_name(self):
        item_false = ConflictItem(package="proj", kind="extra", name="cpu", default=False)
        item_true = ConflictItem(package="proj", kind="extra", name="cpu", default=True)
        self.assertEqual(item_false.qualified_name, item_true.qualified_name)


class RawLockSetConflictsRoundtripTest(unittest.TestCase):
    """Test RawLockSet serialization roundtrip with conflicts."""

    def test_roundtrip(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            conflicts=[
                ConflictSet(items=(
                    ConflictItem(package="proj", kind="extra", name="cpu"),
                    ConflictItem(package="proj", kind="extra", name="cu124"),
                )),
            ],
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        self.assertEqual(restored.conflicts, lock.conflicts)
        self.assertEqual(len(restored.conflicts), 1)
        self.assertEqual(len(restored.conflicts[0].items), 2)
        self.assertEqual(restored.conflicts[0].items[0].name, "cpu")
        self.assertEqual(restored.conflicts[0].items[1].name, "cu124")

    def test_roundtrip_with_default_true(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            conflicts=[
                ConflictSet(items=(
                    ConflictItem(package="proj", kind="extra", name="cpu", default=True),
                    ConflictItem(package="proj", kind="extra", name="cu124"),
                )),
            ],
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        self.assertEqual(restored.conflicts, lock.conflicts)
        self.assertTrue(restored.conflicts[0].items[0].default)
        self.assertFalse(restored.conflicts[0].items[1].default)

    def test_roundtrip_preserves_kind(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            conflicts=[
                ConflictSet(items=(
                    ConflictItem(package="proj", kind="extra", name="cpu"),
                    ConflictItem(package="proj", kind="group", name="test"),
                )),
            ],
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        self.assertEqual(restored.conflicts[0].items[0].kind, "extra")
        self.assertEqual(restored.conflicts[0].items[1].kind, "group")


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

    def test_conflicting_pins_stay_as_dict(self):
        """Pins with multiple constraint keys should remain as dicts."""
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            pins={"torch": {
                "extra_cpu": PackageKey("torch@2.12.1"),
                "extra_cu124": PackageKey("torch@2.6.0"),
            }},
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


class ResolvedLockSetConflictsRoundtripTest(unittest.TestCase):
    """Test ResolvedLockSet serialization roundtrip with conflicts."""

    def test_roundtrip(self):
        resolved = ResolvedLockSet(
            conflicts=[
                ConflictSet(items=(
                    ConflictItem(package="proj", kind="extra", name="cpu"),
                    ConflictItem(package="proj", kind="extra", name="cu124"),
                )),
            ],
        )
        json_str = resolved.to_json()
        restored = ResolvedLockSet.from_json(json_str)
        self.assertEqual(restored.conflicts, resolved.conflicts)

    def test_roundtrip_with_default(self):
        resolved = ResolvedLockSet(
            conflicts=[
                ConflictSet(items=(
                    ConflictItem(package="proj", kind="extra", name="cpu", default=True),
                    ConflictItem(package="proj", kind="extra", name="cu124"),
                )),
            ],
        )
        json_str = resolved.to_json()
        restored = ResolvedLockSet.from_json(json_str)
        self.assertEqual(restored.conflicts, resolved.conflicts)
        self.assertTrue(restored.conflicts[0].items[0].default)


class EmptyConflictsTest(unittest.TestCase):
    """Test that empty conflicts are omitted from serialized JSON."""

    def test_raw_lock_set_empty_conflicts_omitted(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            conflicts=[],
        )
        json_str = lock.to_json()
        parsed = json.loads(json_str)
        self.assertNotIn("conflicts", parsed)

    def test_raw_lock_set_empty_conflicts_roundtrip(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            conflicts=[],
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        self.assertEqual(restored.conflicts, [])

    def test_resolved_lock_set_empty_conflicts_omitted(self):
        resolved = ResolvedLockSet(conflicts=[])
        json_str = resolved.to_json()
        parsed = json.loads(json_str)
        self.assertNotIn("conflicts", parsed)


class ProjectLevelConflictsTest(unittest.TestCase):
    """Test ConflictSet with project-level conflict items."""

    def test_project_setting_name(self):
        cs = ConflictSet(items=(
            ConflictItem(package="app-a", kind="project"),
            ConflictItem(package="app-b", kind="project"),
        ))
        self.assertEqual(cs.setting_name, "conflicts_package_app-a_package_app-b")

    def test_project_items_have_empty_name(self):
        item = ConflictItem(package="app-a", kind="project")
        self.assertEqual(item.name, "")

    def test_project_conflicts_roundtrip(self):
        lock = RawLockSet(
            python_versions=SpecifierSet(">=3.8"),
            conflicts=[
                ConflictSet(items=(
                    ConflictItem(package="app-a", kind="project"),
                    ConflictItem(package="app-b", kind="project"),
                )),
            ],
        )
        json_str = lock.to_json()
        restored = RawLockSet.from_json(json_str)
        self.assertEqual(restored.conflicts, lock.conflicts)
        self.assertEqual(restored.conflicts[0].items[0].kind, "project")
        self.assertEqual(restored.conflicts[0].items[0].package, "app-a")
        self.assertEqual(restored.conflicts[0].items[1].package, "app-b")


if __name__ == "__main__":
    unittest.main()
